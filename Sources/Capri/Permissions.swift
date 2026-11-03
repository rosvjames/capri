import AppKit
import ApplicationServices
import AVFoundation
import os
import Speech

/// Permisos del sistema que Capri necesita para hablar contigo.
enum Permission: CaseIterable {
    case microphone, speech, accessibility

    var title: String {
        switch self {
        case .microphone: "micrófono"
        case .speech: "reconocimiento de voz"
        case .accessibility: "accesibilidad (atajo ⌘ derecho)"
        }
    }

    var settingsURL: URL {
        let pane = switch self {
        case .microphone: "Privacy_Microphone"
        case .speech: "Privacy_SpeechRecognition"
        case .accessibility: "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}

enum PermissionState { case granted, notDetermined, denied }

/// Permiso de Automatización sobre Spotify (carátula y controles, C-29). No es un `Permission`:
/// es opcional, así que no pone el punto en rojo ni bloquea el ⌘ derecho; sin él solo falta la carátula.
enum SpotifyAutomation {
    /// Con `ask` muestra el aviso del sistema si aún no se respondió y bloquea hasta la respuesta:
    /// llamar fuera del hilo principal. Devuelve nil si no se puede saber (Spotify cerrado).
    static func state(ask: Bool) -> PermissionState? {
        var target = AEDesc()
        let created = MusicWatcher.spotifyID.withCString {
            AECreateDesc(DescType(typeApplicationBundleID), $0, strlen($0), &target)
        }
        guard created == noErr else { return nil }
        defer { AEDisposeDesc(&target) }
        switch Int(AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)) {
        case Int(noErr): return .granted
        case errAEEventWouldRequireUserConsent: return .notDetermined
        case errAEEventNotPermitted: return .denied
        default: return nil
        }
    }
}

/// Estado de los permisos y su solicitud, en orden: micrófono → voz → accesibilidad.
final class PermissionCenter: ObservableObject {
    @Published private(set) var states: [Permission: PermissionState] = [:]

    private let log = Logger(subsystem: "com.rosvjames.capri", category: "permisos")
    private var accessibilityObserver: NSObjectProtocol?

    init() {
        refresh()
        // macOS avisa por esta notificación cuando cambia la lista de apps con accesibilidad.
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // El cambio tarda un instante en reflejarse en AXIsProcessTrusted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refresh() }
        }
    }

    deinit {
        if let accessibilityObserver { DistributedNotificationCenter.default().removeObserver(accessibilityObserver) }
    }

    var missing: [Permission] { Permission.allCases.filter { states[$0] != .granted } }
    var allGranted: Bool { missing.isEmpty }

    func refresh() {
        let new: [Permission: PermissionState] = [
            .microphone: Self.state(of: AVCaptureDevice.authorizationStatus(for: .audio)),
            .speech: Self.state(of: SFSpeechRecognizer.authorizationStatus()),
            .accessibility: AXIsProcessTrusted() ? .granted : .notDetermined,
        ]
        guard new != states else { return }
        states = new
        log.notice("permisos: \(Permission.allCases.map { "\($0)=\(new[$0]!)" }.joined(separator: " "), privacy: .public)")
    }

    /// Pide el primer permiso que falte y, al responder, sigue con el siguiente.
    /// Los que ya se denegaron solo se pueden cambiar en Ajustes del Sistema: se abre el panel correcto.
    func requestMissing() {
        refresh()
        guard let next = missing.first else { return }
        let state = states[next] ?? .notDetermined
        log.notice("solicitando \(String(describing: next), privacy: .public) (estado \(String(describing: state), privacy: .public))")

        switch (next, state) {
        case (.microphone, .notDetermined):
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { self.continueIfAnswered(next) }
            }
        case (.speech, .notDetermined):
            SFSpeechRecognizer.requestAuthorization { _ in
                DispatchQueue.main.async { self.continueIfAnswered(next) }
            }
        case (.accessibility, _):
            // Muestra el aviso del sistema y abre el ajuste: el usuario activa a Capri en la lista.
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            NSWorkspace.shared.open(next.settingsURL)
        default:
            NSWorkspace.shared.open(next.settingsURL)
        }
    }

    private func continueIfAnswered(_ permission: Permission) {
        refresh()
        // Solo se encadena si se concedió: tras un rechazo no se abre nada más por sorpresa.
        if states[permission] == .granted { requestMissing() }
    }

    /// Para capturas de verificación: simula permisos sin tocar los reales.
    func overrideForPreview(_ states: [Permission: PermissionState]) { self.states = states }

    private static func state(of status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private static func state(of status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
