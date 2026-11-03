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
/// hace falta la carátula. Con el permiso concedido, al abrir Capri se lee lo que ya sonaba.
final class MusicWatcher: NSObject {
    var onChange: (NowPlaying?) -> Void = { _ in }
    /// Carátula de la canción actual; nil al cambiar de canción hasta que llega la nueva.
    var onArtwork: (NSImage?) -> Void = { _ in }
    private(set) var current: NowPlaying?
    let spotify = SpotifyRemote()

    static let spotifyID = "com.spotify.client"
    private let artwork = ArtworkCache()
    /// Canción cuya carátula se muestra y la que se está buscando (para no pedirla dos veces).
    private var artworkShown: String?
    private var artworkLoading: String?
    private var quitObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "musica")

    /// Empieza a escuchar; llamar después de conectar `onChange` y `onArtwork`.
    func start() {
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
    }

    private func update(_ value: NowPlaying?) {
        guard value != current else { return }
        current = value
        let state = value.map { $0.isPlaying ? "suena" : "en pausa" } ?? "nada"
        log.notice("música: \(state, privacy: .public) \(value?.trackID ?? "", privacy: .public)")
        onChange(value)
        refreshArtwork()
    }

    /// Busca la carátula si cambió la canción: primero en la caché y, si no está, se la pide a Spotify.
    /// Si no se consigue (permiso aún sin responder, sin red), se reintenta en el siguiente aviso.
    private func refreshArtwork() {
        let id = current?.trackID
        if artworkShown != nil, artworkShown != id {
            artworkShown = nil
            onArtwork(nil)
        }
        guard let id, id != artworkShown, id != artworkLoading else { return }
        artworkLoading = id
        artwork.cached(id) { [weak self] image in
            guard let self else { return }
            if let image { return self.show(image, for: id, from: "caché") }
            self.spotify.artworkURL(for: id) { url in
                guard let url, self.current?.trackID == id else { return self.show(nil, for: id, from: "") }
                self.artwork.download(url, for: id) { self.show($0, for: id, from: "descarga") }
            }
        }
    }

    private func show(_ image: NSImage?, for id: String, from source: String) {
        if artworkLoading == id { artworkLoading = nil }
        guard let image, current?.trackID == id else { return }
        artworkShown = id
        log.notice("carátula (\(source, privacy: .public)): \(id, privacy: .public)")
        onArtwork(image)
    }
}
