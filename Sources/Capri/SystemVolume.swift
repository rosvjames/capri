import AudioToolbox
import CoreAudio

/// Volumen de la salida de audio actual del Mac (C-36), por Core Audio: sin AppleScript ni permisos.
/// Algunas salidas (HDMI, ciertas interfaces) no dejan cambiarlo: entonces `level` es nil.
enum SystemVolume {
    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static var output: AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var where_ = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// Volumen de 0 a 1 (el mismo que mueven las teclas de volumen).
    static var level: Float? {
        guard let device = output else { return nil }
        var where_ = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &where_),
              AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setLevel(_ level: Float) -> Bool {
        guard let device = output else { return false }
        var where_ = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value = Float32(min(max(level, 0), 1))
        return AudioObjectSetPropertyData(device, &where_, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    static var isMuted: Bool? {
        guard let device = output else { return nil }
        var where_ = address(kAudioDevicePropertyMute)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &where_),
              AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = output else { return false }
        var where_ = address(kAudioDevicePropertyMute)
        // Sin silencio propio (algunas salidas), quitarlo no hace falta y ponerlo es bajar a cero.
        guard AudioObjectHasProperty(device, &where_) else { return muted ? setLevel(0) : true }
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &where_, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
