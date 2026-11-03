import AppKit
import ImageIO
import SwiftUI

/// Capri hablando en el panel: 12 fotogramas (3 bocas × 4 estados de ojos) sobre la pose de reposo del v3.
///
/// - La boca sigue el volumen de lo que se está oyendo (`Speaker.level()`), medido cada 20 ms: silencio →
///   cerrada, voz suave → media, voz fuerte → abierta. Umbrales distintos para abrir y para cerrar y un mínimo
///   de 90 ms por dibujo, para que cambie a saltos como en la serie y no vibre.
/// - El parpadeo va aparte (cada 4–8 s, 240 ms: 40/40/80/40/40), así puede parpadear mientras habla.
final class TalkingFace {
    enum Mouth: Int { case closed, half, open }

    static let shared = TalkingFace()

    /// `images[boca][ojos]`; ojos: 0 abiertos, 1 inicio de parpadeo, 2 medio, 3 cerrados.
    private let images: [[CGImage]]
    private var mouth = Mouth.closed
    private var lastChange = Date.distantPast
    private var smoothed: Float = -80
    private var blinkStart: Date?
    private var nextBlink = Date().addingTimeInterval(.random(in: 4...8))

    // Umbrales en dB, calibrados con la voz de Paulina (mediana de la voz ≈ -17 dB).
    private static let openAbove: Float = -16.5, openBelow: Float = -19
    private static let halfAbove: Float = -30, closeBelow: Float = -33
    private static let minHold: TimeInterval = 0.09

    private init() {
        let mouths = ["0-cerrada", "1-media", "2-abierta"]
        let eyes = ["0-ojos-abiertos", "1-parpadeo-inicio", "2-medio-parpadeo", "3-ojos-cerrados"]
        images = mouths.map { m in eyes.map { e in Self.decode("notch-v3-habla-\(m)-\(e)") } }
    }

    /// Fotograma para `date`, con el volumen que suena ahora (nil = nada).
    func frame(at date: Date, level: Float?) -> CGImage {
        updateMouth(at: date, level: level)
        return images[mouth.rawValue][eyes(at: date)]
    }

    /// Al empezar una frase: boca cerrada y ojos abiertos.
    func reset() {
        mouth = .closed
        smoothed = -80
        lastChange = .distantPast
    }

    private func updateMouth(at date: Date, level: Float?) {
        smoothed += ((level ?? -80) - smoothed) * 0.6
        var wanted = mouth
        switch mouth {
        case .closed: wanted = smoothed >= Self.openAbove ? .open : smoothed >= Self.halfAbove ? .half : .closed
        case .half: wanted = smoothed >= Self.openAbove ? .open : smoothed < Self.closeBelow ? .closed : .half
        case .open: wanted = smoothed < Self.closeBelow ? .closed : smoothed < Self.openBelow ? .half : .open
        }
        if level == nil { wanted = .closed }
        if wanted != mouth, date.timeIntervalSince(lastChange) >= Self.minHold {
            mouth = wanted
            lastChange = date
        }
    }

    private func eyes(at date: Date) -> Int {
        if blinkStart == nil, date >= nextBlink { blinkStart = date }
        guard let start = blinkStart else { return 0 }
        let ms = date.timeIntervalSince(start) * 1000
        switch ms {
        case ..<40: return 1
        case ..<80: return 2
        case ..<160: return 3
        case ..<200: return 2
        case ..<240: return 1
        default:
            blinkStart = nil
            nextBlink = date.addingTimeInterval(.random(in: 4...8))
            return 0
        }
    }

    private static func decode(_ name: String) -> CGImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { fatalError("Falta el fotograma \(name).png") }
        return image
    }
}

/// Reproduce a Capri hablando: se actualiza cada 20 ms mientras habla, como las ventanas de volumen.
struct TalkingFacePlayer: View {
    let level: () -> Float?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.02)) { ctx in
            Image(decorative: TalkingFace.shared.frame(at: ctx.date, level: level()), scale: 1)
                .resizable()
                .interpolation(.high)
        }
    }
}
