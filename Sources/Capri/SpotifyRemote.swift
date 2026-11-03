import AppKit
import os

/// Habla con Spotify por AppleScript: lo que el aviso no trae y, más adelante, la carátula y los controles (C-29).
///
/// Necesita el permiso de Automatización (`SpotifyAutomation`), que se pide la primera vez que hace falta.
/// Los scripts comprueban dentro que Spotify siga abierto: un `tell` a una app cerrada la abriría.
final class SpotifyRemote {
    private(set) var permission: PermissionState?
    /// Los scripts y el aviso del permiso bloquean: van en orden en su propia cola, nunca en el hilo principal.
    private let queue = DispatchQueue(label: "com.rosvjames.capri.spotify")
    private var asking = false
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "musica")

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: MusicWatcher.spotifyID).isEmpty
    }

    /// Lo que suena ahora, para cuando Spotify ya sonaba al abrir Capri. Con `ask` false no muestra el aviso
    /// del permiso: si aún no se concedió, devuelve nil. `done` llega en el hilo principal.
    func readNowPlaying(ask: Bool, _ done: @escaping (NowPlaying?) -> Void) {
        let separator = "\u{1F}"
        run("""
            if application id "\(MusicWatcher.spotifyID)" is running then
                tell application id "\(MusicWatcher.spotifyID)"
                    if player state is stopped then return ""
                    set s to character id 31
                    set t to current track
                    return (id of t) & s & (name of t) & s & (artist of t) & s & (album of t) & s & (player state as string)
                end tell
            end if
            return ""
            """, ask: ask) { text in
            let f = text?.components(separatedBy: separator) ?? []
            guard f.count == 5 else { return done(nil) }
            done(NowPlaying(trackID: f[0], title: f[1], artist: f[2], album: f[3], isPlaying: f[4] == "playing"))
        }
    }

    /// Muestra el aviso del permiso si aún no se respondió; no hace nada si ya se concedió o se denegó.
    func requestPermission() {
        guard permission != .granted, permission != .denied else { return }
        run(nil, ask: true) { _ in }
    }

    /// Comprueba el permiso (preguntando solo si `ask` y aún no se respondió) y ejecuta el script, si hay.
    private func run(_ source: String?, ask: Bool, _ done: @escaping (String?) -> Void) {
        guard Self.isRunning, !(ask && asking) else { return done(nil) }
        if ask { asking = true }
        let known = permission
        queue.async { [self] in
            var state = known == .granted ? .granted : SpotifyAutomation.state(ask: ask)
            var result: String?
            if state == .granted, let source {
                var error: NSDictionary?
                result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
                if let error {
                    log.error("AppleScript de Spotify: \(error, privacy: .public)")
                    // Se revocó en Ajustes del Sistema después de concederlo.
                    if error[NSAppleScript.errorNumber] as? Int == errAEEventNotPermitted { state = .denied }
                }
            }
            DispatchQueue.main.async { [self] in
                if ask { asking = false }
                if let state, state != permission {
                    permission = state
                    log.notice("permiso de Spotify: \(String(describing: state), privacy: .public)")
                }
                done(result)
            }
        }
    }
}
