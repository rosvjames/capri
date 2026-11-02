import SwiftUI

/// Paleta de Capri, medida sobre capturas de la serie.
enum Theme {
    static let ink = Color(hex: 0x0B0B12)
    static let red = Color(hex: 0xFF1A47)
    static let green = Color(hex: 0x2BF56C)
    static let blue = Color(hex: 0x1F5FD6)
    static let violet = Color(hex: 0x7A3CF0)
    static let dim = Color.white.opacity(0.55)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Ruido determinista barato para efectos de glitch.
func noise(_ n: Int) -> Int {
    var x = UInt64(truncatingIfNeeded: n) &* 6364136223846793005 &+ 1442695040888963407
    x ^= x >> 33
    x = x &* 0xff51afd7ed558ccd
    x ^= x >> 29
    return Int(x % 10_000)
}
