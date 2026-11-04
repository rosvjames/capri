import Foundation
import os
import Security

/// Claude por la API de Anthropic (`/v1/messages` en streaming), sin SDK: no hay uno oficial para Swift.
/// No ocupa memoria del Mac, a diferencia de Gemma, pero la pregunta (y lo copiado, si la frase lo pide)
/// sale del Mac y cada respuesta cuesta. Con Haiku, ~US$0,0002 por pregunta; con Sonnet, ~US$0,003.
final class ClaudeBrain: Brain {
    let model: String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private var task: Task<Void, Never>?
    private var key: String?
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "llm")

    init(model: String) {
        self.model = model
    }

    /// Abre la conexión (TLS) mientras James habla, para que la pregunta no espere el saludo con el servidor.
    /// Listar modelos no cuesta nada.
    func warmUp(with messages: [ChatMessage]) {
        guard let key = apiKey() else { return }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!, timeoutInterval: 10)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        URLSession.shared.dataTask(with: request).resume()
    }

    func respond(to messages: [ChatMessage], onPartial: @escaping (String) -> Void,
                 completion: @escaping (Result<String, Error>) -> Void) {
        cancel()
        guard let key = apiKey() else {
            completion(.failure(BrainError(spoken: "Me falta la clave de la API de Anthropic en el Llavero.")))
            return
        }
        guard let request = request(messages, key: key) else {
            completion(.failure(BrainError(spoken: "No pude preparar la pregunta.")))
            return
        }
        let start = Date()
        task = Task { [log, model] in
            var text = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                    var body = Data()
                    for try await byte in bytes { body.append(byte) }
                    throw Self.httpError(status: status, body: body)
                }
                // Eventos SSE: solo importan las líneas "data:"; el texto llega en content_block_delta.
                for try await line in bytes.lines {
                    guard line.hasPrefix("data:"),
                          let json = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any]
                    else { continue }
                    switch json["type"] as? String {
                    case "content_block_delta":
                        guard let delta = json["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                              let piece = delta["text"] as? String, !piece.isEmpty else { continue }
                        if text.isEmpty {
                            log.notice("\(model, privacy: .public): primer texto en \(Date().timeIntervalSince(start), format: .fixed(precision: 2)) s")
                        }
                        text += piece
                        let partial = text
                        await MainActor.run { if !Task.isCancelled { onPartial(partial) } }
                    case "message_delta":
                        if (json["delta"] as? [String: Any])?["stop_reason"] as? String == "refusal", text.isEmpty {
                            throw BrainError(spoken: "Eso no te lo puedo responder.")
                        }
                    case "error":
                        let message = (json["error"] as? [String: Any])?["message"] as? String ?? ""
                        log.error("error de la API en el streaming: \(message, privacy: .public)")
                        throw BrainError(spoken: "La API tuvo un problema. Inténtalo de nuevo.")
                    default:
                        continue
                    }
                }
                log.notice("\(model, privacy: .public) respondió en \(Date().timeIntervalSince(start), format: .fixed(precision: 2)) s")
                let result = text
                await MainActor.run { if !Task.isCancelled { completion(.success(result)) } }
            } catch {
                let failure = Self.describe(error)
                await MainActor.run { if !Task.isCancelled, let failure { completion(.failure(failure)) } }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    static let apiVersion = "2026-10-21"

    private func request(_ messages: [ChatMessage], key: String) -> URLRequest? {
        let system = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
        var body: [String: Any] = [
            "model": model,
            // Respuestas de una o dos frases y, como mucho, un bloque para copiar.
            "max_tokens": 1024,
            "stream": true,
            "system": system,
            "messages": messages.filter { $0.role != "system" }.map { ["role": $0.role, "content": $0.content] },
            "output_config": ["effort": "low"],
        ]
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        // Sin razonamiento previo: para preguntas rápidas solo añade espera. Haiku lo acepta con esfuerzo bajo;
        // Sonnet 5.5 no acepta "disabled" y lo apaga con "between_tools".
        if model.hasPrefix("claude-sonnet") {
            body["thinking"] = ["type": "between_tools"]
            // Si los filtros de seguridad rechazan la respuesta, la API la repite con otro modelo en la misma llamada.
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        } else {
            body["thinking"] = ["type": "disabled"]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Error HTTP de la API → frase corta para decir en voz; el detalle queda en el registro.
    private static func httpError(status: Int, body: Data) -> Error {
        let message = ((try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? [String: Any])?["message"] as? String ?? ""
        Logger(subsystem: "com.rosvjames.capri", category: "llm").error("API \(status): \(message, privacy: .public)")
        switch status {
        case 401, 403: return BrainError(spoken: "La clave de la API no es válida.")
        case 400 where message.localizedCaseInsensitiveContains("credit"):
            return BrainError(spoken: "Se acabó el saldo de la API de Anthropic.")
        case 429: return BrainError(spoken: "Llegué al límite de la API. Espera un momento.")
        case 500...: return BrainError(spoken: "La API de Anthropic no responde ahora. Inténtalo en un rato.")
        default: return BrainError(spoken: "La API rechazó la pregunta.")
        }
    }

    /// Error con una frase que Capri pueda decir, o nil si se canceló.
    private static func describe(_ error: Error) -> Error? {
        if error is CancellationError { return nil }
        guard let error = error as? URLError else { return error }
        switch error.code {
        case .cancelled: return nil
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return BrainError(spoken: "No tengo internet para preguntarle a Claude.")
        case .timedOut: return BrainError(spoken: "Claude tardó demasiado en responder.")
        default: return error
        }
    }

    /// La clave se lee una vez: ANTHROPIC_API_KEY (pruebas en la terminal) o el Llavero.
    private func apiKey() -> String? {
        if key == nil { key = AnthropicKey.read() }
        return key
    }
}

/// Clave de la API de Anthropic en el Llavero de macOS (servicio com.rosvjames.capri, cuenta anthropic).
/// Nunca en el repositorio. Se guarda una vez desde la terminal con
/// `security add-generic-password -s com.rosvjames.capri -a anthropic -w` (pide la clave sin dejarla en el historial).
enum AnthropicKey {
    static let service = "com.rosvjames.capri"
    static let account = "anthropic"

    /// Si hay clave, sin leerla: leerla la primera vez hace que macOS pida permiso, y eso espera a la primera pregunta.
    static var exists: Bool {
        if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.isEmpty == false { return true }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnAttributes as String: true]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func read() -> String? {
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty { return key }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
