import Foundation
import os

/// Modelo local servido por Ollama (`/api/chat`): nada sale del Mac y no cuesta nada.
/// Gemma 4 12B responde una pregunta corta en ~1 s en un M1 Max y ocupa ~9 GB mientras está cargado;
/// Ollama lo descarga de la memoria 10 minutos después de la última pregunta.
final class OllamaBrain: Brain {
    /// CAPRI_MODELO o `defaults write com.rosvjames.capri modelo …` lo cambian (la app abierta con `open` no recibe variables de entorno).
    let model = ProcessInfo.processInfo.environment["CAPRI_MODELO"]
        ?? UserDefaults.standard.string(forKey: "modelo")
        ?? "gemma4:12b"
    private let endpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    private var task: URLSessionDataTask?
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "llm")

    func warmUp() {
        // Con la lista de mensajes vacía, Ollama solo carga el modelo.
        send(["model": model, "messages": [], "keep_alive": "10m"]) { [log, model] result in
            if case .failure(let error) = result {
                log.error("no se pudo precargar \(model, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func respond(to messages: [ChatMessage], completion: @escaping (Result<String, Error>) -> Void) {
        cancel()
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
            "think": false,
            "keep_alive": "10m",
            "options": ["temperature": 0.3],
        ]
        let start = Date()
        task = send(body) { [log, model] result in
            completion(result.flatMap { json in
                guard let message = json["message"] as? [String: Any], let content = message["content"] as? String else {
                    return .failure(BrainError(spoken: "El modelo me respondió algo que no entiendo."))
                }
                log.notice("\(model, privacy: .public) respondió en \(Date().timeIntervalSince(start), format: .fixed(precision: 2)) s")
                return .success(content)
            })
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    @discardableResult
    private func send(_ body: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) -> URLSessionDataTask? {
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let model = model
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<[String: Any], Error>
            if let error = error as? URLError {
                switch error.code {
                case .cancelled: return
                case .cannotConnectToHost, .networkConnectionLost:
                    result = .failure(BrainError(spoken: "No encuentro Ollama. Ábrelo y vuelve a preguntarme."))
                case .timedOut:
                    result = .failure(BrainError(spoken: "El modelo tardó demasiado en responder."))
                default:
                    result = .failure(error)
                }
            } else if let error {
                result = .failure(error)
            } else if (response as? HTTPURLResponse)?.statusCode == 404 {
                result = .failure(BrainError(spoken: "Falta el modelo \(model) en Ollama."))
            } else if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let message = json["error"] as? String {
                    result = .failure(BrainError(spoken: "Ollama dio un error: \(message)"))
                } else {
                    result = .success(json)
                }
            } else {
                result = .failure(BrainError(spoken: "El modelo me respondió algo que no entiendo."))
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }
}
