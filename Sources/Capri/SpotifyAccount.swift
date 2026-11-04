import AppKit
import CryptoKit
import Network
import os

/// Tu sesión de Spotify, solo para "Me gusta": leer si la canción está en Tus me gusta, y guardarla o quitarla.
///
/// Usa el flujo de autorización con PKCE, pensado para apps de escritorio: no hace falta el Client secret. La
/// primera vez, el navegador abre la página de Spotify para aceptar; Spotify vuelve a un servidor que Capri abre
/// un momento en el propio Mac (`http://127.0.0.1:<puerto>/callback`, registrado sin puerto en la app de
/// desarrollador). Capri guarda en el Llavero el token para renovar la sesión (cuenta `spotify-sesion`) y nunca
/// ve tu contraseña. Permisos que pide: leer y modificar tu biblioteca.
final class SpotifyAccount {
    enum Failure: Error { case noClientID, cancelled, failed }

    static let sessionAccount = "spotify-sesion"
    private static let scopes = "user-library-read user-library-modify"
    private var token: String?
    private var tokenExpires = Date.distantPast
    private var login: LoginServer?
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "musica")

    var hasSession: Bool { APIKeys.exists(account: Self.sessionAccount, variable: "SPOTIFY_REFRESH_TOKEN") }

    // MARK: Me gusta

    /// Si la canción está en Tus me gusta; nil sin sesión o si falló. `done` llega en el hilo principal.
    func isSaved(_ uri: String, _ done: @escaping (Bool?) -> Void) {
        guard hasSession, Self.isTrack(uri) else { return done(nil) }
        perform(done) { [self] in
            let data = try await call("GET", "/me/library/contains", uri: uri)
            return (try JSONSerialization.jsonObject(with: data) as? [Bool])?.first
        }
    }

    /// Guarda o quita la canción y devuelve cómo quedó (nil si no se pudo). Sin sesión, la inicia antes.
    func setSaved(_ uri: String, _ saved: Bool, _ done: @escaping (Bool?) -> Void) {
        guard Self.isTrack(uri) else { return done(nil) }
        perform(done) { [self] in
            if !hasSession { try await signIn() }
            _ = try await call(saved ? "PUT" : "DELETE", "/me/library", uri: uri)
            log.notice("me gusta: \(saved ? "guardada" : "quitada", privacy: .public) \(uri, privacy: .public)")
            return saved
        }
    }

    private static func isTrack(_ uri: String) -> Bool {
        uri.range(of: "^spotify:track:[A-Za-z0-9]+$", options: .regularExpression) != nil
    }

    private func perform<T>(_ done: @escaping (T?) -> Void, _ work: @escaping () async throws -> T?) {
        Task {
            let value: T?
            do { value = try await work() } catch {
                log.error("sesión de Spotify: \(String(describing: error), privacy: .public)")
                value = nil
            }
            await MainActor.run { done(value) }
        }
    }

    private func call(_ method: String, _ path: String, uri: String) async throws -> Data {
        var components = URLComponents(string: "https://api.spotify.com/v1" + path)!
        components.queryItems = [URLQueryItem(name: "uris", value: uri)]
        var request = URLRequest(url: components.url!, timeoutInterval: 8)
        request.httpMethod = method
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            log.error("API de Spotify \(status): \(String(decoding: data.prefix(300), as: UTF8.self), privacy: .public)")
            if status == 401 { token = nil }
            throw Failure.failed
        }
        return data
    }

    // MARK: Tokens

    /// Token de una hora; se renueva con el de la sesión guardada en el Llavero.
    private func accessToken() async throws -> String {
        if let token, Date() < tokenExpires { return token }
        guard let refresh = APIKeys.read(account: Self.sessionAccount, variable: "SPOTIFY_REFRESH_TOKEN") else { throw Failure.failed }
        try await requestToken(["grant_type": "refresh_token", "refresh_token": refresh])
        guard let token else { throw Failure.failed }
        return token
    }

    @discardableResult
    private func requestToken(_ fields: [String: String]) async throws -> [String: Any] {
        guard let clientID = APIKeys.read(account: "spotify-id", variable: "SPOTIFY_CLIENT_ID") else { throw Failure.noClientID }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = (fields.merging(["client_id": clientID]) { a, _ in a }).map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard status == 200, let access = json["access_token"] as? String else {
            log.error("token de Spotify \(status): \(json["error"] as? String ?? "", privacy: .public)")
            // La sesión se revocó (en la cuenta de Spotify) o caducó: hay que volver a iniciarla.
            if json["error"] as? String == "invalid_grant" { APIKeys.delete(account: Self.sessionAccount) }
            throw Failure.failed
        }
        token = access
        tokenExpires = Date().addingTimeInterval((json["expires_in"] as? Double ?? 3600) - 60)
        // Spotify puede cambiar el token de la sesión al renovarla: se guarda el nuevo.
        if let refresh = json["refresh_token"] as? String { APIKeys.save(refresh, account: Self.sessionAccount) }
        return json
    }

    // MARK: Inicio de sesión

    /// Abre la página de Spotify en el navegador y espera la respuesta (hasta 3 minutos).
    private func signIn() async throws {
        guard let clientID = APIKeys.read(account: "spotify-id", variable: "SPOTIFY_CLIENT_ID") else { throw Failure.noClientID }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(24)
        let server = LoginServer(state: state)
        login = server
        defer { login = nil }
        let port = try await server.start()
        let redirect = "http://127.0.0.1:\(port)/callback"
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        let url = components.url!
        log.notice("sesión de Spotify: se abre el navegador")
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
        let code = try await server.code(timeout: 180)
        try await requestToken(["grant_type": "authorization_code", "code": code, "redirect_uri": redirect,
                                "code_verifier": verifier])
        log.notice("sesión de Spotify iniciada")
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars.randomElement(using: &generator)! })
    }
}

/// Servidor HTTP mínimo en 127.0.0.1, abierto solo mientras se inicia la sesión: recibe la vuelta de Spotify
/// (`/callback?code=…&state=…`), responde con una página corta y se cierra.
private final class LoginServer: @unchecked Sendable {
    private let state: String
    private let queue = DispatchQueue(label: "com.rosvjames.capri.spotify-login")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    /// El servidor ya dijo en qué puerto escucha (o que falló); su cola es serie.
    private var started = false

    init(state: String) { self.state = state }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] in self?.handle($0) }
        return try await withCheckedThrowingContinuation { (ready: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { [self] state in
                guard !started else { return }
                switch state {
                case .ready:
                    started = true
                    ready.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    started = true
                    ready.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func code(timeout: TimeInterval) async throws -> String {
        defer { queue.async { self.listener?.cancel() } }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.result { return continuation.resume(with: result) }
                self.continuation = continuation
                self.queue.asyncAfter(deadline: .now() + timeout) { self.finish(.failure(SpotifyAccount.Failure.cancelled)) }
            }
        }
    }

    private func finish(_ value: Result<String, Error>) {
        guard result == nil else { return }
        result = value
        continuation?.resume(with: value)
        continuation = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return connection.cancel() }
            // Primera línea: "GET /callback?code=…&state=… HTTP/1.1".
            let line = data.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\r\n").first ?? ""
            let parts = line.split(separator: " ")
            let items = parts.count > 1 ? URLComponents(string: String(parts[1]))?.queryItems ?? [] : []
            let value = { (name: String) in items.first { $0.name == name }?.value }
            let ok: Bool
            if parts.count > 1, parts[1].hasPrefix("/callback"), value("state") == self.state {
                if let code = value("code") {
                    ok = true
                    self.finish(.success(code))
                } else {
                    ok = false
                    self.finish(.failure(SpotifyAccount.Failure.cancelled))  // "Cancelar" en la página de Spotify
                }
            } else {
                ok = false
            }
            let text = ok ? "Listo: Capri ya puede marcar tus Me gusta. Puedes cerrar esta pestaña."
                          : "No se pudo conectar Capri con Spotify. Puedes cerrar esta pestaña."
            let body = "<!doctype html><meta charset=utf-8><title>Capri</title>"
                + "<body style=\"background:#020106;color:#fff;font:16px -apple-system;padding:40px\">\(text)</body>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
