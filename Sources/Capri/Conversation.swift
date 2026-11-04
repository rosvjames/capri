import AppKit
import os

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
        spoken = Self.clean(spoken)
        if spoken.isEmpty { spoken = copyable == nil ? "No sé qué decirte." : "Aquí lo tienes." }
        self.spoken = spoken
        self.copyable = copyable
    }

    /// Por si se cuela formato de chat: la voz leería los asteriscos y las comillas invertidas.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "[*_`#]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Corta en frases el texto hablado según llega, para que la voz empiece con la primera
/// mientras el modelo escribe el resto. Desde el primer "<" (el bloque <copiar>) ya no se dice nada.
struct SentenceSplitter {
    /// Caracteres del texto hablado ya entregados.
    private var emitted = 0

    private static func spokenPart(_ raw: String) -> Substring {
        raw[..<(raw.firstIndex(of: "<") ?? raw.endIndex)]
    }

    /// Las frases completas nuevas del texto acumulado, juntas, o nil si aún no termina ninguna.
    /// Una frase termina en . ? ! … o salto de línea seguido de espacio (así "3.5" no corta).
    mutating func sentences(in raw: String) -> String? {
        let pending = Self.spokenPart(raw).dropFirst(emitted)
        var end: Substring.Index?
        var i = pending.startIndex
        while i < pending.endIndex {
            let next = pending.index(after: i)
            if ".?!…\n".contains(pending[i]), next < pending.endIndex, pending[next].isWhitespace { end = next }
            i = next
        }
        guard let end else { return nil }
        let chunk = pending[..<end]
        emitted += chunk.count
        return Reply.clean(String(chunk))
    }

    /// Lo que queda por decir del texto completo.
    mutating func rest(of raw: String) -> String {
        let pending = Self.spokenPart(raw).dropFirst(emitted)
        emitted += pending.count
        return Reply.clean(String(pending))
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
    private static let log = Logger(subsystem: "com.rosvjames.capri", category: "llm")

    init(brain: Brain = Brains.make()) {
        self.brain = brain
        personality = Bundle.module.url(forResource: "capri-personalidad", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    func warmUp() {
        forgetIfStale()
        brain.warmUp(with: [ChatMessage(role: "system", content: personality)] + history)
    }

    private func forgetIfStale() {
        if Date().timeIntervalSince(lastTurn) > Self.forgetAfter { history = [] }
    }

    /// `onSentence` recibe lo que hay que decir, por frases y en orden, en cuanto el modelo las escribe;
    /// `completion`, la respuesta completa (con lo que hay que copiar) o el error.
    func ask(_ question: String, onSentence: @escaping (String) -> Void,
             completion: @escaping (Result<Reply, Error>) -> Void) {
        cancel()
        let id = requestID
        forgetIfStale()
        let turn = ChatMessage(role: "user", content: ClipboardContext.attach(to: question))
        let messages = [ChatMessage(role: "system", content: personality)] + history + [turn]
        var splitter = SentenceSplitter()
        var spoke = false
        let say = { (text: String) in
            guard !text.isEmpty else { return }
            spoke = true
            Self.log.notice("frase lista: \(text.count) caracteres")
            onSentence(text)
        }
        brain.respond(to: messages, onPartial: { [weak self] partial in
            guard let self, id == self.requestID, let sentences = splitter.sentences(in: partial) else { return }
            say(sentences)
        }, completion: { [weak self] result in
            guard let self, id == self.requestID else { return }
            if case .success(let raw) = result {
                self.history = Array((self.history + [turn, ChatMessage(role: "assistant", content: raw)]).suffix(Self.maxHistory))
                self.lastTurn = Date()
                // Si no se dijo nada por el camino (respuesta de una sola frase o solo un bloque), la respuesta
                // entera, que ya trae su frase de respaldo.
                let rest = splitter.rest(of: raw)
                say(spoke ? rest : Reply(parsing: raw).spoken)
            }
            completion(result.map(Reply.init(parsing:)))
        })
    }

    func cancel() {
        requestID += 1
        brain.cancel()
    }
}

/// El portapapeles como contexto (C-05): solo se envía si la frase lo pide ("este error", "lo que copié"),
/// para que nunca salga algo copiado por accidente. Lo que los gestores de contraseñas marcan como oculto no se usa.
enum ClipboardContext {
    static let maxCharacters = 4_000
    /// Frases que señalan lo copiado, sin acentos ni mayúsculas.
    static let triggers = [
        "este error", "ese error", "el error", "este mensaje", "ese mensaje",
        "este codigo", "ese codigo", "este comando", "ese comando",
        "lo que copie", "lo que tengo copiado", "copiado", "portapapeles",
        "esto que", "que significa esto", "que dice esto",
    ]

    static func wanted(by question: String) -> Bool {
        let folded = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
        return triggers.contains { folded.contains($0) }
    }

    /// La pregunta con el texto copiado delante, si la frase lo pide y hay texto que se pueda usar.
    static func attach(to question: String, pasteboard: NSPasteboard = .general) -> String {
        guard wanted(by: question),
              !(pasteboard.types ?? []).contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")),
              let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return question }
        // Del final de un error largo suele salir lo importante: se conserva el final.
        let clipped = text.count > maxCharacters ? "…" + text.suffix(maxCharacters) : text
        return "<portapapeles>\n\(clipped)\n</portapapeles>\n\(question)"
    }
}
