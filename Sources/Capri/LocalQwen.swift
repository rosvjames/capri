import Foundation
import os

/// Puente local por JSONL: el proceso mantiene el modelo cargado entre respuestas.
/// Ningún texto sale del Mac. Cancelar una generación termina el proceso para que no deje audio pendiente.
final class LocalQwen {
    private struct Pending {
        let id: UUID
        let output: URL
        let completion: (Result<URL, Error>) -> Void
    }

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var received = Data()
    private var pending: Pending?
    private var timeout: DispatchWorkItem?
    private var startedAt = Date()
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "qwen")

    func generate(_ text: String, completion: @escaping (Result<URL, Error>) -> Void) {
        cancel()
        let id = UUID()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capri-qwen-\(id).wav")
        do {
            try startIfNeeded()
            pending = Pending(id: id, output: url, completion: completion)
            var line = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "text": text, "output": url.path])
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
            try? FileManager.default.removeItem(at: url)
            completion(.failure(error))
        }
    }

    /// Arranca el proceso y carga el modelo (~4 s) sin pedir audio, para que la primera respuesta no espere la carga.
    func warmUp() {
        do { try startIfNeeded() } catch { log.error("no se pudo precargar Qwen: \(error.localizedDescription, privacy: .public)") }
    }

    func cancel() {
        guard let request = pending else { return }
        pending = nil
        shutdown()
        try? FileManager.default.removeItem(at: request.output)
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

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }
        shutdown()
        let python = ProcessInfo.processInfo.environment["CAPRI_QWEN_PYTHON"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".venvs/capri-tts/bin/python").path
        guard FileManager.default.isExecutableFile(atPath: python),
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
            guard object["event"] as? String == "audio" else {
                fail(object["error"] as? String ?? "No se pudo generar la voz.")
                return
            }
            pending = nil
            timeout?.cancel()
            timeout = nil
            request.completion(.success(request.output))
        }
    }

    private func fail(_ message: String) {
        let request = pending
        pending = nil
        shutdown()
        if let request { try? FileManager.default.removeItem(at: request.output) }
        log.error("\(message, privacy: .public)")
        request?.completion(.failure(NSError(domain: "Capri.Qwen", code: 2,
                                             userInfo: [NSLocalizedDescriptionKey: message])))
    }
}
