import SwiftUI

/// Texto con separación cromática (verde / rojo) y saltos aleatorios en ráfagas.
struct GlitchText: View {
    let text: String
    var font: Font = Theme.mono(15, weight: .bold)
    /// 0...1: frecuencia de las ráfagas de glitch.
    var intensity: Double = 0.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { ctx in
            let step = Int(ctx.date.timeIntervalSinceReferenceDate * 24)
            let burst = noise(step / 2) % 100 < Int(intensity * 22)
            let dx = burst ? CGFloat(noise(step &* 7) % 9) - 4 : 0
            let dy = burst ? CGFloat(noise(step &* 13) % 3) - 1 : 0
            ZStack {
                Text(text).foregroundStyle(Theme.green.opacity(burst ? 0.9 : 0)).offset(x: -dx - 1.5, y: dy)
                Text(text).foregroundStyle(Theme.red.opacity(burst ? 0.9 : 0)).offset(x: dx + 1.5, y: -dy)
                Text(text).foregroundStyle(.white)
            }
            .font(font)
        }
    }
}
