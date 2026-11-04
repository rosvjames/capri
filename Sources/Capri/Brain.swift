import Foundation

/// Un turno de la conversación, en el formato de los modelos de chat.
struct ChatMessage: Codable {
    let role: String
    let content: String
}

/// El modelo que piensa las respuestas, detrás de un protocolo para poder cambiar de proveedor (D-1).
/// Los resultados llegan en el hilo principal.
protocol Brain: AnyObject {
    /// Mientras James habla: carga el modelo y lee ya el principio de la conversación (personalidad e
    /// historial), para que al llegar la pregunta solo quede leer esta y escribir la respuesta.
    func warmUp(with messages: [ChatMessage])
    /// `onPartial` recibe el texto acumulado según se escribe, para empezar a hablar antes de que termine;
    /// `completion`, el texto completo.
    func respond(to messages: [ChatMessage], onPartial: @escaping (String) -> Void,
                 completion: @escaping (Result<String, Error>) -> Void)
    func cancel()
}

enum Brains {
    /// El modelo sale de CAPRI_MODELO o de `defaults write com.rosvjames.capri modelo …` (la app abierta con
    /// `open` no recibe variables de entorno): los que empiezan por "claude-" van por la API de Anthropic y el
    /// resto, por Ollama. Sin ajuste, Claude Haiku si hay clave en el Llavero y, si no, Gemma en el Mac.
    /// CAPRI_LLM=demo responde sin IA, como en la Fase 2.
    static func make() -> Brain {
        let environment = ProcessInfo.processInfo.environment
        if environment["CAPRI_LLM"] == "demo" { return DemoBrain() }
        let model = environment["CAPRI_MODELO"]
            ?? UserDefaults.standard.string(forKey: "modelo")
            ?? (AnthropicKey.exists ? "claude-haiku-5-5" : "gemma4:12b")
        return model.hasPrefix("claude-") ? ClaudeBrain(model: model) : OllamaBrain(model: model)
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

    func respond(to messages: [ChatMessage], onPartial: @escaping (String) -> Void,
                 completion: @escaping (Result<String, Error>) -> Void) {
        let question = messages.last { $0.role == "user" }?.content ?? ""
        let text = question.components(separatedBy: "</portapapeles>").last ?? question
        DispatchQueue.main.async { completion(.success(DemoReply.response(to: text))) }
    }
}
