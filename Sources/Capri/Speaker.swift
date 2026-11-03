import AVFoundation
import os

/// Voz de Capri: Paulina (es-MX) en la mejor calidad instalada (Premium > mejorada > estándar), D-5 y D-8.
/// La voz se elige en cada frase, así que al descargar una versión mejor se usa sin reiniciar.
///
/// El audio no lo reproduce el sintetizador: se recibe en bloques (`write`), se reproduce con un
/// `AVAudioPlayerNode` propio y se mide su volumen cada 20 ms. Así la boca de Capri puede seguir
/// exactamente lo que se está oyendo (`level(at:)`).
final class Speaker {
    var onStart: () -> Void = {}
    var onFinish: () -> Void = {}

    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "voz")

    /// Volumen (dB) de cada ventana de 20 ms de la frase actual, en orden.
    private var envelope: [Float] = []
    private static let window: TimeInterval = 0.02
    /// Muestras pendientes de completar una ventana (los bloques del sintetizador no coinciden con 20 ms).
    private var carry: [Float] = []
    private var sampleRate: Double = 22_050
    /// Identifica la frase en curso: los avisos de una frase cancelada se ignoran.
    private var utteranceID = 0
    private var pendingBuffers = 0
    private var generationDone = false
    private(set) var isSpeaking = false

    init() {
        engine.attach(player)
    }

    func speak(_ text: String) {
        stop()
        utteranceID += 1
        let id = utteranceID
        envelope = []
        carry = []
        pendingBuffers = 0
        generationDone = false

        let utterance = AVSpeechUtterance(string: text)
        let voice = Self.bestVoice()
        utterance.voice = voice
        log.notice("hablando con \(voice?.name ?? "voz por defecto", privacy: .public) (\(Self.qualityName(voice), privacy: .public))")

        synthesizer.write(utterance) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            // Copia: el sintetizador puede reutilizar el bloque al volver de este callback.
            let copy = pcm.frameLength > 0 ? pcm.copy() as? AVAudioPCMBuffer : nil
            DispatchQueue.main.async { self?.receive(copy, id: id) }
        }
    }

    func stop() {
        utteranceID += 1
        synthesizer.stopSpeaking(at: .immediate)
        player.stop()
        engine.stop()  // un motor de audio encendido sin sonar gasta CPU: se apaga entre frases
        let wasSpeaking = isSpeaking
        isSpeaking = false
        envelope = []
        if wasSpeaking { onFinish() }
    }

    /// Volumen (dB) de lo que se está oyendo ahora mismo, o nil si no suena nada.
    /// Tiene en cuenta la latencia de salida: el audio llega al altavoz un poco después de reproducirse.
    func level() -> Float? {
        guard isSpeaking,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return nil }
        let latency = engine.outputNode.presentationLatency
        let heard = Double(playerTime.sampleTime) / playerTime.sampleRate - latency
        let index = Int(heard / Self.window)
        guard index >= 0, index < envelope.count else { return nil }
        return envelope[index]
    }

    private func receive(_ buffer: AVAudioPCMBuffer?, id: Int) {
        guard id == utteranceID else { return }
        guard let buffer else {
            // Bloque vacío: el sintetizador terminó de generar.
            generationDone = true
            finishIfDone(id: id)
            return
        }
        if connectedFormat != buffer.format {
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            connectedFormat = buffer.format
            sampleRate = buffer.format.sampleRate
        }
        analyze(buffer)
        pendingBuffers += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, id == self.utteranceID else { return }
                self.pendingBuffers -= 1
                self.finishIfDone(id: id)
            }
        }
        if !isSpeaking {
            do {
                if !engine.isRunning { try engine.start() }
                player.play()
                isSpeaking = true
                onStart()
            } catch {
                log.error("no se pudo reproducir la voz: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func finishIfDone(id: Int) {
        guard id == utteranceID, generationDone, pendingBuffers == 0 else { return }
        isSpeaking = false
        player.stop()
        engine.stop()
        onFinish()
    }

    /// Añade a `envelope` el volumen de cada ventana completa de 20 ms.
    private func analyze(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        carry += UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        let size = Int(sampleRate * Self.window)
        var start = 0
        while start + size <= carry.count {
            var sum: Float = 0
            for i in start..<(start + size) { sum += carry[i] * carry[i] }
            envelope.append(20 * log10(max(sqrt(sum / Float(size)), 1e-6)))
            start += size
        }
        carry.removeFirst(start)
    }

    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let mexican = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "es-MX" }
        let byQuality = { (a: AVSpeechSynthesisVoice, b: AVSpeechSynthesisVoice) in a.quality.rawValue > b.quality.rawValue }
        return mexican.filter { $0.name.hasPrefix("Paulina") }.sorted(by: byQuality).first
            ?? mexican.sorted(by: byQuality).first
            ?? AVSpeechSynthesisVoice(language: "es-MX")
    }

    private static func qualityName(_ voice: AVSpeechSynthesisVoice?) -> String {
        switch voice?.quality {
        case .premium: "premium"
        case .enhanced: "mejorada"
        default: "estándar"
        }
    }
}
