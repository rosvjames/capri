import AVFoundation
import os

/// Puente local por JSONL: el proceso mantiene el modelo cargado entre respuestas.
/// El audio llega por trozos mientras se genera (el primero en ~0,7 s), así que Capri empieza a hablar
/// sin esperar la frase entera. Ningún texto sale del Mac. Cancelar una generación termina el proceso
/// para que no deje audio pendiente.
final class LocalQwen {
    private struct Pending {
        let id: UUID
        let onChunk: (AVAudioPCMBuffer) -> Void
        let completion: (Result<Void, Error>) -> Void
    }

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var received = Data()
    private var pending: Pending?
    private var timeout: DispatchWorkItem?
    private var startedAt = Date()
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "qwen")

    /// `onChunk` recibe cada trozo de audio en orden; `completion`, el final de la frase o el error.
    func generate(_ text: String, onChunk: @escaping (AVAudioPCMBuffer) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        cancel()
        let id = UUID()
        do {
            try startIfNeeded()
            pending = Pending(id: id, onChunk: onChunk, completion: completion)
            var line = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "text": text])
            line.append(0x0A)
            try input?.write(contentsOf: line)
            let deadline = DispatchWorkItem { [weak self] in
                guard let self, self.pending?.id == id else { return }
                self.fail("La generación local de voz tardó demasiado.")
            }
            timeout = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: deadline)
        } catch {
            pending = nil
            shutdown()
            completion(.failure(error))
        }
    }

    /// Arranca el proceso y carga el modelo (~4 s) sin pedir audio, para que la primera respuesta no espere la carga.
    func warmUp() {
        do { try startIfNeeded() } catch { log.error("no se pudo precargar Qwen: \(error.localizedDescription, privacy: .public)") }
    }

    func cancel() {
        guard pending != nil else { return }
        pending = nil
        shutdown()
    }

    func shutdown() {
        timeout?.cancel()
        timeout = nil
        output?.readabilityHandler = nil
        try? output?.close()
        try? input?.close()
        output = nil
        input = nil
        received = Data()
        let previous = process
        process = nil
        previous?.terminationHandler = nil
        if previous?.isRunning == true { previous?.terminate() }
    }

    private static var python: String {
        ProcessInfo.processInfo.environment["CAPRI_QWEN_PYTHON"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".venvs/capri-tts/bin/python").path
    }

    /// Hay entorno de Python y referencia de voz (WAV y su transcripción .txt). La referencia no está en el
    /// repositorio, así que en un clon nuevo falta y Capri usa la voz del sistema.
    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: python)
            && Bundle.module.url(forResource: "qwen-speaker", withExtension: "py") != nil
            && Bundle.module.url(forResource: "capri-qwen-ref2", withExtension: "wav") != nil
            && Bundle.module.url(forResource: "capri-qwen-ref2", withExtension: "txt") != nil
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }
        shutdown()
        let python = Self.python
        guard Self.isAvailable,
              let script = Bundle.module.url(forResource: "qwen-speaker", withExtension: "py"),
              let reference = Bundle.module.url(forResource: "capri-qwen-ref2", withExtension: "wav")
        else { throw NSError(domain: "Capri.Qwen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Falta el entorno local de Qwen o la referencia de voz."]) }

        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = URL(fileURLWithPath: python)
        child.arguments = ["-u", script.path, "--reference", reference.path]
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        child.environment = environment
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self, weak child] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let self, let child, self.process === child else { return }
                self.consume(data)
            }
        }
        child.terminationHandler = { [weak self] child in
            DispatchQueue.main.async {
                guard let self, self.process === child else { return }
                self.fail("El proceso local de voz terminó (\(child.terminationStatus)).")
            }
        }
        process = child
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        try child.run()
        startedAt = Date()
        log.notice("motor Qwen local iniciado")
    }

    private func consume(_ data: Data) {
        received.append(data)
        while let end = received.firstIndex(of: 0x0A) {
            let line = received.prefix(upTo: end)
            received.removeSubrange(...end)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if object["event"] as? String == "ready" {
                log.notice("modelo Qwen cargado en \(Date().timeIntervalSince(self.startedAt), format: .fixed(precision: 1)) s")
                continue
            }
            if object["event"] as? String == "fatal" {
                fail(object["error"] as? String ?? "No se pudo cargar Qwen.")
                return
            }
            guard let request = pending, object["id"] as? String == request.id.uuidString else { continue }
            switch object["event"] as? String {
            case "chunk":
                guard let buffer = Self.buffer(from: object) else {
                    fail("La voz local devolvió un trozo de audio no válido.")
                    return
                }
                request.onChunk(buffer)
            case "done":
                pending = nil
                timeout?.cancel()
                timeout = nil
                request.completion(.success(()))
            default:
                fail(object["error"] as? String ?? "No se pudo generar la voz.")
                return
            }
        }
    }

    /// PCM de 16 bits en base64 → bloque de audio en coma flotante, como los del sintetizador del sistema.
    private static func buffer(from object: [String: Any]) -> AVAudioPCMBuffer? {
        guard let encoded = object["pcm"] as? String, let data = Data(base64Encoded: encoded),
              let rate = object["rate"] as? Double,
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 2)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = buffer.frameCapacity
        data.withUnsafeBytes { raw in
            for (i, sample) in raw.bindMemory(to: Int16.self).enumerated() {
                channel[i] = Float(Int16(littleEndian: sample)) / 32767
            }
        }
        return buffer
    }

    private func fail(_ message: String) {
        let request = pending
        pending = nil
        shutdown()
        log.error("\(message, privacy: .public)")
        request?.completion(.failure(NSError(domain: "Capri.Qwen", code: 2,
                                             userInfo: [NSLocalizedDescriptionKey: message])))
    }
}
