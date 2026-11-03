import AVFoundation
import os

/// Voz de Capri: Paulina (es-MX) en la mejor calidad instalada (Premium > mejorada > estándar), D-5 y D-8.
/// La voz se elige en cada frase, así que al descargar Paulina Premium se usa sin reiniciar.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    var onStart: () -> Void = {}
    var onFinish: () -> Void = {}

    private let synthesizer = AVSpeechSynthesizer()
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "voz")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        let voice = Self.bestVoice()
        utterance.voice = voice
        log.notice("hablando con \(voice?.name ?? "voz por defecto", privacy: .public) (\(Self.qualityName(voice), privacy: .public))")
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let mexican = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "es-MX" }
        let byQuality = { (a: AVSpeechSynthesisVoice, b: AVSpeechSynthesisVoice) in a.quality.rawValue > b.quality.rawValue }
        return mexican.filter { $0.name.hasPrefix("Paulina") }.sorted(by: byQuality).first
            ?? mexican.sorted(by: byQuality).first
            ?? AVSpeechSynthesisVoice(language: "es-MX")
    }

    private static func qualityName(_ voice: AVSpeechSynthesisVoice?) -> String {
        switch voice?.quality {
        case .premium: "premium"
        case .enhanced: "mejorada"
        default: "estándar"
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onStart() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish() }
    }
}
