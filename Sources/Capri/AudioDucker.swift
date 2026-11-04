import AudioToolbox
import CoreAudio
import os

/// Baja el sonido de las demás apps (Spotify, YouTube, cualquier cosa) mientras Capri escucha o habla, para que
/// su voz se entienda y el micrófono capte menos música. El volumen del Mac y la voz de Capri no cambian.
///
/// Usa un tap de procesos de Core Audio (macOS 14.2+): intercepta el audio de todas las apps menos Capri, lo
/// silencia en su salida normal y lo vuelve a reproducir, más bajo, por un dispositivo agregado privado sobre la
/// salida actual. Solo existe mientras dura la atenuación: en reposo no hay tap ni gasto de CPU.
///
/// Necesita el permiso de grabación de audio del sistema (Capri no graba ni guarda nada: macOS lo llama así).
/// Sin él, no atenúa: un tap sin permiso entrega silencio y, como silencia las apps, las callaría del todo.
final class AudioDucker {
    /// Volumen de las demás apps mientras Capri escucha o habla.
    static let duckedGain: Float = 0.25
    /// Duración de los fundidos de bajada y subida.
    static let fade: TimeInterval = 0.2
    /// Espera antes de subir el volumen: si llega otra orden enseguida, no sube y baja entre medias.
    static let releaseDelay: TimeInterval = 0.3

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    /// Ganancia compartida con el hilo de audio: la escribe este objeto y la lee el bloque de E/S.
    private let gain = Gain()
    /// Cada bajada o subida invalida las anteriores (una subida pendiente no apaga una bajada nueva).
    private var generation = 0
    private let ioQueue = DispatchQueue(label: "com.rosvjames.capri.atenuar", qos: .userInteractive)
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "atenuar")

    var isActive: Bool { ioProc != nil }

    func duck() {
        generation += 1
        if isActive {
            gain.target = Self.duckedGain
            return
        }
        switch AudioCapturePermission.status {
        case .granted:
            break
        case .unknown:
            // La primera vez se pide el permiso; esta vez Capri habla sin atenuar.
            AudioCapturePermission.request { [log] granted in
                log.notice("permiso de audio del sistema: \(granted ? "concedido" : "denegado", privacy: .public)")
            }
            return
        case .denied:
            return
        }
        guard #available(macOS 14.2, *) else { return }
        do {
            try start()
            gain.target = Self.duckedGain
            log.notice("atenuando las demás apps")
        } catch {
            log.error("no se pudo atenuar: \(String(describing: error), privacy: .public)")
            teardown()
        }
    }

    /// Sube el volumen con un fundido, tras una espera corta, y quita el tap.
    func release() {
        guard isActive else { return }
        generation += 1
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay) { [self] in
            guard current == generation else { return }
            gain.target = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fade + 0.05) { [self] in
                guard current == generation else { return }
                // Nivel máximo que llegó de las demás apps: 0 con música sonando querría decir que falta el permiso.
                let peak = gain.peak
                teardown()
                log.notice("volumen de las demás apps restablecido (nivel máximo recibido: \(peak, format: .fixed(precision: 3)))")
            }
        }
    }

    // MARK: Core Audio

    private struct Failure: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "\(step): \(status)" }
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        if status != noErr { throw Failure(step: step, status: status) }
    }

    @available(macOS 14.2, *)
    private func start() throws {
        // Capri queda fuera del tap: su voz suena como siempre.
        guard let me = Self.ownProcessObject() else { throw Failure(step: "proceso de Capri sin objeto de audio", status: -1) }
        guard let output = Self.defaultOutputDevice(), let outputUID = Self.uid(of: output) else {
            throw Failure(step: "sin salida de audio", status: -1)
        }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [me])
        description.name = "Capri"
        description.isPrivate = true
        description.muteBehavior = .muted
        try check(AudioHardwareCreateProcessTap(description, &tap), "crear el tap")

        guard let format = Self.tapFormat(tap), format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            throw Failure(step: "formato del tap no esperado", status: -1)
        }

        let settings: [String: Any] = [
            kAudioAggregateDeviceUIDKey: "com.rosvjames.capri.atenuar." + UUID().uuidString,
            kAudioAggregateDeviceNameKey: "Capri (atenuar)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        try check(AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregate), "crear el dispositivo agregado")

        // En el agregado, las entradas propias de la salida (el micrófono de unos AirPods) van antes que el tap.
        let tapIndex = Self.streamCount(of: output, scope: kAudioObjectPropertyScopeInput)
        let sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 48_000
        let step = Float(1 / (Self.fade * sampleRate))
        let gain = gain
        gain.current = 1
        gain.target = 1
        gain.peak = 0
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, ioQueue) { _, input, _, output, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputs = UnsafeMutableAudioBufferListPointer(output)
            for buffer in outputs { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
            guard inputs.count > 0, let out = outputs.first, let outData = out.mData else { return }
            let source = inputs[min(tapIndex, inputs.count - 1)]
            guard let inData = source.mData else { return }
            let inChannels = max(Int(source.mNumberChannels), 1)
            let outChannels = max(Int(out.mNumberChannels), 1)
            let frames = min(Int(source.mDataByteSize) / (4 * inChannels), Int(out.mDataByteSize) / (4 * outChannels))
            let src = inData.assumingMemoryBound(to: Float.self)
            let dst = outData.assumingMemoryBound(to: Float.self)
            var current = gain.current
            let target = gain.target
            var peak = gain.peak
            for frame in 0..<frames {
                peak = max(peak, abs(src[frame * inChannels]))
                if current < target { current = min(current + step, target) } else if current > target { current = max(current - step, target) }
                for channel in 0..<outChannels {
                    dst[frame * outChannels + channel] = src[frame * inChannels + min(channel, inChannels - 1)] * current
                }
            }
            gain.current = current
            gain.peak = peak
        }, "crear la función de audio")
        try check(AudioDeviceStart(aggregate, ioProc), "arrancar el dispositivo agregado")
    }

    private func teardown() {
        if let ioProc {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
        }
        ioProc = nil
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        aggregate = AudioObjectID(kAudioObjectUnknown)
        // Al quitar el tap, las apps vuelven a sonar por su salida normal.
        if #available(macOS 14.2, *), tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { teardown() }

    // MARK: Consultas

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func ownProcessObject() -> AudioObjectID? {
        var pid = getpid()
        var where_ = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var where_ = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func uid(of device: AudioDeviceID) -> String? {
        var where_ = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private static func streamCount(of device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var where_ = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &where_, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private static func tapFormat(_ tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var where_ = address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        return AudioObjectGetPropertyData(tap, &where_, 0, nil, &size, &format) == noErr ? format : nil
    }
}

/// Ganancia que lee el hilo de audio. Un Float alineado se lee y escribe entero en Apple Silicon: basta para
/// un valor que solo marca hacia dónde ir.
private final class Gain: @unchecked Sendable {
    var current: Float = 1
    var target: Float = 1
    var peak: Float = 0
}

/// El permiso de grabación de audio del sistema no tiene API pública para consultarlo ni pedirlo; se usa la del
/// sistema de privacidad (TCC), como hacen otras apps que usan taps. Si no está disponible, se intenta igual.
enum AudioCapturePermission {
    enum Status { case granted, denied, unknown }

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    static var status: Status {
        guard let symbol = framework.flatMap({ dlsym($0, "TCCAccessPreflight") }) else { return .granted }
        switch unsafeBitCast(symbol, to: Preflight.self)(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    /// Muestra el aviso del permiso. `done` llega en el hilo principal.
    static func request(_ done: @escaping (Bool) -> Void) {
        guard let symbol = framework.flatMap({ dlsym($0, "TCCAccessRequest") }) else { return done(true) }
        unsafeBitCast(symbol, to: Request.self)(service, nil) { granted in
            DispatchQueue.main.async { done(granted) }
        }
    }
}
