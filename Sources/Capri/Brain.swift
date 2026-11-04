import Foundation

/// Un turno de la conversación, en el formato de los modelos de chat.
struct ChatMessage: Codable {
    let role: String
    let content: String
}

/// El modelo que piensa las respuestas, detrás de un protocolo para poder cambiar de proveedor (D-1).
/// Los resultados llegan en el hilo principal.
protocol Brain: AnyObject {
    /// Empieza a cargar el modelo mientras James habla, para que la respuesta solo espere la generación.
    func warmUp()
    /// `onPartial` recibe el texto acumulado según se escribe, para empezar a hablar antes de que termine;
    /// `completion`, el texto completo.
    func respond(to messages: [ChatMessage], onPartial: @escaping (String) -> Void,
                 completion: @escaping (Result<String, Error>) -> Void)
    func cancel()
}

enum Brains {
    /// Ollama por defecto; CAPRI_LLM=demo responde sin IA, como en la Fase 2.
    static func make() -> Brain {
        ProcessInfo.processInfo.environment["CAPRI_LLM"] == "demo" ? DemoBrain() : OllamaBrain()
    }
}

/// Error con un mensaje corto que Capri puede decir en voz.
struct BrainError: LocalizedError {
    let spoken: String
    var errorDescription: String? { spoken }
}

/// Eco de la Fase 2, para probar el flujo sin modelo.
final class DemoBrain: Brain {
    func warmUp() {}
    func cancel() {}

    func respond(to messages: [ChatMessage], onPartial: @escaping (String) -> Void,
                 completion: @escaping (Result<String, Error>) -> Void) {
        let question = messages.last { $0.role == "user" }?.content ?? ""
        let text = question.components(separatedBy: "</portapapeles>").last ?? question
        DispatchQueue.main.async { completion(.success(DemoReply.response(to: text))) }
    }
}
