import AppKit
import os
import SwiftUI

// Burbuja de Spotify: se abre con el botón de debajo del panel de música y muestra tus listas, Tus me gusta,
// lo último que sonó, la cola y una búsqueda, sin cambiar de app ni de escritorio. Lo que eliges suena en la app
// de Spotify (AppleScript); los datos salen de la API web con tu sesión (`SpotifyAccount`).
//
// Prototipo funcional: el aspecto es provisional, a la espera del diseño.

/// Algo que se puede reproducir o abrir: canción, álbum, lista o artista.
struct SpotifyItem: Identifiable, Hashable {
    enum Kind { case track, album, playlist, artist }
    let id: String
    let uri: String
    let kind: Kind
    let title: String
    let subtitle: String
    let image: URL?
    /// Listas: si es tuya, la API da sus canciones; de las demás solo los datos.
    var ownPlaylist = false

    /// Lee un objeto de la API (canción, álbum, lista o artista); nil si viene vacío o incompleto.
    init?(json: [String: Any]?, ownerID: String? = nil) {
        guard let json, let uri = json["uri"] as? String, let name = json["name"] as? String,
              let type = json["type"] as? String else { return nil }
        let artists = (json["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
        let images = (json["images"] as? [[String: Any]]) ?? ((json["album"] as? [String: Any])?["images"] as? [[String: Any]]) ?? []
        switch type {
        case "track":
            kind = .track
            subtitle = artists
        case "album":
            kind = .album
            subtitle = "Álbum · " + artists
        case "playlist":
            kind = .playlist
            let owner = json["owner"] as? [String: Any]
            subtitle = "Lista · " + (owner?["display_name"] as? String ?? "")
            ownPlaylist = ownerID != nil && owner?["id"] as? String == ownerID
        case "artist":
            kind = .artist
            subtitle = "Artista"
        default: return nil
        }
        id = uri
        self.uri = uri
        title = name
        // La imagen más pequeña que se vea nítida a 40 pt (las devuelve de mayor a menor).
        let urls = images.compactMap { image -> (Int, URL)? in
            guard let s = image["url"] as? String, let url = URL(string: s) else { return nil }
            return ((image["width"] as? Int) ?? 0, url)
        }
        image = (urls.last { $0.0 >= 80 } ?? urls.first)?.1
    }
}

enum BubbleTab: String, CaseIterable, Identifiable {
    case search = "Buscar", playlists = "Listas", liked = "Me gusta", recent = "Recientes", queue = "Cola"
    var id: String { rawValue }
}

@MainActor
final class SpotifyBubbleModel: ObservableObject {
    struct Section: Identifiable {
        let title: String?
        let items: [SpotifyItem]
        var id: String { title ?? "" }
    }

    enum State: Equatable { case needsSession, loading, ready, failed(String) }

    @Published var tab: BubbleTab = .playlists
    @Published var query = ""
    @Published var sections: [Section] = []
    @Published var state: State = .loading
    /// Lista abierta dentro de la burbuja (sus canciones), o nil.
    @Published var openPlaylist: SpotifyItem?
    /// Aviso corto tras una acción ("Añadida a la cola").
    @Published var notice: String?
    /// Fila bajo el ratón (muestra sus botones).
    @Published var hovered: String?

    private let account: SpotifyAccount
    private let remote: SpotifyRemote
    /// La búsqueda va con la clave de cliente (como "pon tal canción"): no necesita permisos de la sesión.
    private let web = SpotifyWeb()
    /// Lo último cargado de cada pestaña, para mostrarlo al instante mientras se actualiza.
    private var cache: [BubbleTab: [Section]] = [:]
    private var cachedAt: [BubbleTab: Date] = [:]
    /// Carátulas reducidas, compartidas por todas las filas mientras la burbuja existe.
    let thumbnails = ThumbnailStore()
    private var myID: String?
    private var loadTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "burbuja")

    init(account: SpotifyAccount, remote: SpotifyRemote) {
        self.account = account
        self.remote = remote
    }

    /// Al cerrar la burbuja se sueltan las carátulas, que es lo que ocupa memoria. Las listas cargadas (texto,
    /// unos KB) se quedan para que al volver a abrirla se vean al instante.
    func clear() {
        loadTask?.cancel()
        sections = []
        hovered = nil
        openPlaylist = nil
        thumbnails.removeAll()
    }

    func appeared() {
        guard account.isReady else { state = .needsSession; return }
        reload()
    }

    func connect() {
        state = .loading
        Task {
            do {
                try await account.ensureSession()
                reload()
            } catch {
                state = .failed("No se pudo conectar con Spotify.")
            }
        }
    }

    /// Carga la pestaña con la que se abre la burbuja, sin mostrar nada, si lo guardado tiene más de 1 minuto.
    /// Así también se renueva el token de la sesión antes de abrirla.
    func prefetch() {
        let tab = tab
        guard account.isReady, tab != .search, Date().timeIntervalSince(cachedAt[tab] ?? .distantPast) > 60 else { return }
        cachedAt[tab] = Date()
        Task {
            guard let result = try? await load(tab, query: "") else { return }
            cache[tab] = result
            cachedAt[tab] = Date()
        }
    }

    func select(_ tab: BubbleTab) {
        self.tab = tab
        openPlaylist = nil
        reload()
    }

    /// Búsqueda al escribir, con una pausa corta para no pedir una por letra.
    func queryChanged() {
        guard tab == .search else { return }
        reload(after: 0.35)
    }

    func reload(after delay: TimeInterval = 0) {
        loadTask?.cancel()
        let tab = tab, query = query, playlist = openPlaylist
        if tab == .search, query.trimmingCharacters(in: .whitespaces).isEmpty, playlist == nil {
            sections = []
            state = .ready
            return
        }
        // Lo que ya se cargó antes se ve al instante; se actualiza por detrás.
        if playlist == nil, tab != .search, let cached = cache[tab] {
            sections = cached
            state = .ready
        } else {
            state = .loading
        }
        loadTask = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            let start = Date()
            do {
                let result: [Section]
                if let playlist { result = try await loadPlaylist(playlist) } else { result = try await load(tab, query: query) }
                guard !Task.isCancelled else { return }
                sections = result
                state = .ready
                if playlist == nil, tab != .search {
                    cache[tab] = result
                    cachedAt[tab] = Date()
                }
                log.notice("\(tab.rawValue, privacy: .public): \(result.reduce(0) { $0 + $1.items.count }) elementos en \(String(format: "%.2f", Date().timeIntervalSince(start)), privacy: .public) s")
            } catch {
                guard !Task.isCancelled else { return }
                log.error("\(tab.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                state = .failed("No se pudo cargar. Inténtalo de nuevo.")
            }
        }
    }

    private func load(_ tab: BubbleTab, query: String) async throws -> [Section] {
        switch tab {
        case .search:
            // Desde febrero de 2026 la búsqueda da como mucho 10 resultados por tipo.
            let json = try await web.searchJSON(query, types: "track,artist,album,playlist", limit: 6)
            let list = { (key: String) in
                ((json[key] as? [String: Any])?["items"] as? [Any] ?? []).compactMap { SpotifyItem(json: $0 as? [String: Any]) }
            }
            return [Section(title: "Canciones", items: list("tracks")), Section(title: "Artistas", items: list("artists")),
                    Section(title: "Álbumes", items: list("albums")), Section(title: "Listas", items: list("playlists"))]
                .filter { !$0.items.isEmpty }
        case .playlists:
            let me = try await meID()
            let json = try await account.get("/me/playlists", ["limit": "50"])
            let items = (json["items"] as? [[String: Any]] ?? []).compactMap { SpotifyItem(json: $0, ownerID: me) }
            return [Section(title: nil, items: items)]
        case .liked:
            let json = try await account.get("/me/tracks", ["limit": "50", "market": "from_token"])
            return [Section(title: nil, items: Self.tracks(json["items"]))]
        case .recent:
            let json = try await account.get("/me/player/recently-played", ["limit": "40"])
            var seen = Set<String>()
            let items = Self.tracks(json["items"]).filter { seen.insert($0.uri).inserted }
            return [Section(title: nil, items: items)]
        case .queue:
            let json = try await account.get("/me/player/queue")
            let now = SpotifyItem(json: json["currently_playing"] as? [String: Any])
            let next = (json["queue"] as? [[String: Any]] ?? []).compactMap { SpotifyItem(json: $0) }
            return [Section(title: "Sonando", items: now.map { [$0] } ?? []), Section(title: "A continuación", items: next)]
                .filter { !$0.items.isEmpty }
        }
    }

    /// Canciones de una lista. Solo las tuyas traen canciones; de las demás solo se puede reproducir entera.
    private func loadPlaylist(_ playlist: SpotifyItem) async throws -> [Section] {
        guard playlist.ownPlaylist, let id = playlist.uri.split(separator: ":").last else { return [] }
        let json = try await account.get("/playlists/\(id)/items", ["limit": "100", "market": "from_token"])
        return [Section(title: nil, items: Self.tracks(json["items"]))]
    }

    /// Elementos que envuelven una canción: `{track: …}` en Me gusta y Recientes, `{item: …}` en las listas.
    private static func tracks(_ value: Any?) -> [SpotifyItem] {
        (value as? [[String: Any]] ?? []).compactMap { SpotifyItem(json: ($0["item"] ?? $0["track"]) as? [String: Any]) }
    }

    private func meID() async throws -> String? {
        if myID == nil { myID = try await account.get("/me")["id"] as? String }
        return myID
    }

    /// Canción: suena (dentro de la lista abierta, si hay). Lista: se abre si es tuya; si no, suena entera.
    /// Álbum y artista: suenan enteros.
    func activate(_ item: SpotifyItem) {
        if item.kind == .playlist, item.ownPlaylist {
            openPlaylist = item
            reload()
            return
        }
        play(item.uri, in: item.kind == .track ? openPlaylist?.uri : nil)
    }

    func play(_ uri: String, in context: String? = nil) {
        let start = Date()
        remote.play(uri, in: context) { [weak self] state in
            self?.log.notice("reproducir \(uri, privacy: .public): \(state ?? "falló", privacy: .public) en \(String(format: "%.2f", Date().timeIntervalSince(start)), privacy: .public) s")
            if state != "playing" { self?.show("Spotify no respondió") }
        }
    }

    func enqueue(_ item: SpotifyItem) {
        Task {
            do {
                try await account.enqueue(item.uri)
                show("Añadida a la cola")
                if tab == .queue { reload() }
            } catch {
                show("No se pudo añadir: ¿Spotify está abierto?")
            }
        }
    }

    private func show(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if notice == text { notice = nil }
        }
    }
}

struct SpotifyBubbleView: View {
    @ObservedObject var model: SpotifyBubbleModel
    var close: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.green))
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
        .onExitCommand(perform: close)
        .animation(.easeOut(duration: 0.15), value: model.notice)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(BubbleTab.allCases) { tab in
                    Button { model.select(tab); if tab == .search { searchFocused = true } } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.tab == tab ? .black : .white.opacity(0.8))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(model.tab == tab ? Theme.green : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Cerrar (Esc)")
            }
            if model.tab == .search, model.openPlaylist == nil {
                TextField("Canciones, artistas, álbumes o listas", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .focused($searchFocused)
                    .onChange(of: model.query) { model.queryChanged() }
                    .onAppear { searchFocused = true }
            }
            if let playlist = model.openPlaylist {
                HStack {
                    Button { model.openPlaylist = nil; model.reload() } label: {
                        Label("Listas", systemImage: "chevron.left").font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                    Text(playlist.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Button { model.play(playlist.uri) } label: {
                        Label("Reproducir", systemImage: "play.fill").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Theme.green))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .needsSession:
            VStack(spacing: 12) {
                Text("Conecta Capri con tu cuenta de Spotify para ver tus listas, tus Me gusta y la cola.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                Button("Conectar con Spotify", action: model.connect)
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 7).background(Capsule().fill(Theme.green))
            }
            .padding(30)
        case .loading:
            ProgressView().controlSize(.small)
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                Button("Reintentar") { model.reload() }.buttonStyle(.plain).foregroundStyle(Theme.green)
            }
        case .ready:
            if model.sections.isEmpty {
                Text(emptyText).font(.system(size: 13)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center).padding(30)
            } else {
                list
            }
        }
    }

    private var emptyText: String {
        if model.openPlaylist != nil { return "Spotify solo da las canciones de tus propias listas. Esta se puede reproducir entera." }
        switch model.tab {
        case .search: return model.query.isEmpty ? "Escribe para buscar." : "Sin resultados."
        case .queue: return "No hay nada sonando en Spotify."
        default: return "No hay nada aquí todavía."
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(model.sections) { section in
                    if let title = section.title {
                        Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
                    }
                    ForEach(section.items) { item in
                        BubbleRow(item: item, thumbnail: model.thumbnails.loader(for: item.image), hover: model.hovered == item.id, activate: { model.activate(item) },
                                  enqueue: { model.enqueue(item) },
                                  onHover: { inside in
                                      if inside { model.hovered = item.id } else if model.hovered == item.id { model.hovered = nil }
                                  })
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct BubbleRow: View {
    let item: SpotifyItem
    @ObservedObject var thumbnail: Thumbnail
    let hover: Bool
    let activate: () -> Void
    let enqueue: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Color.white.opacity(0.08)
                if let image = thumbnail.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 40, height: 40)
            .onAppear { thumbnail.load() }
            .clipShape(item.kind == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if hover {
                if item.kind == .track {
                    Button(action: enqueue) {
                        Image(systemName: "text.badge.plus").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Añadir a la cola")
                }
                Image(systemName: item.kind == .playlist && item.ownPlaylist ? "chevron.right" : "play.fill")
                    .font(.system(size: 11)).foregroundStyle(Theme.green)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hover ? 0.07 : 0)).padding(.horizontal, 6))
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: activate)
    }
}

/// Ventana de la burbuja. A diferencia del panel del notch, puede recibir el teclado (para buscar) sin
/// activar Capri: la app en la que estabas sigue al frente. Se cierra con Esc, con la X, al volver a pulsar el
/// botón o al hacer clic fuera.
final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SpotifyBubbleController {
    static let size = CGSize(width: 380, height: 460)
    var onVisibilityChange: (Bool) -> Void = { _ in }
    private var panel: BubblePanel?
    private var outsideMonitor: Any?
    private let model: SpotifyBubbleModel

    init(account: SpotifyAccount, remote: SpotifyRemote) {
        model = SpotifyBubbleModel(account: account, remote: remote)
    }

    var isVisible: Bool { panel?.isVisible == true }

    func prefetch() { model.prefetch() }

    /// `top` es el borde inferior de lo que tiene encima (en coordenadas de pantalla); `centerX`, el de la cámara.
    func toggle(centerX: CGFloat, top: CGFloat) {
        isVisible ? hide() : show(centerX: centerX, top: top)
    }

    func show(centerX: CGFloat, top: CGFloat) {
        let size = Self.size
        let frame = NSRect(x: centerX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        model.appeared()
        // Clic en otra app: se cierra. Los clics en el panel del notch los decide él.
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        onVisibilityChange(true)
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        outsideMonitor.map(NSEvent.removeMonitor)
        outsideMonitor = nil
        panel.orderOut(nil)
        model.clear()
        onVisibilityChange(false)
    }

    private func makePanel() -> BubblePanel {
        let panel = BubblePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Por encima de la ventana del notch: es transparente pero más alta que el panel y, debajo de ella,
        // la parte de arriba de la burbuja no recibía algunos clics.
        panel.level = .mainMenu + 4
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: SpotifyBubbleView(model: model, close: { [weak self] in self?.hide() }))
        panel.contentView = hosting
        return panel
    }
}

/// Carátula de una fila: se descarga una vez y se reduce a 80 px (40 pt en Retina) antes de guardarla.
/// Las de 300 px de la API, decodificadas a tamaño completo, sumaban decenas de MB con unas cuantas listas.
@MainActor
final class Thumbnail: ObservableObject {
    @Published private(set) var image: NSImage?
    private let url: URL?
    private var started = false

    init(url: URL?) { self.url = url }

    func load() {
        guard !started, let url else { return }
        started = true
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 80,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary)
            else { return }
            image = NSImage(cgImage: cg, size: NSSize(width: 40, height: 40))
        }
    }
}

@MainActor
final class ThumbnailStore {
    private var loaders: [URL: Thumbnail] = [:]
    private let none = Thumbnail(url: nil)

    func loader(for url: URL?) -> Thumbnail {
        guard let url else { return none }
        if let loader = loaders[url] { return loader }
        let loader = Thumbnail(url: url)
        loaders[url] = loader
        return loader
    }

    func removeAll() { loaders = [:] }
}
