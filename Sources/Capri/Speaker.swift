import AVFoundation
import os

/// Demo con Qwen local y la referencia 2 elegida. CAPRI_TTS=paulina permite comparar con la voz anterior.
///
/// Qwen entrega un WAV; Paulina entrega bloques (`write`). Ambos pasan por el mismo
/// `AVAudioPlayerNode` y su volumen se mide cada 20 ms para sincronizar la boca (`level()`).
final class Speaker {
    var onStart: () -> Void = {}
    var onFinish: () -> Void = {}
    var onPreparing: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let qwen = LocalQwen()
    private var engineStopWork: DispatchWorkItem?
    private let usePaulina = ProcessInfo.processInfo.environment["CAPRI_TTS"] == "paulina"
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
    private(set) var isPreparing = false
    var isBusy: Bool { isSpeaking || isPreparing }

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
        isPreparing = true
        onPreparing()

        // El saludo del demo usa una toma concreta para mantener el registro elegido,
        // sin volver a variar la interpretación ni alterar las otras respuestas.
        if !usePaulina, text == DemoReply.greeting,
           let url = Bundle.module.url(forResource: "capri-qwen-greeting", withExtension: "wav") {
            DispatchQueue.main.async { [weak self] in self?.playFile(url, id: id) }
            return
        }

        if !usePaulina {
            qwen.generate(text) { [weak self] result in
                guard let self else { return }
                guard id == self.utteranceID else {
                    if case .success(let url) = result { try? FileManager.default.removeItem(at: url) }
                    return
                }
                switch result {
                case .success(let url):
                    defer { try? FileManager.default.removeItem(at: url) }
                    self.playFile(url, id: id)
                case .failure(let error): self.failed(error)
                }
            }
            return
        }

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

    /// Se llama al empezar a escuchar: el modelo carga mientras hablas y la respuesta solo espera la generación.
    func prepare() {
        if !usePaulina { qwen.warmUp() }
    }

    private func playFile(_ url: URL, id: Int) {
        guard id == utteranceID else { return }
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
            else { throw NSError(domain: "Capri.Qwen", code: 3) }
            try file.read(into: buffer)
            log.notice("reproduciendo la voz Qwen elegida")
            receive(buffer, id: id)
            receive(nil, id: id)
        } catch { failed(error) }
    }

    func stop() {
        utteranceID += 1
        synthesizer.stopSpeaking(at: .immediate)
        player.stop()
        scheduleEngineStop()
        qwen.cancel()
        let wasSpeaking = isBusy
        isSpeaking = false
        isPreparing = false
        envelope = []
        carry = []
        if wasSpeaking { onFinish() }
    }

    /// Un motor encendido sin sonar gasta ~0,3 % de CPU, así que se apaga; pero no al terminar cada frase:
    /// esperar unos segundos evita el clic de apagar y encender la salida entre frases seguidas.
    private func scheduleEngineStop() {
        engineStopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isSpeaking else { return }
            self.engine.stop()
        }
        engineStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    func shutdown() {
        stop()
        engineStopWork?.cancel()
        engine.stop()
        qwen.shutdown()
    }

    private func failed(_ error: Error) {
        log.error("no se pudo generar la voz: \(error.localizedDescription, privacy: .public)")
        stop()
        onError("No pude reproducir la voz. Inténtalo de nuevo.")
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
        guard heard >= 0 else { return nil }
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
            engineStopWork?.cancel()
            do {
                if !engine.isRunning { try engine.start() }
                player.play()
                isSpeaking = true
                isPreparing = false
                onStart()
            } catch {
                log.error("no se pudo reproducir la voz: \(error.localizedDescription, privacy: .public)")
                failed(error)
            }
        }
    }

    private func finishIfDone(id: Int) {
        guard id == utteranceID, generationDone, pendingBuffers == 0 else { return }
        isSpeaking = false
        isPreparing = false
        player.stop()
        scheduleEngineStop()
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
