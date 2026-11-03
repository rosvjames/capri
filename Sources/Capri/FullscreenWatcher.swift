import AppKit
import os

/// Detecta si la app de delante está en pantalla completa en la pantalla del notch (C-10),
/// para que Capri no se dibuje encima de un vídeo o un juego.
///
/// Solo comprueba cuando cambia el escritorio o la app activa: no consulta en bucle (0 % de CPU en reposo).
/// No necesita permisos ni lee nada de las ventanas: solo el tipo de escritorio activo.
final class FullscreenWatcher {
    var onChange: (Bool) -> Void = { _ in }
    private(set) var isFullscreen = false

    private let screen: NSScreen
    private var observers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "pantalla")

    init(screen: NSScreen) {
        self.screen = screen
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // La animación de cambio de escritorio tarda: se comprueba al terminar.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.check() }
            })
        }
        check()
    }

    deinit { observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver) }

    func check() {
        let now = Self.frontAppIsFullscreen(on: screen)
        guard now != isFullscreen else { return }
        isFullscreen = now
        log.notice("pantalla completa: \(now, privacy: .public)")
        onChange(now)
    }

    /// Pregunta al sistema si el escritorio (Space) visible en esa pantalla es de pantalla completa.
    ///
    /// Usa una función interna de macOS (CGSCopyManagedDisplaySpaces: tipo 0 = escritorio normal,
    /// 4 = pantalla completa), no documentada pero estable y muy usada. Las señales públicas no sirven
    /// en un Mac con notch: la barra de menús sigue "visible" en pantalla completa, y una ventana
    /// a pantalla completa mide lo mismo que una maximizada con el Dock oculto.
    static func frontAppIsFullscreen(on screen: NSScreen) -> Bool {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] else { return false }
        let uuid = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
            .flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
            .map { CFUUIDCreateString(nil, $0) as String }
        // Con "las pantallas tienen Spaces separados" desactivado hay una sola entrada ("Main").
        let display = displays.first { ($0["Display Identifier"] as? String) == uuid } ?? (displays.count == 1 ? displays.first : nil)
        let current = display?["Current Space"] as? [String: Any]
        return (current?["type"] as? Int) == 4
    }
}

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray
