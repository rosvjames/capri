import AppKit
import SwiftUI

enum AssistantMode: CaseIterable {
    case idle, listening, thinking, speaking

    var label: String {
        switch self {
        case .idle: "STANDBY"
        case .listening: "ESCUCHANDO"
        case .thinking: "PROCESANDO"
        case .speaking: "RESPONDIENDO"
        }
    }

    var sampleLine: String {
        switch self {
        case .idle: "> construct en espera_"
        case .listening: "> ¿puedes abrir Safari?"
        case .thinking: "> resolviendo intención..."
        case .speaking: "Abriendo Safari."
        }
    }

    var next: AssistantMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

struct NotchMetrics {
    let width: CGFloat
    let height: CGFloat

    static func of(_ screen: NSScreen) -> NotchMetrics {
        let h = screen.safeAreaInsets.top
        guard h > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return NotchMetrics(width: 200, height: 24) }
        return NotchMetrics(width: screen.frame.width - left.width - right.width, height: h)
    }
}

enum Layout {
    static let expandedW: CGFloat = 500
    static let expandedH: CGFloat = 156
    static let panelPadX: CGFloat = 60
    static let panelPadY: CGFloat = 40
}

final class AssistantModel: ObservableObject {
    @Published var mode: AssistantMode = .idle
    @Published var expanded = false
    let metrics: NotchMetrics

    init(metrics: NotchMetrics) { self.metrics = metrics }
}
