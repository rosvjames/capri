import Foundation

/// Respuestas puntuales para probar el intercambio antes de conectar la IA.
enum DemoReply {
    static let greeting = "Hola, James. ¿Cómo estás? ¿Qué te gustaría hacer hoy?"

    static func response(to transcript: String) -> String {
        let words = transcript.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                       locale: Locale(identifier: "es_MX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if words == ["hola", "capri"] {
            return greeting
        }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No te escuché." : transcript
    }
}
