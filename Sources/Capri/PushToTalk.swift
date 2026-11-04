import AppKit
import os

/// Atajo para hablar: mantener el ⌘ derecho (D-2).
///
/// - Mantenerlo ~0,25 s solo, sin otra tecla, empieza a escuchar; soltarlo termina.
/// - Un toque corto no hace nada.
/// - Si se pulsa otra tecla o modificador mientras se mantiene (⌘C con el ⌘ derecho), se cancela:
///   el usuario estaba usando un atajo, no hablando.
///
/// Usa monitores globales de teclado, que macOS solo entrega con el permiso de accesibilidad.
final class PushToTalk {
    var onStart: () -> Void = {}
    var onEnd: () -> Void = {}
    var onCancel: () -> Void = {}
    /// Esc pulsado en cualquier app (C-10). macOS lo entrega también a la app de delante: no se puede capturar.
    var onEscape: () -> Void = {}

    /// Tiempo que hay que mantener la tecla antes de empezar a escuchar.
    var holdDelay: TimeInterval = 0.25

    private enum Phase { case idle, armed, active }
    private var phase = Phase.idle
    private var armWork: DispatchWorkItem?
    private var monitors: [Any] = []
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "atajo")

    private static let rightCommandKeyCode: UInt16 = 54
    private static let escapeKeyCode: UInt16 = 53
    /// Bit del ⌘ derecho en los modificadores dependientes del dispositivo (NX_DEVICERCMDKEYMASK).
    private static let rightCommandMask: UInt = 0x10

    /// Instala (o reinstala) los monitores. Se llama otra vez al conceder accesibilidad.
    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0); return $0 }) {
            monitors.append(local)
        }
        log.notice("monitores del ⌘ derecho instalados")
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged: handleFlags(event)
        case .keyDown:
            if event.keyCode == Self.escapeKeyCode { onEscape() }
            interrupt("tecla \(event.keyCode)")
        default: break
        }
    }

    /// Modificadores que cuentan como "otra tecla pulsada". El Bloq Mayús no: es un estado, no una tecla
    /// mantenida, y con él activado el atajo dejaba de funcionar. La tecla fn y el teclado numérico tampoco.
    private static let heldModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.heldModifiers)
        let rightCommandDown = event.modifierFlags.rawValue & Self.rightCommandMask != 0

        if event.keyCode == Self.rightCommandKeyCode {
            if rightCommandDown && phase == .idle {
                // Solo cuenta si el ⌘ derecho es el único modificador pulsado.
                guard flags == .command else { return }
                arm()
            } else if !rightCommandDown {
                release()
            }
        } else if phase != .idle {
            interrupt("otro modificador")
        }
    }

    private func arm() {
        phase = .armed
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .armed else { return }
            self.phase = .active
            self.log.notice("inicio")
            self.onStart()
        }
        armWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: work)
    }

    private func release() {
        switch phase {
        case .active:
            log.notice("fin")
            reset()
            onEnd()
        case .armed:
            reset()  // toque corto: se ignora
        case .idle:
            break
        }
    }

    private func interrupt(_ reason: String) {
        switch phase {
        case .active:
            log.notice("cancelado: \(reason, privacy: .public)")
            reset()
            onCancel()
        case .armed:
            reset()
        case .idle:
            break
        }
    }

    private func reset() {
        armWork?.cancel()
        armWork = nil
        phase = .idle
    }
}
