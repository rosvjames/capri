import AppKit
import os

/// Lo que suena en Spotify (C-29).
struct NowPlaying: Equatable {
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
}

/// Sigue la canción de Spotify por el aviso distribuido que publica en cada cambio de canción o de estado (C-29).
///
/// No consulta en bucle (0 % de CPU en reposo) y no necesita permisos: el aviso le llega a cualquier app.
/// Lo que el aviso no trae va por AppleScript (`SpotifyRemote`), cuyo permiso se pide la primera vez que
/// suena algo. Con el permiso concedido, al abrir Capri se lee lo que ya sonaba.
final class MusicWatcher: NSObject {
    var onChange: (NowPlaying?) -> Void = { _ in }
    private(set) var current: NowPlaying?
    let spotify = SpotifyRemote()

    static let spotifyID = "com.spotify.client"
    private var quitObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "musica")

    override init() {
        super.init()
        // Capri nunca es la app activa: sin .deliverImmediately, macOS retendría los avisos hasta activarla.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackChanged(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil,
            suspensionBehavior: .deliverImmediately)
        // Al cerrar Spotify no siempre llega un último aviso.
        quitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == Self.spotifyID { self?.update(nil) }
        }
        // Sin preguntar: el aviso del permiso no debe salir al arrancar.
        spotify.readNowPlaying(ask: false) { [weak self] value in
            guard let self, self.current == nil, let value else { return }
            self.update(value)
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        quitObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    @objc private func playbackChanged(_ note: Notification) {
        let info = note.userInfo ?? [:]
        let state = info["Player State"] as? String
        guard state == "Playing" || state == "Paused", let id = info["Track ID"] as? String else { return update(nil) }
        update(NowPlaying(trackID: id, title: info["Name"] as? String ?? "", artist: info["Artist"] as? String ?? "",
                          album: info["Album"] as? String ?? "", isPlaying: state == "Playing"))
        spotify.requestPermission()
    }

    private func update(_ value: NowPlaying?) {
        guard value != current else { return }
        current = value
        let state = value.map { $0.isPlaying ? "suena" : "en pausa" } ?? "nada"
        log.notice("música: \(state, privacy: .public) \(value?.trackID ?? "", privacy: .public)")
        onChange(value)
    }
}
