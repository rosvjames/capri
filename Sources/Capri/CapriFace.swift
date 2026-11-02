import AppKit
import SwiftUI

// Cara de Capri por capas: la base es una imagen
// (melena, cabeza, máscara lisa) y los ojos y la boca se dibujan encima con vectores.

/// Dónde van los ojos y la boca sobre la base, en píxeles de la imagen original
/// (art/final/A-004-base-chibi.json).
struct FaceAnchors: Decodable {
    struct Point: Decodable { let x: CGFloat; let y: CGFloat }
    struct Rings: Decodable { let outline, green, black, iris, pupil: CGFloat }
    struct Eyes: Decodable { let left: Point; let right: Point; let irisRadius: CGFloat; let rings: Rings }
    struct Mouth: Decodable { let x, y, width, zigzagHeight, stroke: CGFloat }

    let size: [CGFloat]
    let eyes: Eyes
    let mouth: Mouth

    static let chibi: FaceAnchors = {
        guard let url = Bundle.module.url(forResource: "capri-base-chibi", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let anchors = try? JSONDecoder().decode(FaceAnchors.self, from: data)
        else { fatalError("Faltan los anclajes de la base chibi en Resources") }
        return anchors
    }()
}

enum CapriAssets {
    static let chibiBase: NSImage? = Bundle.module
        .url(forResource: "capri-base-chibi", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))
}

enum EyeShape: Equatable { case open, closed, cross, happy }

enum MouthShape: Equatable { case zigzag, chevron, flat, talkHalf, talkOpen, grin, halfGrin, gasp }

struct FaceState: Equatable {
    var leftEye: EyeShape = .open
    var rightEye: EyeShape = .open
    var mouth: MouthShape = .zigzag
    /// Escala de los ojos (1 = normal).
    var eyeScale: CGFloat = 1
    /// Dirección de la mirada (-1...1 en cada eje).
    var look: CGSize = .zero
    /// Apertura de los párpados: 1 abiertos, 0 cerrados.
    var lid: CGFloat = 1
}

/// Las nueve expresiones aprobadas en A-002, en el mismo orden que la hoja.
enum CapriExpression: String, CaseIterable {
    case calm, listening, thinking, talkingHalf, talkingOpen, grin, wink, surprised, asleep

    var face: FaceState {
        switch self {
        case .calm: FaceState()
        case .listening: FaceState(mouth: .chevron, eyeScale: 1.12)
        case .thinking: FaceState(mouth: .flat, look: CGSize(width: 0.6, height: -0.6))
        case .talkingHalf: FaceState(mouth: .talkHalf)
        case .talkingOpen: FaceState(mouth: .talkOpen)
        case .grin: FaceState(leftEye: .happy, rightEye: .happy, mouth: .grin)
        case .wink: FaceState(leftEye: .cross, mouth: .halfGrin)
        case .surprised: FaceState(mouth: .gasp, eyeScale: 1.2)
        case .asleep: FaceState(leftEye: .closed, rightEye: .closed)
        }
    }
}

/// Cara estática: base + rasgos vectoriales para un `FaceState` dado.
struct CapriFaceView: View {
    let face: FaceState
    var anchors: FaceAnchors = .chibi
    var base: NSImage? = CapriAssets.chibiBase

    var body: some View {
        ZStack {
            if let base {
                Image(nsImage: base).resizable().interpolation(.high)
            }
            Canvas { g, size in
                FaceRenderer(a: anchors, k: size.width / anchors.size[0]).draw(face, in: &g)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Cara animada según el estado del asistente: parpadeo, miradas, pulso al escuchar y boca al hablar.
struct LiveCapriFace: View {
    let mode: AssistantMode

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { ctx in
            CapriFaceView(face: Self.face(for: mode, at: ctx.date.timeIntervalSinceReferenceDate))
        }
    }

    static func face(for mode: AssistantMode, at t: TimeInterval) -> FaceState {
        var f: FaceState
        switch mode {
        case .idle:
            f = CapriExpression.calm.face
            f.look = glance(at: t)
        case .listening:
            f = CapriExpression.listening.face
            // Pulso de los ojos; en la Fase 2 seguirá el nivel del micrófono.
            f.eyeScale = 1.08 + 0.06 * CGFloat(abs(sin(t * 5)))
        case .thinking:
            f = CapriExpression.thinking.face
        case .speaking:
            // Boca a saltos, como en la serie: unas 10 poses por segundo. En la Fase 2 seguirá su voz.
            let mouths: [MouthShape] = [.zigzag, .talkHalf, .talkOpen, .talkHalf]
            f = FaceState(mouth: mouths[noise(Int(t * 10)) % mouths.count])
        }
        f.lid = blink(at: t)
        return f
    }

    /// Parpadeo breve cada ~3,5 s, saltándose algunos ciclos para que no sea mecánico.
    private static func blink(at t: TimeInterval) -> CGFloat {
        let period = 3.5
        let cycle = Int(t / period)
        let phase = t - Double(cycle) * period
        return noise(cycle) % 4 != 0 && phase < 0.12 ? 0 : 1
    }

    /// Miradas ocasionales, sin transición: pose a pose, como en la serie.
    private static func glance(at t: TimeInterval) -> CGSize {
        let looks = [CGSize.zero, .zero, CGSize(width: 0.7, height: 0), CGSize(width: -0.7, height: 0.1), CGSize(width: 0.3, height: -0.6)]
        return looks[noise(Int(t / 2.4) &* 31) % looks.count]
    }
}

/// Dibuja ojos y boca en coordenadas de la vista (`k` = escala de la imagen original a la vista).
private struct FaceRenderer {
    let a: FaceAnchors
    let k: CGFloat

    func draw(_ f: FaceState, in g: inout GraphicsContext) {
        let r = a.eyes.irisRadius * k * f.eyeScale
        drawEye(f.leftEye, at: point(a.eyes.left), r: r, face: f, in: &g)
        drawEye(f.rightEye, at: point(a.eyes.right), r: r, face: f, in: &g)
        drawMouth(f.mouth, in: &g)
    }

    private func point(_ p: FaceAnchors.Point) -> CGPoint { CGPoint(x: p.x * k, y: p.y * k) }

    private func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    private func polyline(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(pts)
        return p
    }

    private func drawEye(_ shape: EyeShape, at c: CGPoint, r: CGFloat, face f: FaceState, in g: inout GraphicsContext) {
        let ring = a.eyes.rings
        let ink = GraphicsContext.Shading.color(Theme.ink)
        switch shape {
        case .open where f.lid > 0.2:
            let sy = f.lid
            g.fill(ellipse(c, r * ring.outline, r * ring.outline * sy), with: ink)
            g.fill(ellipse(c, r * ring.green, r * ring.green * sy), with: .color(Theme.green))
            g.fill(ellipse(c, r * ring.black, r * ring.black * sy), with: ink)
            // El iris se desplaza con la mirada sin salir del anillo negro.
            let travel = r * (ring.black - ring.iris)
            let ic = CGPoint(x: c.x + f.look.width * travel, y: c.y + f.look.height * travel * sy)
            g.fill(ellipse(ic, r * ring.iris, r * ring.iris * sy), with: .color(Theme.blue))
            let pc = CGPoint(x: c.x + f.look.width * travel * 1.8, y: c.y + f.look.height * travel * 1.8 * sy)
            g.fill(ellipse(pc, r * ring.pupil, r * ring.pupil * sy), with: .color(.white))
        case .open, .closed:
            var p = Path()
            p.move(to: CGPoint(x: c.x - r * 1.15, y: c.y))
            p.addQuadCurve(to: CGPoint(x: c.x + r * 1.15, y: c.y), control: CGPoint(x: c.x, y: c.y + r * 0.45))
            g.stroke(p, with: ink, style: StrokeStyle(lineWidth: r * 0.24, lineCap: .round))
        case .cross:
            var p = Path()
            let d = r * 0.85
            p.move(to: CGPoint(x: c.x - d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
            p.move(to: CGPoint(x: c.x + d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x - d, y: c.y + d))
            g.stroke(p, with: ink, style: StrokeStyle(lineWidth: r * 0.3))
        case .happy:
            var p = Path()
            p.move(to: CGPoint(x: c.x - r * 1.1, y: c.y + r * 0.35))
            p.addQuadCurve(to: CGPoint(x: c.x + r * 1.1, y: c.y + r * 0.35), control: CGPoint(x: c.x, y: c.y - r * 1.0))
            g.stroke(p, with: ink, style: StrokeStyle(lineWidth: r * 0.42, lineCap: .round))
            g.stroke(p.offsetBy(dx: 0, dy: r * 0.1), with: .color(Theme.blue), style: StrokeStyle(lineWidth: r * 0.14, lineCap: .round))
        }
    }

    private func drawMouth(_ shape: MouthShape, in g: inout GraphicsContext) {
        let m = a.mouth
        let c = CGPoint(x: m.x * k, y: m.y * k)
        // Las bocas abiertas de A-002 son mucho mayores que el zigzag en calma: ~1,9 veces su tamaño.
        let open: CGFloat = [.zigzag, .chevron, .flat].contains(shape) ? 1 : 1.9
        let w = m.width * k * open, h = m.zigzagHeight * k * open
        let white = GraphicsContext.Shading.color(.white)
        let line = StrokeStyle(lineWidth: m.stroke * k, lineCap: .round, lineJoin: .miter)
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * w, y: c.y + y * h) }

        switch shape {
        case .zigzag:
            g.stroke(polyline([at(-0.5, 0.5), at(-0.25, -0.5), at(0, 0.5), at(0.25, -0.5), at(0.5, 0.5)]), with: white, style: line)
        case .chevron:
            g.stroke(polyline([at(-0.16, 0.4), at(0, -0.4), at(0.16, 0.4)]), with: white, style: line)
        case .flat:
            g.stroke(polyline([at(-0.16, 0), at(0.16, 0)]), with: white, style: line)
        case .talkHalf:
            g.fill(teeth(from: at(-0.28, -0.6), to: at(0.28, -0.6), count: 3, depth: h * 1.1, down: true), with: white)
        case .talkOpen:
            g.fill(teeth(from: at(-0.36, -1.0), to: at(0.36, -1.0), count: 4, depth: h * 1.2, down: true), with: white)
            g.fill(teeth(from: at(-0.26, 1.9), to: at(0.26, 1.9), count: 3, depth: h * 1.0, down: false), with: white)
        case .grin:
            grin(center: at(0, 0), width: w * 1.15, height: h * 2.6, in: &g)
        case .halfGrin:
            grin(center: at(0.12, 0), width: w * 0.7, height: h * 1.8, in: &g)
        case .gasp:
            var p = Path()
            p.move(to: at(0, -0.6)); p.addLine(to: at(0.14, 0.6)); p.addLine(to: at(-0.14, 0.6)); p.closeSubpath()
            g.fill(p, with: white)
        }
    }

    /// Fila de dientes triangulares colgando (o subiendo) desde la línea p0–p1.
    private func teeth(from p0: CGPoint, to p1: CGPoint, count: Int, depth: CGFloat, down: Bool) -> Path {
        var p = Path()
        let dir: CGFloat = down ? 1 : -1
        let step = (p1.x - p0.x) / CGFloat(count)
        p.move(to: p0)
        for i in 0..<count {
            let x = p0.x + step * CGFloat(i)
            p.addLine(to: CGPoint(x: x + step / 2, y: p0.y + depth * dir))
            p.addLine(to: CGPoint(x: x + step, y: p0.y))
        }
        p.closeSubpath()
        return p
    }

    /// Sonrisa ancha: media luna blanca con una línea en zigzag que separa los dientes.
    private func grin(center c: CGPoint, width w: CGFloat, height h: CGFloat, in g: inout GraphicsContext) {
        let top = c.y - h * 0.3
        var p = Path()
        p.move(to: CGPoint(x: c.x - w / 2, y: top))
        p.addLine(to: CGPoint(x: c.x + w / 2, y: top))
        p.addQuadCurve(to: CGPoint(x: c.x - w / 2, y: top), control: CGPoint(x: c.x, y: top + h * 1.6))
        g.fill(p, with: .color(.white))

        var z = Path()
        let n = 6
        for i in 0...n {
            let pt = CGPoint(x: c.x - w * 0.38 + w * 0.76 * CGFloat(i) / CGFloat(n),
                             y: top + h * 0.42 + (i % 2 == 0 ? -h * 0.14 : h * 0.14))
            if i == 0 { z.move(to: pt) } else { z.addLine(to: pt) }
        }
        g.stroke(z, with: .color(Theme.ink), lineWidth: max(1, h * 0.09))
    }
}
