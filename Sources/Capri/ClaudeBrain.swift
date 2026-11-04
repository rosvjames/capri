import Foundation
import os
import Security

/// Por dónde se llega a Claude.
enum ClaudeAccess {
    /// La API de Anthropic, con una clave propia.
    case anthropic
    /// El AI Gateway de Astropods, que pasa la misma API de mensajes y cobra de los créditos de esa cuenta.
    /// Solo ofrece modelos anteriores (Haiku 4.5, Sonnet 5…) y su clave de desarrollo caduca a las 24 h:
    /// sirve para probar, no para el día a día.
    case astropods(url: String)

    /// Cuenta del Llavero (servicio com.rosvjames.capri) donde vive su clave.
    var keyAccount: String {
        switch self {
        case .anthropic: "anthropic"
        case .astropods: "astropods"
        }
    }

    /// Variable de entorno con la clave, para pruebas en la terminal.
    var keyVariable: String {
        switch self {
        case .anthropic: "ANTHROPIC_API_KEY"
        case .astropods: "ASTRO_GATEWAY_API_KEY"
        }
    }

    var baseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com"
        case .astropods(let url): url.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + "/anthropic"
        }
    }

    /// El gateway envía las peticiones a Bedrock: se le habla con la versión de la API que usa el SDK.
    var apiVersion: String {
        switch self {
        case .anthropic: "2026-10-21"
        case .astropods: "2023-06-01"
        }
    }

    /// La API de Anthropic lee la clave de x-api-key; el gateway ignora esa cabecera y lee x-bf-vk.
    func authorize(_ request: inout URLRequest, key: String) {
        switch self {
        case .anthropic: request.setValue(key, forHTTPHeaderField: "x-api-key")
        case .astropods: request.setValue(key, forHTTPHeaderField: "x-bf-vk")
        }
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
    }

    var hasKey: Bool { APIKeys.exists(account: keyAccount, variable: keyVariable) }

    /// La clave de Anthropic si la hay; si no, Astropods (ASTRO_GATEWAY_URL o el ajuste `astropods-url`
    /// cambian su dirección); nil si no hay ninguna.
    static var available: ClaudeAccess? {
        if ClaudeAccess.anthropic.hasKey { return .anthropic }
        let url = ProcessInfo.processInfo.environment["ASTRO_GATEWAY_URL"]
            ?? UserDefaults.standard.string(forKey: "astropods-url")
            ?? "https://aig.astropods.ai"
        let gateway = ClaudeAccess.astropods(url: url)
        return gateway.hasKey ? gateway : nil
    }
}

/// Claude por la API de mensajes (`/v1/messages` en streaming), sin SDK: no hay uno oficial para Swift.
/// No ocupa memoria del Mac, a diferencia de Gemma, pero la pregunta (y lo copiado, si la frase lo pide)
/// sale del Mac y cada respuesta cuesta. Con Haiku 5.5, ~US$0,0002 por pregunta; con Sonnet, ~US$0,003;
/// con Haiku 4.5 (Astropods), ~US$0,0015.
final class ClaudeBrain: Brain {
    let model: String
    let access: ClaudeAccess
    private var task: Task<Void, Never>?
    private var key: String?
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "llm")

    init(model: String, access: ClaudeAccess) {
        self.model = model
        self.access = access
    }

    /// Abre la conexión (TLS) mientras James habla, para que la pregunta no espere el saludo con el servidor.
    /// Listar modelos no cuesta nada (si el gateway no tiene esa ruta, la conexión queda abierta igual).
    func warmUp(with messages: [ChatMessage]) {
        guard let key = apiKey(), let url = URL(string: access.baseURL + "/v1/models?limit=1") else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        access.authorize(&request, key: key)
        URLSession.shared.dataTask(with: request).resume()
    }

    func respond(to messages: [ChatMessage], tools: [[String: Any]], onPartial: @escaping (String) -> Void,
                 completion: @escaping (Result<BrainOutput, Error>) -> Void) {
        cancel()
        guard let key = apiKey() else {
            completion(.failure(BrainError(spoken: "Me falta la clave de Claude en el Llavero.")))
            return
        }
        guard let request = request(messages, tools: tools, key: key) else {
            completion(.failure(BrainError(spoken: "No pude preparar la pregunta.")))
            return
        }
        let start = Date()
        task = Task { [log, model, access] in
            var text = ""
            // Herramienta elegida: nombre y JSON de sus datos, que llega por trozos (input_json_delta).
            var toolName: String?
            var toolIndex: Int?
            var toolJSON = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                    var body = Data()
                    for try await byte in bytes { body.append(byte) }
                    throw Self.httpError(status: status, body: body, access: access)
                }
                // Eventos SSE: solo importan las líneas "data:"; el texto llega en content_block_delta.
                // Una herramienta abre su bloque con content_block_start (tipo tool_use, con su nombre) y manda
                // sus datos como input_json_delta. Solo se usa la primera.
                for try await line in bytes.lines {
                    guard line.hasPrefix("data:"),
                          let json = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any]
                    else { continue }
                    switch json["type"] as? String {
                    case "message_start":
                        // Para medir el costo (personalidad, herramientas, historial y pregunta). La API de
                        // Anthropic lo manda aquí; el gateway, en message_delta.
                        Self.logUsage((json["message"] as? [String: Any])?["usage"], model: model)
                    case "content_block_start":
                        guard toolName == nil, let block = json["content_block"] as? [String: Any],
                              block["type"] as? String == "tool_use", let name = block["name"] as? String else { continue }
                        toolName = name
                        toolIndex = json["index"] as? Int
                        log.notice("\(model, privacy: .public): herramienta \(name, privacy: .public) en \(Date().timeIntervalSince(start), format: .fixed(precision: 2)) s")
                    case "content_block_delta":
                        guard let delta = json["delta"] as? [String: Any] else { continue }
                        if delta["type"] as? String == "input_json_delta" {
                            if toolName != nil, json["index"] as? Int == toolIndex, toolJSON.count < 4_000 {
                                toolJSON += delta["partial_json"] as? String ?? ""
                            }
                            continue
                        }
                        // Lo que escriba después de elegir una herramienta no se dice: la confirmación es de Capri.
                        guard toolName == nil, delta["type"] as? String == "text_delta",
                              let piece = delta["text"] as? String, !piece.isEmpty else { continue }
                        if text.isEmpty {
                            log.notice("\(model, privacy: .public): primer texto en \(Date().timeIntervalSince(start), format: .fixed(precision: 2)) s")
                        }
                        text += piece
                        let partial = text
                        await MainActor.run { if !Task.isCancelled { onPartial(partial) } }
                    case "message_delta":
                        Self.logUsage(json["usage"], model: model)
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
                // Sin datos, la API manda el JSON vacío como "" en vez de "{}".
                let call = toolName.map { ToolCall(name: $0, arguments: Data((toolJSON.isEmpty ? "{}" : toolJSON).utf8)) }
                let result = BrainOutput(text: text, toolCall: call)
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

    private func request(_ messages: [ChatMessage], tools: [[String: Any]], key: String) -> URLRequest? {
        let system = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
        var body: [String: Any] = [
            "model": model,
            // Respuestas de una o dos frases y, como mucho, un bloque para copiar.
            "max_tokens": 1024,
            "stream": true,
            "system": system,
            "messages": messages.filter { $0.role != "system" }.map { ["role": $0.role, "content": $0.content] },
        ]
        if !tools.isEmpty { body["tools"] = tools }
        guard let url = URL(string: access.baseURL + "/v1/messages") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        access.authorize(&request, key: key)
        // Sin razonamiento previo: para preguntas rápidas solo añade espera. Cada modelo lo apaga distinto.
        let base = model.replacingOccurrences(of: "bedrock/", with: "")
        if base.hasSuffix("-4-5") {
            // Haiku 4.5 no razona si no se le pide y no acepta `effort`.
        } else if base.hasPrefix("claude-opus-5-5") {
            // Opus 5.5 no deja apagarlo: con esfuerzo bajo razona poco o nada.
            body["output_config"] = ["effort": "low"]
        } else if base.hasPrefix("claude-sonnet-5-5") {
            // Sonnet 5.5 no acepta "disabled" y lo apaga con "between_tools".
            body["output_config"] = ["effort": "low"]
            body["thinking"] = ["type": "between_tools"]
            if case .anthropic = access {
                // Si los filtros de seguridad rechazan la respuesta, la API la repite con otro modelo en la misma llamada.
                body["fallbacks"] = "default"
                request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            }
        } else {
            body["output_config"] = ["effort": "low"]
            body["thinking"] = ["type": "disabled"]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func logUsage(_ usage: Any?, model: String) {
        guard let usage = usage as? [String: Any], let input = usage["input_tokens"] as? Int, input > 0 else { return }
        let output = usage["output_tokens"] as? Int ?? 0
        Logger(subsystem: "com.rosvjames.capri", category: "llm").notice("\(model, privacy: .public): \(input) tokens de entrada, \(output) de salida")
    }

    /// Error HTTP de la API → frase corta para decir en voz; el detalle queda en el registro.
    private static func httpError(status: Int, body: Data, access: ClaudeAccess) -> Error {
        let message = ((try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? [String: Any])?["message"] as? String ?? ""
        Logger(subsystem: "com.rosvjames.capri", category: "llm").error("API \(status): \(message, privacy: .public)")
        switch status {
        case 401, 403:
            if case .astropods = access {
                return BrainError(spoken: "La clave de Astropods venció. Renuévala con ast project start.")
            }
            return BrainError(spoken: "La clave de la API no es válida.")
        case 400 where message.localizedCaseInsensitiveContains("credit"):
            return BrainError(spoken: "Se acabó el saldo de la API de Anthropic.")
        case 429:
            if case .astropods = access {
                return BrainError(spoken: "Llegué al límite de Astropods, o se acabaron los créditos.")
            }
            return BrainError(spoken: "Llegué al límite de la API. Espera un momento.")
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

    /// La clave se lee una vez: de la variable de entorno (pruebas en la terminal) o del Llavero.
    private func apiKey() -> String? {
        if key == nil { key = APIKeys.read(account: access.keyAccount, variable: access.keyVariable) }
        return key
    }
}

/// Claves de Claude en el Llavero de macOS (servicio com.rosvjames.capri; cuentas anthropic y astropods).
/// Nunca en el repositorio. Se guardan desde la terminal con
/// `security add-generic-password -U -s com.rosvjames.capri -a <cuenta> -w`, que pide la clave sin dejarla en el historial.
enum APIKeys {
    static let service = "com.rosvjames.capri"

    /// Si hay clave, sin leerla: leerla la primera vez hace que macOS pida permiso, y eso espera a la primera pregunta.
    static func exists(account: String, variable: String) -> Bool {
        if ProcessInfo.processInfo.environment[variable]?.isEmpty == false { return true }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnAttributes as String: true]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String, variable: String) -> String? {
        if let key = ProcessInfo.processInfo.environment[variable], !key.isEmpty { return key }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
