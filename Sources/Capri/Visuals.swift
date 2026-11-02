import SwiftUI

/// Núcleo animado del "construct". Placeholder hasta tener el arte definitivo de Capri.
struct CoreAvatar: View {
    let mode: AssistantMode

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2 - 4
                let speed: Double = mode == .idle ? 0.5 : (mode == .thinking ? 3.0 : 1.6)

                var ring = Path()
                ring.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                g.stroke(ring, with: .color(Theme.crimson.opacity(0.4)),
                         style: StrokeStyle(lineWidth: 1.5, dash: [3, 5], dashPhase: CGFloat(t * 18 * speed)))

                for i in 0..<3 {
                    var arc = Path()
                    let start = Angle.degrees(t * 70 * speed + Double(i) * 120)
                    arc.addArc(center: c, radius: r - 9, startAngle: start, endAngle: start + .degrees(55), clockwise: false)
                    g.stroke(arc, with: .color(i == 0 ? Theme.magenta : (mode == .thinking ? Theme.cyan : Theme.crimson)),
                             style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }

                let pulse = 0.5 + 0.5 * sin(t * (mode == .speaking ? 9 : 2.2))
                let cr = (r - 22) * (0.55 + 0.3 * pulse)
                g.fill(Path(ellipseIn: CGRect(x: c.x - cr, y: c.y - cr, width: cr * 2, height: cr * 2)),
                       with: .radialGradient(Gradient(colors: [Theme.magenta, Theme.crimson.opacity(0)]),
                                             center: c, startRadius: 0, endRadius: cr))

                // Barrido tipo glitch: franja horizontal desplazada de vez en cuando.
                let step = Int(t * 24)
                if noise(step / 3) % 100 < 14 {
                    let y = CGFloat(noise(step &* 5) % Int(size.height))
                    g.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 2)), with: .color(Theme.cyan.opacity(0.6)))
                }
            }
        }
    }
}

struct WaveformView: View {
    let mode: AssistantMode
    var bars = 30

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let gap: CGFloat = 3
                let bw = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
                for i in 0..<bars {
                    let p = Double(i) / Double(bars)
                    let amp: Double
                    switch mode {
                    case .idle: amp = 0.07 + 0.05 * sin(t * 2 + p * 6)
                    case .listening: amp = 0.2 + 0.75 * abs(sin(t * 7 + p * 11) * sin(t * 3.1 + p * 5))
                    case .thinking:
                        let d = abs((t * 1.2).truncatingRemainder(dividingBy: 1) - p)
                        amp = 0.08 + 0.9 * max(0, 1 - d * 6)
                    case .speaking: amp = 0.25 + 0.65 * abs(sin(t * 9 + p * 8) * sin(t * 4.3 + p * 3))
                    }
                    let h = max(2, size.height * amp)
                    let rect = CGRect(x: CGFloat(i) * (bw + gap), y: (size.height - h) / 2, width: bw, height: h)
                    let color = mode == .thinking ? Theme.cyan : (i % 5 == 0 ? Theme.magenta : Theme.crimson)
                    g.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                }
            }
        }
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
