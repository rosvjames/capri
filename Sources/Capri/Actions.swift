import AppKit
import os

/// Lo que Capri sabe hacer en el Mac (C-06 a C-09, C-36). Sale de la vía rápida (`QuickCommands`) o de la
/// herramienta que eligió el modelo (`Tools`), y en los dos casos se valida aquí: lo que escribe el modelo
/// nunca se ejecuta tal cual.
enum Action: Equatable {
    case tellTime
    case tellDate
    /// La hora en otro sitio: nombre para decir y zona horaria (IANA, "Asia/Tokyo").
    case tellTimeIn(place: String, zone: String)
    case openApp(String)
    case openWebsite(String)
    case volume(VolumeChange)
    case music(MusicRequest)
}

enum VolumeChange: Equatable {
    case up, down, mute, unmute
    /// Nivel de 0 a 100.
    case set(Int)
}

enum MusicRequest: Equatable {
    case pause, play, next, previous, nowPlaying
    /// Canción, artista o álbum.
    case search(String, MusicKind)
    /// Me gusta (true) o quitarlo (false) a lo que suena. Necesita la sesión de Spotify.
    case like(Bool)
    /// Añadir una canción a la cola, buscándola. Necesita la sesión de Spotify.
    case enqueue(String)
    /// Poner una de tus listas por su nombre. Necesita la sesión de Spotify.
    case playlist(String)
}

/// Lo que Capri dice al terminar y si la acción se hizo de verdad.
struct ActionOutcome {
    let spoken: String
    let succeeded: Bool

    static func done(_ spoken: String) -> ActionOutcome { ActionOutcome(spoken: spoken, succeeded: true) }
    static func failed(_ spoken: String) -> ActionOutcome { ActionOutcome(spoken: spoken, succeeded: false) }
}

/// Las herramientas que se le ofrecen al modelo y su validación. Para añadir una: su definición aquí, su caso
/// en `Action` y en `action(from:)`, y su ejecución en `ActionRunner`.
///
/// Cada herramienta ocupa tokens en cada pregunta (las cinco, ~700): las descripciones son cortas.
enum Tools {
    static let definitions: [[String: Any]] = [
        [
            // El modelo se equivoca al sumar husos horarios: solo elige la zona y la hora la calcula el Mac.
            "name": "hora_en",
            "description": "Dice la hora actual en otra ciudad o país.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "lugar": ["type": "string", "description": "Como lo dijo James, p. ej. Tokio"],
                    "zona": ["type": "string", "description": "Zona horaria IANA, p. ej. Asia/Tokyo"],
                ],
                "required": ["lugar", "zona"],
            ],
        ],
        [
            "name": "abrir_app",
            "description": "Abre una app del Mac.",
            "input_schema": [
                "type": "object",
                "properties": ["nombre": ["type": "string", "description": "Nombre de la app, p. ej. Safari"]],
                "required": ["nombre"],
            ],
        ],
        [
            "name": "abrir_sitio",
            "description": "Abre un sitio web en el navegador.",
            "input_schema": [
                "type": "object",
                "properties": ["direccion": ["type": "string", "description": "Dominio o URL, p. ej. youtube.com"]],
                "required": ["direccion"],
            ],
        ],
        [
            "name": "volumen",
            "description": "Cambia el volumen del Mac.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "accion": ["type": "string", "enum": ["subir", "bajar", "silenciar", "quitar_silencio", "fijar"]],
                    "nivel": ["type": "integer", "minimum": 0, "maximum": 100, "description": "Solo con fijar"],
                ],
                "required": ["accion"],
            ],
        ],
        [
            "name": "musica",
            "description": "Controla Spotify o busca qué poner.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "accion": ["type": "string", "enum": ["pausar", "seguir", "siguiente", "anterior", "que_suena", "poner",
                                                          "me_gusta", "quitar_me_gusta", "a_la_cola", "mi_lista"]],
                    "busqueda": ["type": "string", "description": "Con poner y a_la_cola: qué buscar, p. ej. Tusa Karol G. Con mi_lista: nombre de la lista"],
                    "tipo": ["type": "string", "enum": ["cancion", "artista", "album"], "description": "Solo con poner"],
                ],
                "required": ["accion"],
            ],
        ],
    ]

    /// La llamada a la herramienta equivalente a una orden de la vía rápida, para el historial. La hora y la
    /// fecha no tienen herramienta: el modelo ya las sabe.
    static func call(for action: Action) -> ToolCall? {
        switch action {
        case .tellTime, .tellDate: return nil
        case .tellTimeIn(let place, let zone): return .local(name: "hora_en", input: ["lugar": place, "zona": zone])
        case .openApp(let name): return .local(name: "abrir_app", input: ["nombre": name])
        case .openWebsite(let address): return .local(name: "abrir_sitio", input: ["direccion": address])
        case .volume(let change):
            switch change {
            case .up: return .local(name: "volumen", input: ["accion": "subir"])
            case .down: return .local(name: "volumen", input: ["accion": "bajar"])
            case .mute: return .local(name: "volumen", input: ["accion": "silenciar"])
            case .unmute: return .local(name: "volumen", input: ["accion": "quitar_silencio"])
            case .set(let level): return .local(name: "volumen", input: ["accion": "fijar", "nivel": level])
            }
        case .music(let request):
            switch request {
            case .pause: return .local(name: "musica", input: ["accion": "pausar"])
            case .play: return .local(name: "musica", input: ["accion": "seguir"])
            case .next: return .local(name: "musica", input: ["accion": "siguiente"])
            case .previous: return .local(name: "musica", input: ["accion": "anterior"])
            case .nowPlaying: return .local(name: "musica", input: ["accion": "que_suena"])
            case .search(let query, let kind):
                let tipo = switch kind {
                case .track: "cancion"
                case .artist: "artista"
                case .album: "album"
                }
                return .local(name: "musica", input: ["accion": "poner", "busqueda": query, "tipo": tipo])
            case .like(let value): return .local(name: "musica", input: ["accion": value ? "me_gusta" : "quitar_me_gusta"])
            case .enqueue(let query): return .local(name: "musica", input: ["accion": "a_la_cola", "busqueda": query])
            case .playlist(let name): return .local(name: "musica", input: ["accion": "mi_lista", "busqueda": name])
            }
        }
    }

    /// La acción que pide la herramienta, o nil si el nombre o los datos no son válidos.
    static func action(from call: ToolCall) -> Action? {
        guard let input = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any] else { return nil }
        func text(_ key: String) -> String? {
            guard let value = (input[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty, value.count <= 200 else { return nil }
            return value
        }
        switch call.name {
        case "hora_en":
            guard let place = text("lugar"), let zone = text("zona"), TimeZone(identifier: zone) != nil else { return nil }
            return .tellTimeIn(place: place, zone: zone)
        case "abrir_app":
            return text("nombre").map(Action.openApp)
        case "abrir_sitio":
            return text("direccion").map(Action.openWebsite)
        case "volumen":
            switch text("accion") {
            case "subir": return .volume(.up)
            case "bajar": return .volume(.down)
            case "silenciar": return .volume(.mute)
            case "quitar_silencio": return .volume(.unmute)
            case "fijar":
                guard let level = (input["nivel"] as? NSNumber)?.intValue else { return nil }
                return .volume(.set(min(max(level, 0), 100)))
            default: return nil
            }
        case "musica":
            switch text("accion") {
            case "pausar": return .music(.pause)
            case "seguir": return .music(.play)
            case "siguiente": return .music(.next)
            case "anterior": return .music(.previous)
            case "que_suena": return .music(.nowPlaying)
            case "poner":
                let kind: MusicKind = switch text("tipo") {
                case "artista": .artist
                case "album": .album
                default: .track
                }
                return text("busqueda").map { .music(.search($0, kind)) }
            case "me_gusta": return .music(.like(true))
            case "quitar_me_gusta": return .music(.like(false))
            case "a_la_cola": return text("busqueda").map { .music(.enqueue($0)) }
            case "mi_lista": return text("busqueda").map { .music(.playlist($0)) }
            default: return nil
            }
        default:
            return nil
        }
    }
}

/// Ejecuta las acciones y comprueba el resultado antes de confirmarlo. La confirmación sale de una plantilla
/// local: no hace falta una segunda llamada al modelo. `done` llega en el hilo principal.
final class ActionRunner {
    let music: MusicWatcher
    let apps = AppCatalog()
    let spotifyWeb = SpotifyWeb()
    /// Lo que cambia el volumen con "sube" o "baja" (de 0 a 100).
    static let volumeStep = 10
    fileprivate let log = Logger(subsystem: "com.rosvjames.capri", category: "acciones")

    /// Sesión de Spotify, para Me gusta, la cola y tus listas; nil en las pruebas sin app.
    let account: SpotifyAccount?
    /// Me gusta cambió por voz: el panel lo muestra (canción, nuevo valor).
    var onLiked: (String, Bool) -> Void = { _, _ in }

    init(music: MusicWatcher, account: SpotifyAccount? = nil) {
        self.music = music
        self.account = account
    }

    func perform(_ action: Action, done: @escaping (ActionOutcome) -> Void) {
        let start = Date()
        let finish = { [log] (outcome: ActionOutcome) in
            DispatchQueue.main.async {
                log.notice("\(String(describing: action), privacy: .public): \(outcome.succeeded ? "hecha" : "falló", privacy: .public) en \(Date().timeIntervalSince(start), format: .fixed(precision: 2)) s")
                done(outcome)
            }
        }
        switch action {
        case .tellTime: finish(.done(SpokenTime.time(Date())))
        case .tellDate: finish(.done(SpokenTime.date(Date())))
        case .tellTimeIn(let place, let zone): finish(.done(SpokenTime.time(Date(), in: place, zone: zone)))
        case .openApp(let name): openApp(name, finish)
        case .openWebsite(let address): openWebsite(address, finish)
        case .volume(let change): finish(Self.changeVolume(change))
        case .music(let request): music(request, finish)
        }
    }

    // MARK: Apps y sitios (C-07, C-08)

    private func openApp(_ name: String, _ done: @escaping (ActionOutcome) -> Void) {
        guard let app = apps.find(name) else {
            // "Abre YouTube" puede llegar como app: si es un sitio conocido, se abre el sitio.
            if Websites.known(name) != nil { return openWebsite(name, done) }
            return done(.failed("No encuentro esa app."))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // La respuesta llega cuando la app ya está abierta (o activada, si ya lo estaba).
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [log] running, error in
            if let error { log.error("no se abrió \(app.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)") }
            done(running != nil ? .done("Abriendo \(app.name).") : .failed("No pude abrir \(app.name)."))
        }
    }

    private func openWebsite(_ address: String, _ done: @escaping (ActionOutcome) -> Void) {
        guard let site = Websites.resolve(address) else { return done(.failed("Esa dirección no es válida.")) }
        NSWorkspace.shared.open(site.url, configuration: NSWorkspace.OpenConfiguration()) { [log] running, error in
            if let error { log.error("no se abrió el sitio: \(error.localizedDescription, privacy: .public)") }
            done(running != nil ? .done("Abriendo \(site.name).") : .failed("No pude abrir \(site.name)."))
        }
    }

    // MARK: Volumen (C-36)

    private static func changeVolume(_ change: VolumeChange) -> ActionOutcome {
        guard let current = SystemVolume.level else { return .failed("No puedo cambiar el volumen de esta salida de audio.") }
        let percent = Int((current * 100).rounded())
        var target: Int
        switch change {
        case .mute:
            return SystemVolume.setMuted(true) ? .done("Silencio.") : .failed("No pude silenciar el Mac.")
        case .unmute:
            guard SystemVolume.setMuted(false) else { return .failed("No pude quitar el silencio.") }
            return .done("Volumen al \(percent) por ciento.")
        case .up:
            if percent >= 100, SystemVolume.isMuted != true { return .done("Ya está al máximo.") }
            target = percent + volumeStep
        case .down:
            if percent <= 0 { return .done("Ya está al mínimo.") }
            target = percent - volumeStep
        case .set(let level):
            target = level
        }
        target = min(max(target, 0), 100)
        // Como con las teclas de volumen: subirlo quita el silencio.
        guard SystemVolume.setLevel(Float(target) / 100), target == 0 || SystemVolume.setMuted(false),
              let now = SystemVolume.level else { return .failed("No pude cambiar el volumen.") }
        return .done("Volumen al \(Int((now * 100).rounded())) por ciento.")
    }

    // MARK: Música (C-09)

    private func music(_ request: MusicRequest, _ done: @escaping (ActionOutcome) -> Void) {
        let spotify = music.spotify
        switch request {
        case .nowPlaying:
            let say = { (now: NowPlaying?) in
                guard let now else { return done(.done("No suena nada.")) }
                let song = now.artist.isEmpty ? now.title : "\(now.title), de \(now.artist)"
                done(.done(now.isPlaying ? "Suena \(song)." : "En pausa: \(song)."))
            }
            // Sin aviso de Spotify todavía (lo que ya sonaba al abrir Capri), se le pregunta.
            guard music.current == nil, SpotifyRemote.isRunning else { return say(music.current) }
            spotify.readNowPlaying(ask: true, say)
        case .search(let query, let kind):
            guard SpotifyWeb.hasCredentials else { return openSearch(query, done) }
            spotifyWeb.search(query, kind: kind) { [self] result in
                switch result {
                case .success(let found):
                    spotify.play(found.uri) { state in
                        guard let state else { return done(.failed("Spotify no respondió.")) }
                        done(state == "playing" ? .done("Pongo \(found.spoken).") : .failed("Spotify no empezó a sonar."))
                    }
                case .failure(.notFound):
                    done(.failed("No encontré eso en Spotify."))
                case .failure(.premiumRequired):
                    log.error("la API de Spotify pide Premium en la cuenta dueña de la app")
                    openSearch(query, done)
                case .failure:
                    // Sin internet o credenciales no válidas: al menos la búsqueda en la app.
                    openSearch(query, done)
                }
            }
        case .like(let value):
            guard let account, account.isReady else { return done(.failed(Self.needsSession)) }
            guard let id = music.current?.trackID, id.hasPrefix("spotify:track:") else { return done(.failed("No suena ninguna canción.")) }
            account.setSaved(id, value) { [self] saved in
                guard let saved else { return done(.failed("Spotify no respondió.")) }
                onLiked(id, saved)
                done(.done(saved ? "Guardada en tus Me gusta." : "Quitada de tus Me gusta."))
            }
        case .enqueue(let query):
            guard let account, account.isReady else { return done(.failed(Self.needsSession)) }
            guard SpotifyRemote.isRunning else { return done(.failed("Spotify está cerrado.")) }
            // Solo canciones: la cola de Spotify no acepta álbumes ni artistas enteros.
            spotifyWeb.search(query, kind: .track) { result in
                guard case .success(let found) = result else { return done(.failed("No encontré esa canción.")) }
                Task { @MainActor in
                    do {
                        try await account.enqueue(found.uri)
                        done(.done("Añadí \(found.spoken) a la cola."))
                    } catch {
                        done(.failed("No pude añadirla a la cola."))
                    }
                }
            }
        case .playlist(let name):
            guard let account, account.isReady else { return done(.failed(Self.needsSession)) }
            Task { @MainActor [self] in
                guard let list = await Self.findPlaylist(name, account: account) else {
                    return done(.failed("No encuentro esa lista entre las tuyas."))
                }
                spotify.play(list.uri) { state in
                    done(state == "playing" ? .done("Pongo tu lista \(list.name).") : .failed("Spotify no empezó a sonar."))
                }
            }
        case .pause, .play, .next, .previous:
            guard SpotifyRemote.isRunning else { return done(.failed("Spotify está cerrado.")) }
            let command: MusicCommand = switch request {
            case .pause: .pause
            case .play: .play
            case .next: .next
            default: .previous
            }
            // El script devuelve el estado del reproductor después de la orden: así se comprueba.
            spotify.control(command) { state in
                guard let state else {
                    return done(.failed(spotify.permission == .denied
                        ? "Necesito permiso para controlar Spotify, en Ajustes del Sistema."
                        : "Spotify no respondió."))
                }
                switch command {
                case .pause: done(state == "paused" ? .done("En pausa.") : .failed("Spotify no se pausó."))
                case .play: done(state == "playing" ? .done("Sigue.") : .failed("Spotify no empezó a sonar."))
                case .next: done(.done("Siguiente."))
                default: done(.done("Anterior."))
                }
            }
        }
    }
}

extension ActionRunner {
    static let needsSession = "Primero conecta tu cuenta de Spotify: abre la burbuja de Spotify en el panel de música."

    /// La lista tuya (o que sigues) que mejor coincide con lo que dijiste: igual, luego que la contenga, luego la
    /// que comparte más palabras. Se miran hasta 100 listas.
    @MainActor
    fileprivate static func findPlaylist(_ spoken: String, account: SpotifyAccount) async -> (uri: String, name: String)? {
        var lists: [(uri: String, name: String)] = []
        for offset in [0, 50] {
            guard let json = try? await account.get("/me/playlists", ["limit": "50", "offset": String(offset)]) else { break }
            let items = json["items"] as? [[String: Any]] ?? []
            lists += items.compactMap { item in
                guard let uri = item["uri"] as? String, let name = item["name"] as? String else { return nil }
                return (uri, name)
            }
            if items.count < 50 { break }
        }
        let target = QuickCommands.normalize(spoken)
        let words = Set(target.split(separator: " "))
        let scored = lists.map { list -> (Int, (uri: String, name: String)) in
            let name = QuickCommands.normalize(list.name)
            if name == target { return (1000, list) }
            if name.contains(target) || target.contains(name) { return (500 - abs(name.count - target.count), list) }
            return (Set(name.split(separator: " ")).intersection(words).count * 10, list)
        }
        guard let best = scored.max(by: { $0.0 < $1.0 }), best.0 > 0 else { return nil }
        return best.1
    }

    /// Sin la API web de Spotify no se puede elegir un resultado: se abre la búsqueda en la app (o en la web si
    /// no está instalada).
    fileprivate func openSearch(_ query: String, _ done: @escaping (ActionOutcome) -> Void) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: ":/"))) else {
            return done(.failed("No pude buscar eso."))
        }
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicWatcher.spotifyID) != nil
        let url = URL(string: installed ? "spotify:search:\(encoded)" : "https://open.spotify.com/search/\(encoded)")!
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { running, _ in
            done(running != nil ? .done("Te dejé la búsqueda en Spotify.") : .failed("No pude abrir Spotify."))
        }
    }
}

/// Sitios que se abren por su nombre ("abre YouTube") y validación de direcciones.
enum Websites {
    struct Site {
        let name: String
        let url: URL
    }

    /// Nombre normalizado (`AppCatalog.normalize`) → nombre para decir y dirección.
    private static let table: [String: (String, String)] = [
        "youtube": ("YouTube", "https://www.youtube.com"),
        "google": ("Google", "https://www.google.com"),
        "gmail": ("Gmail", "https://mail.google.com"),
        "drive": ("Google Drive", "https://drive.google.com"),
        "googledrive": ("Google Drive", "https://drive.google.com"),
        "maps": ("Google Maps", "https://maps.google.com"),
        "googlemaps": ("Google Maps", "https://maps.google.com"),
        "calendar": ("Google Calendar", "https://calendar.google.com"),
        "googlecalendar": ("Google Calendar", "https://calendar.google.com"),
        "github": ("GitHub", "https://github.com"),
        "chatgpt": ("ChatGPT", "https://chatgpt.com"),
        "claude": ("Claude", "https://claude.ai"),
        "gemini": ("Gemini", "https://gemini.google.com"),
        "netflix": ("Netflix", "https://www.netflix.com"),
        "twitter": ("X", "https://x.com"),
        "x": ("X", "https://x.com"),
        "instagram": ("Instagram", "https://www.instagram.com"),
        "facebook": ("Facebook", "https://www.facebook.com"),
        "whatsapp": ("WhatsApp", "https://web.whatsapp.com"),
        "whatsappweb": ("WhatsApp", "https://web.whatsapp.com"),
        "wikipedia": ("Wikipedia", "https://es.wikipedia.org"),
        "amazon": ("Amazon", "https://www.amazon.com"),
        "linkedin": ("LinkedIn", "https://www.linkedin.com"),
        "reddit": ("Reddit", "https://www.reddit.com"),
        "twitch": ("Twitch", "https://www.twitch.tv"),
        "notion": ("Notion", "https://www.notion.so"),
        "figma": ("Figma", "https://www.figma.com"),
        "outlook": ("Outlook", "https://outlook.live.com"),
        "stackoverflow": ("Stack Overflow", "https://stackoverflow.com"),
    ]

    static func known(_ name: String) -> Site? {
        table[AppCatalog.normalize(name)].flatMap { name, address in URL(string: address).map { Site(name: name, url: $0) } }
    }

    /// Un sitio conocido o una dirección web válida (solo http y https, con dominio), o nil.
    static func resolve(_ address: String) -> Site? {
        if let site = known(address) { return site }
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " punto ", with: ".")
        if !text.contains("://") { text = "https://" + text }
        guard !text.contains(" "), let url = URL(string: text), ["http", "https"].contains(url.scheme),
              let host = url.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              host.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil
        else { return nil }
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return Site(name: name, url: url)
    }
}

/// Las apps instaladas, para abrirlas por su nombre en español o en inglés ("Calculadora", "Calculator",
/// "chat gpt"). Se leen las carpetas de apps la primera vez y otra vez si un nombre no aparece (una app recién
/// instalada); no se consulta en segundo plano.
final class AppCatalog {
    struct App {
        let name: String
        let url: URL
    }

    private var entries: [(key: String, app: App)] = []
    private var loaded = false

    /// Nombres que se dicen distinto de como se llama la app. Con el Mac en inglés, el Finder no da los nombres
    /// en español de las apps del sistema: van aquí.
    private static let aliases: [String: String] = [
        "vscode": "visualstudiocode",
        "code": "visualstudiocode",
        "zoom": "zoomus",
        "ajustes": "systemsettings",
        "ajustesdelsistema": "systemsettings",
        "configuracion": "systemsettings",
        "configuraciondelsistema": "systemsettings",
        "preferencias": "systemsettings",
        "preferenciasdelsistema": "systemsettings",
        "calculadora": "calculator",
        "notas": "notes",
        "calendario": "calendar",
        "recordatorios": "reminders",
        "correo": "mail",
        "mapas": "maps",
        "mensajes": "messages",
        "fotos": "photos",
        "musica": "music",
        "contactos": "contacts",
        "vistaprevia": "preview",
        "libros": "books",
        "noticias": "news",
        "bolsa": "stocks",
        "clima": "weather",
        "eltiempo": "weather",
        "reloj": "clock",
        "notasdevoz": "voicememos",
        "atajos": "shortcuts",
        "tienda": "appstore",
        "editordetexto": "textedit",
        "monitordeactividad": "activitymonitor",
        "utilidaddediscos": "diskutility",
        "capturadepantalla": "screenshot",
        "contrasenas": "passwords",
        "diccionario": "dictionary",
        "telefono": "phone",
        "buscar": "findmy",
    ]

    /// Minúsculas, sin acentos y solo letras y números: "Chat GPT" y "ChatGPT" quedan igual.
    static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
            .unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }

    func find(_ name: String) -> App? {
        let said = Self.normalize(name.replacingOccurrences(of: ".app", with: ""))
        let key = Self.aliases[said] ?? said
        guard key.count >= 2 else { return nil }
        if !loaded { reload() }
        guard let app = lookup(key) ?? { reload(); return lookup(key) }() else { return nil }
        // Por su nombre en español, como lo dijo James: "Abriendo Calculadora", no "Calculator".
        guard key != said else { return app }
        let spoken = name.trimmingCharacters(in: .whitespaces)
        return App(name: spoken.prefix(1).uppercased() + spoken.dropFirst(), url: app.url)
    }

    /// Nombre exacto; si no, el más corto que empiece así; si no, el más corto que lo contenga.
    private func lookup(_ key: String) -> App? {
        func shortest(_ match: (String) -> Bool) -> App? {
            entries.filter { match($0.key) }.min { $0.key.count < $1.key.count }?.app
        }
        return shortest { $0 == key }
            ?? (key.count >= 3 ? shortest { $0.hasPrefix(key) } : nil)
            ?? (key.count >= 4 ? shortest { $0.contains(key) } : nil)
    }

    private func reload() {
        loaded = true
        let manager = FileManager.default
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       "/System/Library/CoreServices/Applications", manager.homeDirectoryForCurrentUser.path + "/Applications"]
        var found = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
        for folder in folders {
            let base = URL(fileURLWithPath: folder)
            // Sin .skipsHiddenFiles: el enlace /Applications/Safari.app está marcado como oculto.
            let items = (try? manager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
            for url in items where !url.lastPathComponent.hasPrefix(".") {
                if url.pathExtension == "app" {
                    found.append(url)
                } else if !["Utilities"].contains(url.lastPathComponent) {
                    // Apps dentro de su propia carpeta ("DaVinci Resolve/DaVinci Resolve.app").
                    let inner = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
                    found += inner.filter { $0.pathExtension == "app" }
                }
            }
        }
        entries = found.flatMap { url -> [(key: String, app: App)] in
            let file = url.deletingPathExtension().lastPathComponent
            // Nombre que muestra el Finder, en el idioma del Mac ("Calculadora").
            let shown = manager.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            let app = App(name: shown, url: url)
            return Set([file, shown]).map { (key: Self.normalize($0), app: app) }
        }
    }
}

/// La hora y la fecha como se dicen (C-06): "Son las nueve y cuarenta de la noche".
enum SpokenTime {
    private static let numbers = ["cero", "una", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve",
                                  "diez", "once", "doce", "trece", "catorce", "quince", "dieciséis", "diecisiete",
                                  "dieciocho", "diecinueve", "veinte", "veintiuno", "veintidós", "veintitrés",
                                  "veinticuatro", "veinticinco", "veintiséis", "veintisiete", "veintiocho", "veintinueve"]
    private static let tens = [3: "treinta", 4: "cuarenta", 5: "cincuenta"]

    /// Minutos en palabras ("un" minuto se dice "uno" en la hora: "las tres y uno").
    private static func minutes(_ m: Int) -> String {
        if m < 30 { return m == 1 ? "uno" : numbers[m] }
        let ten = tens[m / 10]!, unit = m % 10
        return unit == 0 ? ten : "\(ten) y \(unit == 1 ? "uno" : numbers[unit])"
    }

    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let clause = clock(date, calendar: calendar)
        return clause.prefix(1).uppercased() + clause.dropFirst() + "."
    }

    /// "En Tokio es la una y trece de la tarde, ya es miércoles."
    static func time(_ date: Date, in place: String, zone: String) -> String {
        guard let timeZone = TimeZone(identifier: zone) else { return time(date) }
        var there = Calendar.current
        there.timeZone = timeZone
        var text = "En \(place) \(clock(date, calendar: there))"
        let here = Calendar.current
        if there.component(.day, from: date) != here.component(.day, from: date) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_MX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "EEEE"
            let ahead = timeZone.secondsFromGMT(for: date) > here.timeZone.secondsFromGMT(for: date)
            text += (ahead ? ", ya es " : ", todavía es ") + formatter.string(from: date)
        }
        return text + "."
    }

    /// "son las nueve y cuarenta de la noche", sin mayúscula ni punto.
    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date), minute = calendar.component(.minute, from: date)
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let start = twelve == 1 ? "es la una" : "son las \(numbers[twelve])"
        let rest = switch minute {
        case 0: " en punto"
        case 15: " y cuarto"
        case 30: " y media"
        default: " y \(minutes(minute))"
        }
        let part = switch hour {
        case 0..<6: "de la madrugada"
        case 6..<12: "de la mañana"
        case 12: "del mediodía"
        case 13..<20: "de la tarde"
        default: "de la noche"
        }
        return "\(start)\(rest) \(part)"
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "EEEE d 'de' MMMM"
        return "Hoy es \(formatter.string(from: date))."
    }

    /// Para el modelo, que no sabe qué día es: "martes 3 de noviembre de 2026, 21:40 (UTC-05:00)". Con la zona
    /// horaria calcula bien la hora de otros países.
    static func context(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "EEEE d 'de' MMMM 'de' y, HH:mm '(UTC'xxx')'"
        return formatter.string(from: date)
    }
}
