import AppKit
import QuartzCore
import SwiftUI

// Cara chibi y onda del notch cerrado mientras Capri escucha, piensa o habla, fuera de SwiftUI.
//
// Antes eran dos `TimelineView` a 24 fps y el nivel del micrófono era un valor publicado del modelo: cada cuadro
// y cada nivel (20 por segundo) redibujaban el panel entero, ~12–16 % de CPU. Ahora la cara es una capa cuya
// imagen solo se cambia cuando cambia el dibujo (poses ya renderizadas, guardadas), y la onda son capas que anima
// Core Animation o que se mueven solas con el nivel, sin pasar por SwiftUI.

/// Nivel del micrófono (0…1) para la onda. No es un valor publicado: llega directo a quien lo dibuja.
final class LevelFeed {
    var onChange: ((CGFloat) -> Void)?
    func send(_ level: CGFloat) { onChange?(level) }
}

// MARK: Cara

struct LiveCapriFace: View {
    let mode: AssistantMode
    @Environment(\.snapshotRendering) private var snapshot

    var body: some View {
        // Las capturas (`ImageRenderer`) no dibujan vistas de AppKit: ahí, la pose del instante.
        if snapshot {
            CapriFaceView(face: FacePoses.face(for: mode, at: Date().timeIntervalSinceReferenceDate))
        } else {
            LiveCapriFaceLayer(mode: mode)
        }
    }
}

private struct LiveCapriFaceLayer: NSViewRepresentable {
    let mode: AssistantMode
    func makeNSView(context: Context) -> LiveFaceView { LiveFaceView() }
    func updateNSView(_ view: LiveFaceView, context: Context) { view.mode = mode }
}

/// Cambia de pose a saltos, como el loop del panel: comprueba 10 veces por segundo qué pose toca y solo cambia la
/// imagen de la capa si es otra. Las poses se dibujan una vez y se guardan (son pocas: bocas, párpados, miradas).
final class LiveFaceView: NSView {
    var mode: AssistantMode = .idle {
        didSet { if mode != oldValue { tick() } }
    }
    private var timer: Timer?
    private var shown: FaceState?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.actions = ["contents": NSNull()]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    override func layout() {
        super.layout()
        shown = nil
        tick()
    }

    private func tick() {
        let face = FacePoses.face(for: mode, at: Date().timeIntervalSinceReferenceDate)
        guard face != shown, bounds.width > 0 else { return }
        shown = face
        let scale = window?.backingScaleFactor ?? 2
        layer?.contents = FacePoses.shared.image(for: face, side: bounds.width, scale: scale)
        layer?.contentsScale = scale
    }
}

/// Poses de la cara chibi según el estado, y sus imágenes ya dibujadas.
@MainActor
final class FacePoses {
    static let shared = FacePoses()
    private var images: [String: CGImage] = [:]

    func image(for face: FaceState, side: CGFloat, scale: CGFloat) -> CGImage? {
        let key = "\(face)|\(side)|\(scale)"
        if let image = images[key] { return image }
        let renderer = ImageRenderer(content: CapriFaceView(face: face).frame(width: side, height: side))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        // Pocas poses posibles; el límite solo protege de tamaños cambiantes.
        if images.count > 200 { images.removeAll() }
        images[key] = image
        return image
    }

    /// Pose a `t` segundos: parpadeo, miradas, pulso de los ojos al escuchar y boca al hablar. Todo en pasos
    /// discretos, para que haya pocas poses distintas.
    nonisolated static func face(for mode: AssistantMode, at t: TimeInterval) -> FaceState {
        var f: FaceState
        switch mode {
        case .idle:
            f = CapriExpression.calm.face
            f.look = glance(at: t)
        case .listening:
            f = CapriExpression.listening.face
            // Pulso de los ojos en tres tamaños.
            f.eyeScale = 1.08 + 0.03 * (abs(sin(t * 5)) * 2).rounded()
        case .thinking:
            f = CapriExpression.thinking.face
        case .speaking:
            // Boca a saltos, como en la serie: unas 10 poses por segundo.
            let mouths: [MouthShape] = [.zigzag, .talkHalf, .talkOpen, .talkHalf]
            f = FaceState(mouth: mouths[noise(Int(t * 10)) % mouths.count])
        }
        f.lid = blink(at: t)
        return f
    }

    /// Parpadeo breve cada ~3,5 s, saltándose algunos ciclos para que no sea mecánico.
    private nonisolated static func blink(at t: TimeInterval) -> CGFloat {
        let period = 3.5
        let cycle = Int(t / period)
        let phase = t - Double(cycle) * period
        return noise(cycle) % 4 != 0 && phase < 0.12 ? 0 : 1
    }

    /// Miradas ocasionales, sin transición: pose a pose, como en la serie.
    private nonisolated static func glance(at t: TimeInterval) -> CGSize {
        let looks = [CGSize.zero, .zero, CGSize(width: 0.7, height: 0), CGSize(width: -0.7, height: 0.1), CGSize(width: 0.3, height: -0.6)]
        return looks[noise(Int(t / 2.4) &* 31) % looks.count]
    }
}

// MARK: Onda

struct LiveWaveform: View {
    let mode: AssistantMode
    let feed: LevelFeed
    @Environment(\.snapshotRendering) private var snapshot

    var body: some View {
        if snapshot {
            WaveformView(mode: mode, bars: 4)
        } else {
            LiveWaveformLayer(mode: mode, feed: feed)
        }
    }
}

private struct LiveWaveformLayer: NSViewRepresentable {
    let mode: AssistantMode
    let feed: LevelFeed

    func makeNSView(context: Context) -> LiveWaveView {
        let view = LiveWaveView()
        feed.onChange = { [weak view] level in view?.show(level: level) }
        return view
    }

    func updateNSView(_ view: LiveWaveView, context: Context) { view.mode = mode }
}

/// Cuatro barras. Escuchando siguen el nivel real del micrófono (se mueven solas, sin animación en bucle);
/// pensando y hablando las anima Core Animation con secuencias propias, como las barras de música.
final class LiveWaveView: NSView {
    var mode: AssistantMode = .idle {
        didSet { if mode != oldValue { restyle() } }
    }
    private var bars: [CALayer] = []
    private static let count = 4
    private static let gap: CGFloat = 3

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<Self.count {
            let bar = CALayer()
            bar.cornerRadius = 1
            bar.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull()]
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let w = (bounds.width - Self.gap * CGFloat(Self.count - 1)) / CGFloat(Self.count)
        for (i, bar) in bars.enumerated() {
            // Altura completa y escala vertical: las animaciones y el nivel solo cambian la escala.
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (w + Self.gap) + w / 2, y: bounds.midY)
        }
        restyle()
    }

    private func restyle() {
        for (i, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            bar.backgroundColor = NSColor(mode == .thinking ? Theme.green : (i == 0 ? Theme.violet : Theme.red)).cgColor
            switch mode {
            case .listening, .idle:
                setScale(0.15, of: bar)
            case .thinking:
                bar.add(Self.sweep(i), forKey: "onda")
            case .speaking:
                bar.add(Self.talk(i), forKey: "onda")
            }
        }
    }

    /// Nivel del micrófono al escuchar: cada barra con su propio peso y un poco de variación.
    func show(level: CGFloat) {
        guard mode == .listening else { return }
        let weights: [CGFloat] = [0.7, 1, 0.85, 0.6]
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.05)
        for (i, bar) in bars.enumerated() {
            let jitter = 0.75 + 0.25 * CGFloat(noise(Int(Date().timeIntervalSinceReferenceDate * 20) &+ i * 7) % 100) / 100
            setScale(0.12 + 0.85 * level * weights[i] * jitter, of: bar, animated: true)
        }
        CATransaction.commit()
    }

    private func setScale(_ s: CGFloat, of bar: CALayer, animated: Bool = false) {
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }
        bar.transform = CATransform3DMakeScale(1, max(0.08, min(s, 1)), 1)
        if !animated { CATransaction.commit() }
    }

    /// Hablando: cada barra repite su secuencia, con duraciones distintas para que no se vea un patrón.
    private static func talk(_ i: Int) -> CAAnimation {
        let sequences: [[CGFloat]] = [
            [0.3, 0.9, 0.5, 1, 0.35, 0.75, 0.3],
            [0.8, 0.4, 1, 0.55, 0.9, 0.3, 0.8],
            [0.5, 1, 0.3, 0.85, 0.45, 0.95, 0.5],
            [0.9, 0.35, 0.7, 0.4, 1, 0.5, 0.9],
        ]
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        animation.values = sequences[i % sequences.count]
        animation.duration = 0.9 + 0.13 * Double(i)
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// Pensando: un pulso que recorre las barras de izquierda a derecha.
    private static func sweep(_ i: Int) -> CAAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        animation.values = [0.12, 0.95, 0.12, 0.12]
        animation.keyTimes = [0, 0.15, 0.35, 1]
        animation.duration = 0.85
        animation.beginTime = CACurrentMediaTime() + 0.12 * Double(i)
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }
}
