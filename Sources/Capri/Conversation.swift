import Foundation

/// Lo que responde Capri: lo que dice en voz y, si hace falta, lo que hay que copiar (la franja del panel).
struct Reply: Equatable {
    let spoken: String
    let copyable: String?

    /// El modelo escribe la frase y, al final, lo que hay que copiar entre <copiar> y </copiar>.
    init(parsing raw: String) {
        var spoken = raw, copyable: String?
        if let open = raw.range(of: "<copiar>") {
            let rest = raw[open.upperBound...]
            let close = rest.range(of: "</copiar>")
            copyable = String(rest[..<(close?.lowerBound ?? rest.endIndex)])
            spoken = String(raw[..<open.lowerBound]) + (close.map { String(rest[$0.upperBound...]) } ?? "")
        }
        copyable = copyable?.trimmingCharacters(in: .whitespacesAndNewlines)
        if copyable?.isEmpty == true { copyable = nil }
        // Por si se cuela formato de chat: la voz leería los asteriscos y las comillas invertidas.
        spoken = spoken.replacingOccurrences(of: "[*_`#]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if spoken.isEmpty { spoken = copyable == nil ? "No sé qué decirte." : "Aquí lo tienes." }
        self.spoken = spoken
        self.copyable = copyable
    }
}

/// La conversación con Capri: su personalidad y una memoria corta para seguir el hilo
/// ("¿y para verlos todos?"), que se olvida tras unos minutos sin hablar. No es memoria a largo plazo (C-21).
final class Conversation {
    private let brain: Brain
    private let personality: String
    private var history: [ChatMessage] = []
    private var lastTurn = Date.distantPast
    /// Identifica la pregunta en curso: la respuesta de una pregunta cancelada se ignora.
    private var requestID = 0
    static let forgetAfter: TimeInterval = 10 * 60
    /// Mensajes que se recuerdan (pregunta y respuesta cuentan por separado).
    static let maxHistory = 6

    init(brain: Brain = Brains.make()) {
        self.brain = brain
        personality = Bundle.module.url(forResource: "capri-personalidad", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    func warmUp() { brain.warmUp() }

    func ask(_ question: String, completion: @escaping (Result<Reply, Error>) -> Void) {
        cancel()
        let id = requestID
        if Date().timeIntervalSince(lastTurn) > Self.forgetAfter { history = [] }
        let turn = ChatMessage(role: "user", content: question)
        let messages = [ChatMessage(role: "system", content: personality)] + history + [turn]
        brain.respond(to: messages) { [weak self] result in
            guard let self, id == self.requestID else { return }
            if case .success(let raw) = result {
                self.history = Array((self.history + [turn, ChatMessage(role: "assistant", content: raw)]).suffix(Self.maxHistory))
                self.lastTurn = Date()
            }
            completion(result.map(Reply.init(parsing:)))
        }
    }

    func cancel() {
        requestID += 1
        brain.cancel()
    }
}
