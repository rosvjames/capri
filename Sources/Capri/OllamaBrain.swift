import Foundation
import os

/// Modelo local servido por Ollama (`/api/chat`): nada sale del Mac y no cuesta nada.
/// Gemma 4 12B responde una pregunta corta en ~1–2 s en un M1 Max y ocupa ~9 GB mientras está cargado;
/// Ollama lo descarga de la memoria 10 minutos después de la última pregunta.
/// La respuesta llega en streaming: la primera frase está lista en una fracción de ese tiempo.
final class OllamaBrain: Brain {
    /// CAPRI_MODELO o `defaults write com.rosvjames.capri modelo …` lo cambian (la app abierta con `open` no recibe variables de entorno).
    let model = ProcessInfo.processInfo.environment["CAPRI_MODELO"]
        ?? UserDefaults.standard.string(forKey: "modelo")
        ?? "gemma4:12b"
    private let endpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    private var task: Task<Void, Never>?
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "llm")

    func warmUp() {
        // Con la lista de mensajes vacía, Ollama solo carga el modelo.
        let request = request(["model": model, "messages": [], "keep_alive": "10m", "stream": false])
        URLSession.shared.dataTask(with: request) { [log, model] _, _, error in
            if let error {
                log.error("no se pudo precargar \(model, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }.resume()
    }

    func respond(to messages: [ChatMessage], onPartial: @escaping (String) -> Void,
                 completion: @escaping (Result<String, Error>) -> Void) {
        cancel()
        let request = request([
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
            "think": false,
            "keep_alive": "10m",
            "options": ["temperature": 0.3],
        ])
        let start = Date()
        task = Task { [log, model] in
            var text = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 404 {
                    throw BrainError(spoken: "Falta el modelo \(model) en Ollama.")
                }
                // Una línea JSON por trozo de texto; la última lleva "done".
                for try await line in bytes.lines {
                    guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                    if let message = json["error"] as? String { throw BrainError(spoken: "Ollama dio un error: \(message)") }
                    if let piece = (json["message"] as? [String: Any])?["content"] as? String, !piece.isEmpty {
                        if text.isEmpty {
                            log.notice("\(model, privacy: .public): primer texto en \(Date().timeIntervalSince(start), format: .fixed(precision: 2)) s")
                        }
                        text += piece
                        let partial = text
                        await MainActor.run { if !Task.isCancelled { onPartial(partial) } }
                    }
                    if json["done"] as? Bool == true { break }
                }
                log.notice("\(model, privacy: .public) respondió en \(Date().timeIntervalSince(start), format: .fixed(precision: 2)) s")
                let result = text
                await MainActor.run { if !Task.isCancelled { completion(.success(result)) } }
            } catch {
                let failure = Self.describe(error, model: model)
                await MainActor.run { if !Task.isCancelled, let failure { completion(.failure(failure)) } }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func request(_ body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Error con una frase que Capri pueda decir, o nil si se canceló.
    private static func describe(_ error: Error, model: String) -> Error? {
        if error is CancellationError { return nil }
        guard let error = error as? URLError else { return error }
        switch error.code {
        case .cancelled: return nil
        case .cannotConnectToHost, .networkConnectionLost:
            return BrainError(spoken: "No encuentro Ollama. Ábrelo y vuelve a preguntarme.")
        case .timedOut:
            return BrainError(spoken: "El modelo tardó demasiado en responder.")
        default:
            return error
        }
    }
}
