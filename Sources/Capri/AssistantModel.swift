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
    /// Desplazamiento del centro del notch respecto al centro de la pantalla (medio punto en algunos modelos).
    var centerOffset: CGFloat = 0

    static func of(_ screen: NSScreen) -> NotchMetrics {
        let h = screen.safeAreaInsets.top
        guard h > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return NotchMetrics(width: 200, height: 24) }
        let width = screen.frame.width - left.width - right.width
        return NotchMetrics(width: width, height: h, centerOffset: left.width + width / 2 - screen.frame.width / 2)
    }
}

enum Layout {
    /// Espacio a cada lado del notch físico cuando está colapsado y activo (cabeza de Capri / onda).
    static let collapsedSide: CGFloat = 48
    static let panelPadX: CGFloat = 60
    static let panelPadY: CGFloat = 40
}

final class AssistantModel: ObservableObject {
    @Published var mode: AssistantMode = .idle
    @Published var expanded = false {
        didSet { if expanded && !oldValue { expandedAt = Date() } }
    }
    /// Cuándo se abrió el panel: el loop de Capri empieza desde aquí.
    @Published var expandedAt = Date()
    /// Lo que Capri entendió (en vivo mientras escucha; se mantiene hasta cerrar el panel).
    @Published var transcript = ""
    /// El panel se abrió solo porque Capri habla: entonces no se muestra lo que dictaste ("voz primero").
    @Published var openedForSpeech = false
    /// Nivel del micrófono mientras escucha (0…1).
    @Published var audioLevel: CGFloat = 0
    /// Empezar o terminar de escuchar desde el botón Hablar; lo conecta AppDelegate.
    var toggleTalk: () -> Void = {}
    /// Volumen (dB) de la voz de Capri que se está oyendo; lo conecta AppDelegate.
    var speechLevel: () -> Float? = { nil }
    let metrics: NotchMetrics
    let geometry: ExpandedGeometry
    let permissions = PermissionCenter()

    init(metrics: NotchMetrics) {
        self.metrics = metrics
        geometry = ExpandedGeometry(metrics: metrics)
    }

    /// Tamaño de la ventana transparente: centrada en el notch y con sitio para el panel abierto.
    var windowSize: CGSize {
        let halfWidth = max(-geometry.minX, geometry.maxX) + geometry.topRadius
        return CGSize(width: 2 * (halfWidth + Layout.panelPadX), height: geometry.height + Layout.panelPadY)
    }
}
