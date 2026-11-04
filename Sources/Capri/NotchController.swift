import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class NotchController {
    let model: AssistantModel
    private let panel: NotchPanel
    private let screen: NSScreen
    private var collapseWork: DispatchWorkItem?
    private var fullscreen: FullscreenWatcher?
    /// Mientras Capri habla el panel no se cierra al apartar el ratón.
    private var holdOpen = false
    /// La franja de copiar está abierta y el ratón aún no ha pasado por el panel: moverlo por fuera
    /// (por ejemplo, hacia la terminal) no la cierra; se cierra sola o al salir del panel después de usarla.
    private var stripUntilHover = false
    static let stripDuration: TimeInterval = 15
    private let fixedState = ProcessInfo.processInfo.environment["CAPRI_ESTADO"] != nil

    init() {
        screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        model = AssistantModel(metrics: NotchMetrics.of(screen))
        // Decodifica los fotogramas de Capri ahora, no al abrir el panel por primera vez.
        _ = NotchFrames.shared
        _ = TalkingFace.shared

        let size = model.windowSize
        let frame = NSRect(x: screen.frame.midX + model.metrics.centerOffset - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(rootView: NotchView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        // En pantalla completa (vídeo, juego, presentación) Capri desaparece; sigue escuchando el ⌘ derecho.
        // Con CAPRI_ESTADO se queda visible: oculta no dibuja nada y la medición de CPU saldría en 0 %.
        if !fixedState {
            let watcher = FullscreenWatcher(screen: screen)
            watcher.onChange = { [weak self] isFullscreen in self?.setHidden(isFullscreen) }
            fullscreen = watcher
            if watcher.isFullscreen { setHidden(true) }
        }

        // CAPRI_ESTADO fija un estado e ignora el ratón, para medir rendimiento sin interferencias.
        if let fixed = ProcessInfo.processInfo.environment["CAPRI_ESTADO"] {
            switch fixed {
            case "abierto": setExpanded(true)
            case "activo": model.mode = .speaking
            default: break
            }
        } else {
            installHoverMonitors()
        }
    }

    /// Capri empieza a responder: el notch se despliega para verla hablar (salvo en pantalla completa).
    func showWhileSpeaking() {
        guard panel.isVisible else { return }
        holdOpen = true
        collapseWork?.cancel()
        if !model.expanded { model.openedForSpeech = true }
        setExpanded(true)
    }

    /// Capri terminó de hablar: el panel se cierra en un momento, salvo que el ratón esté encima.
    /// Si la respuesta trae algo que copiar, aparece la franja y el panel espera más antes de cerrarse.
    func speechEnded() {
        holdOpen = false
        guard model.expanded, !fixedState else { return }
        if model.copyable != nil {
            model.showsStrip = true
            stripUntilHover = true
            scheduleCollapse(after: Self.stripDuration)
        } else {
            scheduleCollapse(after: 1.5)
        }
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            if !self.holdOpen, !self.hoverRect(expanded: true).contains(NSEvent.mouseLocation) { self.setExpanded(false) }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func setHidden(_ hidden: Bool) {
        if hidden {
            setExpanded(false)
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func setExpanded(_ value: Bool) {
        guard model.expanded != value else { return }
        collapseWork?.cancel()
        model.expanded = value
        panel.ignoresMouseEvents = !value
        // Pudo cambiar los permisos en Ajustes del Sistema mientras el panel estaba cerrado.
        if value { model.permissions.refresh() } else {
            model.openedForSpeech = false
            if model.mode == .idle { model.transcript = "" }
            model.showsStrip = false
            model.copyable = nil
            stripUntilHover = false
        }
    }

    private func hoverRect(expanded: Bool) -> NSRect {
        let m = model.metrics, g = model.geometry
        let w = expanded ? g.bodyWidth + 24 : m.width + 2 * Layout.collapsedSide
        let h = expanded ? g.height + model.stripHeight + 10 : m.height + 2
        let centerX = screen.frame.midX + m.centerOffset + (expanded ? g.offsetX : 0)
        return NSRect(x: centerX - w / 2, y: screen.frame.maxY - h, width: w, height: h + 6)
    }

    private func handleMouseMoved() {
        let p = NSEvent.mouseLocation
        if model.expanded {
            if hoverRect(expanded: true).contains(p) {
                collapseWork?.cancel()
                stripUntilHover = false
            } else if !holdOpen, !stripUntilHover, collapseWork == nil || collapseWork?.isCancelled == true {
                scheduleCollapse(after: 0.25)
            }
        } else if panel.isVisible, hoverRect(expanded: false).contains(p) {
            setExpanded(true)
        }
    }

    private func installHoverMonitors() {
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.handleMouseMoved() }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in self?.handleMouseMoved(); return e }
    }
}
