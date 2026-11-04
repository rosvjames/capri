import AppKit
import os

enum MusicCommand {
    case previous, playPause, next, pause, play

    fileprivate var script: String {
        switch self {
        case .previous: "previous track"
        case .playPause: "playpause"
        case .next: "next track"
        case .pause: "pause"
        case .play: "play"
        }
    }
}

/// Habla con Spotify por AppleScript: lo que el aviso no trae (lo que ya sonaba, la carátula) y, más adelante,
/// los controles (C-29).
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

    /// URL de la carátula de la canción que suena, solo si sigue siendo `trackID`. Es la primera vez que hace
    /// falta el permiso, así que muestra su aviso si aún no se respondió. `done` llega en el hilo principal.
    func artworkURL(for trackID: String, _ done: @escaping (URL?) -> Void) {
        run("""
            if application id "\(MusicWatcher.spotifyID)" is running then
                tell application id "\(MusicWatcher.spotifyID)"
                    if player state is stopped then return ""
                    return (id of current track) & (character id 31) & (artwork url of current track)
                end tell
            end if
            return ""
            """, ask: true) { text in
            let f = text?.components(separatedBy: "\u{1F}") ?? []
            guard f.count == 2, f[0] == trackID, let url = URL(string: f[1]), url.scheme == "https" else { return done(nil) }
            done(url)
        }
    }

    /// Anterior, pausa/reproducir o siguiente. El cambio llega después por el aviso de Spotify.
    func send(_ command: MusicCommand) {
        run("""
            if application id "\(MusicWatcher.spotifyID)" is running then
                tell application id "\(MusicWatcher.spotifyID)" to \(command.script)
            end if
            return ""
            """, ask: true) { _ in }
    }

    /// Como `send`, pero devuelve el estado del reproductor después de la orden ("playing", "paused"), para
    /// comprobar que se cumplió; nil si Spotify está cerrado o no hay permiso. `done` llega en el hilo principal.
    /// Spotify cambia de estado unos milisegundos después de la orden: con pausa y reproducir se espera hasta 1 s.
    func control(_ command: MusicCommand, _ done: @escaping (String?) -> Void) {
        let expected = switch command {
        case .pause: "paused"
        case .play: "playing"
        default: ""
        }
        run("""
            if application id "\(MusicWatcher.spotifyID)" is running then
                tell application id "\(MusicWatcher.spotifyID)"
                    \(command.script)
                    if "\(expected)" is not "" then
                        repeat 10 times
                            if (player state as string) is "\(expected)" then exit repeat
                            delay 0.1
                        end repeat
                    end if
                    return player state as string
                end tell
            end if
            return ""
            """, ask: true) { done($0?.isEmpty == false ? $0 : nil) }
    }

    /// Comprueba el permiso (preguntando solo si `ask` y aún no se respondió) y ejecuta el script.
    private func run(_ source: String, ask: Bool, _ done: @escaping (String?) -> Void) {
        guard Self.isRunning, !(ask && asking) else { return done(nil) }
        if ask { asking = true }
        let known = permission
        queue.async { [self] in
            var state = known == .granted ? .granted : SpotifyAutomation.state(ask: ask)
            var result: String?
            if state == .granted {
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
