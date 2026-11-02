import SwiftUI

/// Paleta provisional (carmesí / magenta / cian de glitch). Ajustar cuando haya referencias visuales.
enum Theme {
    static let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
    static let magenta = Color(red: 1.0, green: 0.18, blue: 0.53)
    static let cyan = Color(red: 0.0, green: 0.90, blue: 1.0)
    static let dim = Color.white.opacity(0.55)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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
