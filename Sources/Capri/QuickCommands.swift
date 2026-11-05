import Foundation

/// Vía rápida: las órdenes comunes se reconocen en el Mac, sin el modelo ("pausa", "¿qué hora es?",
/// "abre Safari"). Responden al instante, no cuestan nada y funcionan sin internet.
///
/// Solo reconoce frases enteras y conocidas: si hay duda, la frase va al modelo, que entiende el resto.
/// Así una pregunta como "¿para qué sirve la pausa?" nunca se toma por una orden.
enum QuickCommands {
    static func match(_ sentence: String, apps: AppCatalog) -> Action? {
        let text = normalize(sentence)
        guard !text.isEmpty else { return nil }
        if let action = fixed[text] { return action }
        if let action = volumeLevel(text) { return action }
        if let action = queueOrPlaylist(text) { return action }
        if let action = song(text) { return action }
        return open(text, apps: apps)
    }

    /// Minúsculas, sin acentos ni signos, sin "Capri" delante ni "por favor".
    static func normalize(_ sentence: String) -> String {
        var text = sentence.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
        text = text.replacingOccurrences(of: "[¿?¡!,;:\"]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\.(\\s|$)", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        for prefix in ["oye capri ", "capri ", "oye ", "por favor "] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        for suffix in [" por favor", " capri"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        return text
    }

    private static func phrases(_ list: [String], _ action: Action) -> [(String, Action)] {
        list.map { ($0, action) }
    }

    /// Frases fijas, ya normalizadas.
    private static let fixed: [String: Action] = Dictionary(
        phrases(["que hora es", "que horas son", "dime la hora", "me dices la hora", "la hora", "hora",
                 "que hora tienes", "que hora es ahorita", "que hora es ahora"], .tellTime)
        + phrases(["que dia es hoy", "que dia es", "que fecha es", "que fecha es hoy", "a cuanto estamos",
                   "a que estamos", "a cuantos estamos", "a cuantos estamos hoy", "dime la fecha", "la fecha",
                   "que dia estamos"], .tellDate)
        + phrases(["sube el volumen", "subele al volumen", "subele", "sube volumen", "mas volumen", "subele tantito",
                   "sube el sonido", "subele un poco", "sube un poco el volumen", "sube el volumen un poco"], .volume(.up))
        + phrases(["baja el volumen", "bajale al volumen", "bajale", "baja volumen", "menos volumen", "bajale tantito",
                   "baja el sonido", "bajale un poco", "baja un poco el volumen", "baja el volumen un poco"], .volume(.down))
        + phrases(["silencio", "silencia", "silencia el mac", "silencia la computadora", "silencia el volumen", "mute",
                   "quita el sonido", "pon el mac en silencio", "pon silencio"], .volume(.mute))
        + phrases(["quita el silencio", "activa el sonido", "unmute", "regresa el sonido", "devuelve el sonido"], .volume(.unmute))
        + phrases(["volumen al maximo", "pon el volumen al maximo", "sube el volumen al maximo", "volumen a tope",
                   "sube todo el volumen"], .volume(.set(100)))
        + phrases(["volumen a la mitad", "pon el volumen a la mitad", "el volumen a la mitad"], .volume(.set(50)))
        + phrases(["pausa", "pausa la musica", "pausa la cancion", "pausala", "pon pausa", "deten la musica",
                   "para la musica", "stop", "quita la musica", "pausa spotify", "deten la cancion", "pausar",
                   "detenla", "parala", "para", "pausa la", "ponle pausa", "pausa esto"], .music(.pause))
        + phrases(["sigue", "continua", "reanuda", "play", "pon play", "dale play", "sigue la musica",
                   "continua la musica", "reanuda la musica", "quita la pausa", "pon la musica", "pon musica",
                   "pon spotify", "sigue con la musica", "reanudala", "reanudar", "reanuda la cancion",
                   "continuala", "continua la cancion", "siguela", "sigue la cancion", "ponla", "dale",
                   "ponle play", "quitale la pausa", "despausa", "despausala"], .music(.play))
        + phrases(["siguiente", "siguiente cancion", "la siguiente", "la que sigue", "pasala", "salta la cancion",
                   "salta esta cancion", "skip", "cambia la cancion", "otra cancion", "pon la siguiente", "cambiala",
                   "saltala", "salta", "otra",
                   "pon la siguiente cancion"], .music(.next))
        + phrases(["anterior", "cancion anterior", "la anterior", "regresa la cancion", "la de antes",
                   "pon la anterior", "pon la cancion anterior", "regresa a la anterior"], .music(.previous))
        + phrases(["que suena", "que esta sonando", "que cancion es", "que cancion es esta", "como se llama esta cancion",
                   "que cancion suena", "quien canta", "quien canta esta cancion", "de quien es esta cancion",
                   "que estoy escuchando", "que es lo que suena"], .music(.nowPlaying))
        + phrases(["dale me gusta", "me gusta", "me gusta esta cancion", "me encanta esta cancion", "dale like", "ponle like",
                   "like", "guardala", "guarda esta cancion", "guarda la cancion", "agregala a mis me gusta",
                   "anadela a mis me gusta", "ponle me gusta", "dale me gusta a esta cancion"], .music(.like(true)))
        + phrases(["quitale el me gusta", "quita el me gusta", "ya no me gusta", "quitale el like", "quita el like",
                   "quitala de mis me gusta", "sacala de mis me gusta", "no me gusta esta cancion"], .music(.like(false))),
        uniquingKeysWith: { first, _ in first })

    /// "Volumen al 40", "pon el volumen en 70 %".
    private static func volumeLevel(_ text: String) -> Action? {
        let pattern = "^(pon |sube |baja |deja )?(el )?volumen (al|a|en) ([0-9]{1,3}) ?(%|por ciento)?$"
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let number = text[match].components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty }
        guard let level = number.flatMap({ Int($0) }), level <= 100 else { return nil }
        return .volume(.set(level))
    }

    /// "Añade X a la cola", "pon mi lista X". "Esta" no cuenta como canción: la cola es para lo que se busca.
    private static func queueOrPlaylist(_ text: String) -> Action? {
        let rules: [(String, (String) -> Action)] = [
            ("^(anade|agrega|mete|pon|encola) (la cancion )?(.+) (a|en) la cola$", { .music(.enqueue($0)) }),
            ("^(pon|ponme|reproduce|toca) (mi lista|mi playlist|la lista|la playlist|mi lista de reproduccion) (de )?(.+)$",
             { .music(.playlist($0)) }),
        ]
        for (pattern, make) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: pattern.hasPrefix("^(anade") ? 3 : 4), in: text) else { continue }
            var query = String(text[range]).trimmingCharacters(in: .whitespaces)
            for filler in ["que se llama ", "llamada ", "que dice "] where query.hasPrefix(filler) { query.removeFirst(filler.count) }
            guard !query.isEmpty, !["esta", "esta cancion", "la", "eso"].contains(query) else { return nil }
            return make(query)
        }
        return nil
    }

    /// Solo frases inequívocas: "pon la canción X", "pon X en Spotify", "pon música de X".
    private static func song(_ text: String) -> Action? {
        let patterns: [(String, MusicKind)] = [
            ("^(pon|ponme|reproduce|toca) (la cancion) (.+)$", .track),
            ("^(pon|ponme|reproduce|toca) (el disco|el album) (.+)$", .album),
            ("^(pon|ponme|reproduce|toca) (musica de|algo de|canciones de) (.+)$", .artist),
            ("^(pon|ponme|reproduce|toca) (.+) en spotify$", .track),
        ]
        for (pattern, kind) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: match.numberOfRanges - 1), in: text) else { continue }
            let query = String(text[range]).trimmingCharacters(in: .whitespaces)
            return query.isEmpty ? nil : .music(.search(query, kind))
        }
        return nil
    }

    /// "Abre Safari", "abre la app de Notas", "abre YouTube", "abre github.com". Si la app no está instalada
    /// y no es un sitio conocido, la frase va al modelo.
    private static func open(_ text: String, apps: AppCatalog) -> Action? {
        let pattern = "^(abre|abrir|abreme|abrime|inicia|lanza|ejecuta|arranca) (la app de |la app |la aplicacion de |la aplicacion |el programa |el sitio de |el sitio |la pagina de |la pagina |la web de )?(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 3), in: text) else { return nil }
        let wantsSite = Range(match.range(at: 2), in: text).map { text[$0].contains("sitio") || text[$0].contains("pagina") || text[$0].contains("web") } ?? false
        var name = String(text[range]).replacingOccurrences(of: " punto ", with: ".")
        for article in ["el ", "la ", "los ", "las "] where name.hasPrefix(article) { name.removeFirst(article.count) }
        guard name.split(separator: " ").count <= 4 else { return nil }
        if !wantsSite, apps.find(name) != nil { return .openApp(name) }
        if Websites.known(name) != nil || (name.contains(".") && Websites.resolve(name) != nil) { return .openWebsite(name) }
        return nil
    }
}
