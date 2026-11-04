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
    @Published var mode: AssistantMode = .idle {
        didSet { activities.set(.conversation, mode != .idle) }
    }
    /// Qué ocupa el notch si coinciden varias cosas (música, conversación y, más adelante, avisos).
    private(set) var activities = ActivityBoard()
    @Published var expanded = false {
        didSet { if expanded && !oldValue { expandedAt = Date() } }
    }
    /// Cuándo se abrió el panel: el loop de Capri empieza desde aquí.
    @Published var expandedAt = Date()
    /// Lo que Capri entendió (en vivo mientras escucha; se mantiene hasta cerrar el panel).
    @Published var transcript = ""
    /// El panel se abrió solo porque Capri habla: entonces no se muestra lo que dictaste ("voz primero").
    @Published var openedForSpeech = false
    /// Lo que suena en Spotify, o nil si no suena ni está en pausa (C-29).
    @Published var nowPlaying: NowPlaying? {
        didSet { activities.set(.music, nowPlaying != nil) }
    }
    /// Carátula de `nowPlaying`, ya reducida; nil mientras llega o si no se pudo conseguir.
    @Published var artwork: NSImage?
    /// Controles de Spotify desde el panel; lo conecta AppDelegate.
    var musicCommand: (MusicCommand) -> Void = { _ in }
    /// Posición, duración y repetición de la canción, para la barra de progreso; nil si no se conocen.
    @Published var clock: PlaybackClock?
    @Published var repeating: Bool?
    /// La canción está en Tus me gusta; nil si no se sabe (sin sesión de Spotify o aún sin leer).
    @Published var liked: Bool?
    var toggleLike: () -> Void = {}
    /// Saltar a un punto de la canción, activar o quitar la repetición, y leer el reloj al abrir el panel.
    var seek: (TimeInterval) -> Void = { _ in }
    var toggleRepeat: () -> Void = {}
    var refreshPlayback: () -> Void = {}
    /// Sección elegida con los iconos del panel; nil hasta que se pulsa uno. Se olvida al cerrar el panel.
    @Published var selectedSection: PanelSection?
    /// Sección a la vista. Si Capri escucha, piensa o habla (o acaba de responder), el panel es suyo: la
    /// conversación tiene más prioridad (C-29). Si no, la elegida o, sin elegir, la música si hay canción.
    var section: PanelSection {
        if mode != .idle || openedForSpeech || showsStrip { return .assistant }
        if let selectedSection { return selectedSection }
        return activities.foreground == .music ? .music : .assistant
    }
    /// Medidas del cuerpo del panel abierto en la sección actual.
    var panelFrame: PanelFrame {
        switch section {
        case .assistant:
            PanelFrame(width: geometry.bodyWidth, height: geometry.height + stripHeight, offsetX: geometry.offsetX,
                       topRadius: geometry.topRadius, bottomRadius: geometry.bottomRadius)
        case .music:
            PanelFrame(width: MusicLayout.width, height: MusicLayout.height, offsetX: 0,
                       topRadius: geometry.topRadius, bottomRadius: geometry.bottomRadius)
        }
    }
    /// Lo que hay que leer o copiar de la última respuesta (comando, código, enlace), o nil si solo era para oírse.
    @Published var copyable: String?
    /// La franja inferior con `copyable` está a la vista: aparece al terminar de hablar y se va con el panel (C-03).
    @Published var showsStrip = false
    /// Se acaba de pulsar Copiar en la franja: el botón dice "Copiado" un momento.
    @Published var stripCopied = false
    /// Alto que la franja añade al panel abierto.
    var stripHeight: CGFloat {
        guard showsStrip, let copyable else { return 0 }
        return CopyStrip.height(for: copyable, geometry: geometry)
    }
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

    /// Tamaño de la ventana transparente: centrada en el notch y con sitio para la sección más grande
    /// (el asistente con su franja más alta, o la música).
    var windowSize: CGSize {
        let halfWidth = max(-geometry.minX, geometry.maxX, MusicLayout.width / 2) + geometry.topRadius
        let height = max(geometry.height + CopyStrip.maxHeight(geometry: geometry), MusicLayout.height)
        return CGSize(width: 2 * (halfWidth + Layout.panelPadX), height: height + Layout.panelPadY)
    }
}

/// Secciones del panel abierto, elegidas con los iconos de arriba a la izquierda. Pendientes y Agentes
/// llegarán con sus funciones (Fases 6 y 7).
enum PanelSection: CaseIterable {
    case assistant, music

    var symbol: String {
        switch self {
        case .assistant: "bubble.left"
        case .music: "music.note"
        }
    }

    var title: String {
        switch self {
        case .assistant: "Asistente"
        case .music: "Música"
        }
    }
}

/// Cuerpo del panel abierto: ancho y alto visibles, desplazamiento respecto a la cámara y radios.
struct PanelFrame: Equatable {
    let width: CGFloat
    let height: CGFloat
    let offsetX: CGFloat
    let topRadius: CGFloat
    let bottomRadius: CGFloat
}

/// Dónde va la canción: la posición leída en un momento y si avanza desde entonces. Así la barra de progreso
/// no necesita preguntarle a Spotify cada segundo.
struct PlaybackClock: Equatable {
    let position: TimeInterval
    let duration: TimeInterval
    let at: Date
    let playing: Bool

    func position(at date: Date) -> TimeInterval {
        min(duration, max(0, position + (playing ? date.timeIntervalSince(at) : 0)))
    }
}
