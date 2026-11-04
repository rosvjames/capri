import Foundation
import os

/// Qué se busca en Spotify: "pon la canción X", "pon música de X", "pon el disco X".
enum MusicKind: String, Equatable {
    case track, artist, album
}

/// La API web de Spotify, solo para buscar (C-09): encuentra lo que James pidió y devuelve su URI, que luego
/// reproduce la app de Spotify por AppleScript (`SpotifyRemote.play`).
///
/// Usa el flujo de credenciales de cliente: James no inicia sesión en Capri, solo crea una app de desarrollador
/// y guarda su Client ID y su Client secret en el Llavero (cuentas `spotify-id` y `spotify-secret`). Desde
/// febrero de 2026 Spotify exige que el dueño de esa app tenga Premium; sin Premium la API responde 403.
/// Sin credenciales o si algo falla, Capri abre la búsqueda en la app, como antes.
final class SpotifyWeb {
    struct Result {
        let uri: String
        /// Para la confirmación: "Tusa, de Karol G".
        let spoken: String
    }

    enum Failure: Error {
        case noCredentials, premiumRequired, notFound, failed
    }

    private var token: String?
    private var tokenExpires = Date.distantPast
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "musica")

    static var hasCredentials: Bool {
        APIKeys.exists(account: "spotify-id", variable: "SPOTIFY_CLIENT_ID")
            && APIKeys.exists(account: "spotify-secret", variable: "SPOTIFY_CLIENT_SECRET")
    }

    /// Busca y devuelve el primer resultado. `done` llega en el hilo principal.
    func search(_ query: String, kind: MusicKind, _ done: @escaping (Swift.Result<Result, Failure>) -> Void) {
        Task { [self] in
            let result: Swift.Result<Result, Failure>
            do {
                result = .success(try await find(query, kind: kind))
            } catch let failure as Failure {
                result = .failure(failure)
            } catch {
                log.error("búsqueda en Spotify: \(error.localizedDescription, privacy: .public)")
                result = .failure(.failed)
            }
            await MainActor.run { done(result) }
        }
    }

    private func find(_ query: String, kind: MusicKind) async throws -> Result {
        let token = try await accessToken()
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: kind.rawValue),
            URLQueryItem(name: "limit", value: "1"),
            // Sin sesión de usuario hay que decir el país, para que el resultado se pueda escuchar aquí.
            URLQueryItem(name: "market", value: Locale.current.region?.identifier ?? "US"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let item = ((json?[kind.rawValue + "s"] as? [String: Any])?["items"] as? [[String: Any]])?.first,
              let uri = item["uri"] as? String, uri.hasPrefix("spotify:"), let name = item["name"] as? String
        else { throw Failure.notFound }
        let artist = (item["artists"] as? [[String: Any]])?.first?["name"] as? String
        return Result(uri: uri, spoken: kind == .artist || artist == nil ? name : "\(name), de \(artist!)")
    }

    /// Token de una hora, pedido con el Client ID y el secret y guardado hasta que caduca.
    private func accessToken() async throws -> String {
        if let token, Date() < tokenExpires { return token }
        guard let id = APIKeys.read(account: "spotify-id", variable: "SPOTIFY_CLIENT_ID"),
              let secret = APIKeys.read(account: "spotify-secret", variable: "SPOTIFY_CLIENT_SECRET")
        else { throw Failure.noCredentials }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("Basic " + Data("\(id):\(secret)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=client_credentials".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let value = json?["access_token"] as? String else { throw Failure.failed }
        let seconds = json?["expires_in"] as? Double ?? 3600
        token = value
        tokenExpires = Date().addingTimeInterval(seconds - 60)
        return value
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, status != 200 else { return }
        let body = String(decoding: data.prefix(300), as: UTF8.self)
        log.error("API de Spotify \(status): \(body, privacy: .public)")
        switch status {
        case 400, 401: token = nil; throw Failure.noCredentials  // credenciales mal copiadas o revocadas
        case 403: throw Failure.premiumRequired
        default: throw Failure.failed
        }
    }
}
