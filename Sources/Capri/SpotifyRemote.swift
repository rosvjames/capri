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

    /// Reproduce una canción, un artista o un álbum (`spotify:track:…`) y devuelve el estado del reproductor,
    /// o nil si no se pudo. Si Spotify está cerrado lo abre, sin traerlo al frente, y espera a que responda.
    /// `done` llega en el hilo principal.
    func play(_ uri: String, _ done: @escaping (String?) -> Void) {
        // Solo URIs de Spotify bien formados: van dentro del script.
        guard uri.range(of: "^spotify:(track|artist|album|playlist):[A-Za-z0-9]+$", options: .regularExpression) != nil else {
            return done(nil)
        }
        let script = """
            if application id "\(MusicWatcher.spotifyID)" is running then
                tell application id "\(MusicWatcher.spotifyID)"
                    play track "\(uri)"
                    repeat 15 times
                        if (player state as string) is "playing" then exit repeat
                        delay 0.1
                    end repeat
                    return player state as string
                end tell
            end if
            return ""
            """
        // Recién abierto, Spotify tarda unos segundos en aceptar órdenes: se reintenta.
        func attempt(_ left: Int) {
            run(script, ask: true) { state in
                if state == "playing" || left == 0 { return done(state?.isEmpty == false ? state : nil) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { attempt(left - 1) }
            }
        }
        if Self.isRunning { return attempt(1) }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicWatcher.spotifyID) else { return done(nil) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { running, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { running == nil ? done(nil) : attempt(5) }
        }
    }

    /// Posición, duración y repetición de lo que suena. Sin preguntar por el permiso. `done` llega en el hilo
    /// principal, con nil si Spotify está cerrado, parado o sin permiso.
    func readPlayback(_ done: @escaping (PlaybackClock?, Bool?) -> Void) {
        run("""
            if application id "\(MusicWatcher.spotifyID)" is running then
                tell application id "\(MusicWatcher.spotifyID)"
                    if player state is stopped then return ""
                    set s to character id 31
                    return (player position as string) & s & ((duration of current track) as string) & s & (repeating as string) & s & (player state as string)
                end tell
            end if
            return ""
            """, ask: false) { text in
            let f = text?.components(separatedBy: "\u{1F}") ?? []
            // AppleScript escribe los decimales con la coma del idioma del Mac.
            let number = { (t: String) in Double(t.replacingOccurrences(of: ",", with: ".")) }
            guard f.count == 4, let position = number(f[0]), let duration = number(f[1]), duration > 0 else { return done(nil, nil) }
            done(PlaybackClock(position: position, duration: duration / 1000, at: Date(), playing: f[3] == "playing"), f[2] == "true")
        }
    }

    /// Salta a `seconds` de la canción que suena.
    func seek(to seconds: TimeInterval) {
        let value = String(format: "%.2f", max(0, seconds))
        run("""
            if application id "\(MusicWatcher.spotifyID)" is running then
                tell application id "\(MusicWatcher.spotifyID)" to set player position to \(value)
            end if
            return ""
            """, ask: true) { _ in }
    }

    /// Activa o quita la repetición y devuelve cómo quedó (nil si no se pudo).
    func toggleRepeat(_ done: @escaping (Bool?) -> Void) {
        run("""
            if application id "\(MusicWatcher.spotifyID)" is running then
                tell application id "\(MusicWatcher.spotifyID)"
                    set repeating to not repeating
                    return repeating as string
                end tell
            end if
            return ""
            """, ask: true) { text in done(text == "true" ? true : text == "false" ? false : nil) }
    }

    /// Comprueba el permiso (preguntando solo si `ask` y aún no se respondió) y ejecuta el script.
    /// Solo se evita mostrar dos avisos del permiso a la vez. Con el permiso concedido, los scripts esperan su
    /// turno en la cola: la carátula se pide mientras sigue el de "pon tal canción", que espera a que suene.
    private func run(_ source: String, ask: Bool, _ done: @escaping (String?) -> Void) {
        let prompting = ask && permission != .granted
        guard Self.isRunning, !(prompting && asking) else { return done(nil) }
        if prompting { asking = true }
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
                if prompting { asking = false }
                if let state, state != permission {
                    permission = state
                    log.notice("permiso de Spotify: \(String(describing: state), privacy: .public)")
                }
                done(result)
            }
        }
    }
}
