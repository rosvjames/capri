import SwiftUI

struct WaveformView: View {
    let mode: AssistantMode
    var bars = 30

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
                    case .listening: amp = 0.2 + 0.75 * abs(sin(t * 7 + p * 11) * sin(t * 3.1 + p * 5))
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
