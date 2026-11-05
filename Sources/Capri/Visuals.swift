import AppKit
import SwiftUI

struct WaveformView: View {
    let mode: AssistantMode
    var bars = 30
    /// Nivel real del micrófono (0…1). Si existe, la onda lo sigue en lugar de simularlo.
    var level: CGFloat? = nil

    var body: some View {
        // 24 fps, como la cara: a la frecuencia de la pantalla (hasta 120 Hz) costaba ~10 % de CPU.
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let gap: CGFloat = 3
                let bw = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
                for i in 0..<bars {
                    let p = Double(i) / Double(bars)
                    let amp: Double
                    switch mode {
                    case .idle: amp = 0.07 + 0.05 * sin(t * 2 + p * 6)
                    case .listening:
                        let shape = 0.55 + 0.45 * abs(sin(t * 7 + p * 11))
                        amp = level.map { 0.12 + 0.85 * Double($0) * shape } ?? 0.2 + 0.75 * abs(sin(t * 7 + p * 11) * sin(t * 3.1 + p * 5))
                    case .thinking:
                        let d = abs((t * 1.2).truncatingRemainder(dividingBy: 1) - p)
                        amp = 0.08 + 0.9 * max(0, 1 - d * 6)
                    case .speaking: amp = 0.25 + 0.65 * abs(sin(t * 9 + p * 8) * sin(t * 4.3 + p * 3))
                    }
                    let h = max(2, size.height * amp)
                    let rect = CGRect(x: CGFloat(i) * (bw + gap), y: (size.height - h) / 2, width: bw, height: h)
                    let color = mode == .thinking ? Theme.green : (i % 5 == 0 ? Theme.violet : Theme.red)
                    g.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                }
            }
        }
    }
}

/// Barras de música del notch cerrado (C-29). No siguen el audio real, que pediría el permiso de grabar la pantalla.
///
/// Las anima Core Animation en el servidor de ventanas: la app no dibuja ningún cuadro. Con una animación de
/// SwiftUI, cada cuadro redibujaba el panel entero (~0,5 % de CPU por cada fps). Las capturas (`ImageRenderer`
/// no dibuja vistas de AppKit) y "Reducir movimiento" usan barras quietas.
struct MusicBars: View {
    var bars = 4
    @Environment(\.snapshotRendering) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if snapshot || reduceMotion {
            Canvas { g, size in
                for rect in MusicBarsView.layout(bars: bars, in: size) {
                    let h = rect.height * MusicBarsView.restingScale(rect.minX / size.width)
                    g.fill(Path(roundedRect: CGRect(x: rect.minX, y: size.height - h, width: rect.width, height: h), cornerRadius: 1),
                           with: .color(Theme.green))
                }
            }
        } else {
            MusicBarsLayer(bars: bars)
        }
    }
}

private struct MusicBarsLayer: NSViewRepresentable {
    let bars: Int
    func makeNSView(context: Context) -> MusicBarsView { MusicBarsView(bars: bars) }
    func updateNSView(_ view: MusicBarsView, context: Context) {}
}

final class MusicBarsView: NSView {
    private var barLayers: [CALayer] = []

    init(bars: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0..<bars {
            let bar = CALayer()
            bar.backgroundColor = NSColor(Theme.green).cgColor
            bar.cornerRadius = 1
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)  // crecen desde abajo (en AppKit y = 0 es abajo)
            layer?.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, (rect, bar)) in zip(Self.layout(bars: barLayers.count, in: bounds.size), barLayers).enumerated() {
            bar.bounds = CGRect(origin: .zero, size: rect.size)
            bar.position = CGPoint(x: rect.midX, y: 0)
            if bar.animation(forKey: "nivel") == nil { bar.add(Self.levels(for: i), forKey: "nivel") }
        }
        CATransaction.commit()
    }

    static func layout(bars: Int, in size: CGSize) -> [CGRect] {
        let gap: CGFloat = 2.5
        let w = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
        return (0..<bars).map { CGRect(x: CGFloat($0) * (w + gap), y: 0, width: w, height: size.height) }
    }

    /// Altura de las barras quietas (de 0 a 1 según su posición), como un instante de la animación.
    static func restingScale(_ position: CGFloat) -> CGFloat { [0.45, 0.8, 0.35, 1][min(Int(position * 4), 3)] }

    /// Cada barra repite una secuencia propia con una duración distinta: juntas no se repiten a simple vista.
    private static func levels(for i: Int) -> CAAnimation {
        let sequences: [[CGFloat]] = [
            [0.3, 0.8, 0.5, 1, 0.4, 0.7, 0.25, 0.9, 0.3],
            [0.9, 0.4, 1, 0.6, 0.3, 0.85, 0.5, 0.7, 0.9],
            [0.5, 1, 0.3, 0.7, 0.9, 0.35, 0.8, 0.45, 0.5],
            [0.7, 0.35, 0.6, 0.95, 0.5, 0.3, 1, 0.55, 0.7],
        ]
        let values = sequences[i % sequences.count]
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        animation.values = values
        animation.duration = 2.2 + 0.37 * Double(i)
        animation.repeatCount = .infinity
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: values.count - 1)
        animation.isRemovedOnCompletion = false
        return animation
    }
}

private struct SnapshotRenderingKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// La vista se dibuja para una captura (`--snapshot`): sin vistas de AppKit, que `ImageRenderer` no dibuja.
    var snapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}

/// Carátula pequeña con esquinas redondeadas; mientras llega, un hueco tenue del mismo tamaño.
struct ArtworkThumb: View {
    let image: NSImage?
    var radius: CGFloat = 5

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.white.opacity(0.08))
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// Líneas de escaneo CRT muy sutiles sobre el contenido.
struct Scanlines: View {
    var body: some View {
        Canvas { g, size in
            var y: CGFloat = 0
            while y < size.height {
                g.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.05)))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}
