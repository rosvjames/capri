import Foundation

/// Un turno de la conversación, en el formato de los modelos de chat.
struct ChatMessage {
    let role: String
    let content: String
    /// En un turno de Capri, la herramienta que usó; `content` es entonces la confirmación. Claude lo recibe
    /// como una llamada a la herramienta con su resultado: si lo viera como texto ("Sigue."), podría imitar la
    /// confirmación sin usar la herramienta. Los modelos sin herramientas solo ven el texto.
    var action: ToolCall? = nil
}

/// Herramienta que eligió el modelo, con sus datos en JSON tal como llegaron. Se valida antes de usarla (`Tools`).
struct ToolCall: Sendable {
    /// El identificador que le da la API, o uno local si la orden llegó por la vía rápida.
    let id: String
    let name: String
    let arguments: Data

    static func local(name: String, input: [String: Any]) -> ToolCall? {
        guard let data = try? JSONSerialization.data(withJSONObject: input) else { return nil }
        let id = "toolu_local_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20).lowercased()
        return ToolCall(id: id, name: name, arguments: data)
    }
}

/// Lo que escribió el modelo: texto y, si eligió una herramienta, cuál.
struct BrainOutput: Sendable {
    let text: String
    var toolCall: ToolCall?
}

/// El modelo que piensa las respuestas, detrás de un protocolo para poder cambiar de proveedor (D-1).
/// Los resultados llegan en el hilo principal.
protocol Brain: AnyObject {
    /// Mientras James habla: carga el modelo y lee ya el principio de la conversación (personalidad e
    /// historial), para que al llegar la pregunta solo quede leer esta y escribir la respuesta.
    func warmUp(with messages: [ChatMessage])
    /// `tools` son las herramientas que puede elegir (formato de la API de Anthropic); un modelo que no las
    /// admite las ignora. `onPartial` recibe el texto acumulado según se escribe, para empezar a hablar antes
    /// de que termine; `completion`, el texto completo y la herramienta elegida.
    func respond(to messages: [ChatMessage], tools: [[String: Any]], onPartial: @escaping (String) -> Void,
                 completion: @escaping (Result<BrainOutput, Error>) -> Void)
    func cancel()
}

enum Brains {
    /// El modelo sale de CAPRI_MODELO o de `defaults write com.rosvjames.capri modelo …` (la app abierta con
    /// `open` no recibe variables de entorno): los que empiezan por "claude-" van a Claude (con la clave de
    /// Anthropic o, si no hay, por Astropods) y el resto, por Ollama. Sin ajuste: Haiku 5.5 con clave de
    /// Anthropic, Haiku 4.5 con la de Astropods y, sin ninguna, Gemma en el Mac.
    /// CAPRI_LLM=demo responde sin IA, como en la Fase 2.
    static func make() -> Brain {
        let environment = ProcessInfo.processInfo.environment
        if environment["CAPRI_LLM"] == "demo" { return DemoBrain() }
        let access = ClaudeAccess.available
        let fallback: String
        switch access {
        case .anthropic: fallback = "claude-haiku-5-5"
        case .astropods: fallback = "claude-haiku-4-5"
        case nil: fallback = "gemma4:12b"
        }
        let model = environment["CAPRI_MODELO"] ?? UserDefaults.standard.string(forKey: "modelo") ?? fallback
        guard model.hasPrefix("claude-") || model.hasPrefix("bedrock/") else { return OllamaBrain(model: model) }
        return ClaudeBrain(model: model, access: access ?? .anthropic)
    }
}

/// Error con un mensaje corto que Capri puede decir en voz.
struct BrainError: LocalizedError {
    let spoken: String
    var errorDescription: String? { spoken }
}

/// Eco de la Fase 2, para probar el flujo sin modelo.
final class DemoBrain: Brain {
    func warmUp(with messages: [ChatMessage]) {}
    func cancel() {}

    func respond(to messages: [ChatMessage], tools: [[String: Any]], onPartial: @escaping (String) -> Void,
                 completion: @escaping (Result<BrainOutput, Error>) -> Void) {
        let question = messages.last { $0.role == "user" }?.content ?? ""
        let text = question.components(separatedBy: "</portapapeles>").last ?? question
        DispatchQueue.main.async { completion(.success(BrainOutput(text: DemoReply.response(to: text)))) }
    }
}
