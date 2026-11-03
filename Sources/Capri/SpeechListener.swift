import AVFoundation
import os
import Speech

/// Escucha el micrófono y transcribe en español de México (D-8), en el propio Mac si el sistema lo permite.
///
/// `start()` abre el micrófono; `stop()` lo cierra y espera el texto final; `cancel()` descarta todo.
/// Los callbacks llegan en el hilo principal.
final class SpeechListener {
    var onPartial: (String) -> Void = { _ in }
    var onLevel: (CGFloat) -> Void = { _ in }
    var onFinal: (String) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastText = ""
    private var finished = true
    private var lastLevelUpdate = Date.distantPast
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "escucha")
    /// Con CAPRI_DEBUG_TRANSCRIPT=1 el texto reconocido aparece en el registro (por defecto se oculta).
    private let logText = ProcessInfo.processInfo.environment["CAPRI_DEBUG_TRANSCRIPT"] == "1"

    var isListening: Bool { !finished }

    func start() {
        guard finished else { return }
        guard let recognizer, recognizer.isAvailable else {
            onError("El reconocimiento de voz no está disponible ahora.")
            return
        }
        finished = false
        lastText = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        let onDevice = recognizer.supportsOnDeviceRecognition
        if onDevice { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            self?.reportLevel(buffer)
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async { self?.handle(result: result, error: error) }
        }

        do {
            engine.prepare()
            try engine.start()
            log.notice("escuchando (en el dispositivo: \(onDevice, privacy: .public))")
        } catch {
            log.error("no se pudo abrir el micrófono: \(error.localizedDescription, privacy: .public)")
            teardown()
            finished = true
            onError("No pude abrir el micrófono.")
        }
    }

    /// Deja de grabar y espera el texto final. Si no llega pronto, entrega lo último reconocido.
    func stop() {
        guard !finished else { return }
        stopAudio()
        request?.endAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.finished else { return }
            self.log.notice("sin texto final a tiempo; se usa el último parcial")
            self.finish()
        }
    }

    func cancel() {
        guard !finished else { return }
        task?.cancel()
        teardown()
        finished = true
        log.notice("cancelado")
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        guard !finished else { return }
        if let result {
            lastText = Self.spanishPunctuation(result.bestTranscription.formattedString)
            onPartial(lastText)
            if result.isFinal { finish() }
        } else if let error {
            // Sin voz reconocible el sistema termina con error: se entrega lo que haya (quizá nada).
            log.notice("reconocimiento terminado: \(error.localizedDescription, privacy: .public)")
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        teardown()
        if logText {
            log.notice("texto final: \(self.lastText, privacy: .public)")
        } else {
            log.notice("texto final: \(self.lastText.count, privacy: .public) caracteres")
        }
        onFinal(lastText)
    }

    /// El reconocedor no pone los signos de apertura: "Cuál es…?" → "¿Cuál es…?".
    static func spanishPunctuation(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("?"), !t.hasPrefix("¿") { t = "¿" + t }
        if t.hasSuffix("!"), !t.hasPrefix("¡") { t = "¡" + t }
        return t
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        DispatchQueue.main.async { self.onLevel(0) }
    }

    private func teardown() {
        stopAudio()
        task = nil
        request = nil
    }

    /// Nivel del micrófono (0…1) para animar la onda, unas 20 veces por segundo como mucho.
    private func reportLevel(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastLevelUpdate) > 0.05 else { return }
        lastLevelUpdate = now
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = sqrt(sum / Float(buffer.frameLength))
        let db = 20 * log10(max(rms, 1e-6))
        let level = CGFloat(min(max((db + 50) / 45, 0), 1))  // -50 dB → 0, -5 dB → 1
        DispatchQueue.main.async { self.onLevel(level) }
    }
}
