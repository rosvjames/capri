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

    init() {
        screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        model = AssistantModel(metrics: NotchMetrics.of(screen))
        // Decodifica los fotogramas de Capri ahora, no al abrir el panel por primera vez.
        _ = NotchFrames.shared

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

    func setExpanded(_ value: Bool) {
        guard model.expanded != value else { return }
        collapseWork?.cancel()
        model.expanded = value
        panel.ignoresMouseEvents = !value
    }

    private func hoverRect(expanded: Bool) -> NSRect {
        let m = model.metrics, g = model.geometry
        let w = expanded ? g.bodyWidth + 24 : m.width + 2 * Layout.collapsedSide
        let h = expanded ? g.height + 10 : m.height + 2
        let centerX = screen.frame.midX + m.centerOffset + (expanded ? g.offsetX : 0)
        return NSRect(x: centerX - w / 2, y: screen.frame.maxY - h, width: w, height: h + 6)
    }

    private func handleMouseMoved() {
        let p = NSEvent.mouseLocation
        if model.expanded {
            if hoverRect(expanded: true).contains(p) {
                collapseWork?.cancel()
            } else if collapseWork == nil || collapseWork?.isCancelled == true {
                let work = DispatchWorkItem { [weak self] in
                    self?.collapseWork = nil
                    self?.setExpanded(false)
                }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            }
        } else if hoverRect(expanded: false).contains(p) {
            setExpanded(true)
        }
    }

    private func installHoverMonitors() {
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.handleMouseMoved() }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in self?.handleMouseMoved(); return e }
    }
}
