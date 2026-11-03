import AppKit
import ImageIO
import os
import UniformTypeIdentifiers

/// Carátulas de Spotify (C-29): cada una se descarga una vez, se reduce al tamaño que usa el notch
/// y se guarda por canción en la caché del usuario, así una canción repetida no vuelve a pedirse.
final class ArtworkCache {
    /// Lado máximo en píxeles: el panel la muestra a ~56 pt en pantallas Retina.
    static let maxPixels = 160
    private static let keep = 500

    private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.rosvjames.capri/caratulas", isDirectory: true)
    private let queue = DispatchQueue(label: "com.rosvjames.capri.caratulas", qos: .utility)
    private let log = Logger(subsystem: "com.rosvjames.capri", category: "musica")

    /// La carátula guardada de esa canción, o nil. `done` llega en el hilo principal.
    func cached(_ trackID: String, _ done: @escaping (NSImage?) -> Void) {
        let file = self.file(for: trackID)
        queue.async {
            let image = NSImage(contentsOf: file)
            DispatchQueue.main.async { done(image) }
        }
    }

    /// Descarga, reduce y guarda la carátula. `done` llega en el hilo principal.
    func download(_ url: URL, for trackID: String, _ done: @escaping (NSImage?) -> Void) {
        let file = self.file(for: trackID)
        URLSession.shared.dataTask(with: url) { [self] data, response, error in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            guard ok, let data, let small = Self.downsample(data) else {
                log.error("carátula no descargada: \(error?.localizedDescription ?? "respuesta inválida", privacy: .public)")
                return DispatchQueue.main.async { done(nil) }
            }
            queue.async { [self] in
                save(small, to: file)
                DispatchQueue.main.async { done(NSImage(cgImage: small, size: .zero)) }
            }
        }.resume()
    }

    private func file(for trackID: String) -> URL {
        // "spotify:track:ID" → "ID.jpg"; los dos puntos no van en un nombre de archivo.
        folder.appendingPathComponent(trackID.split(separator: ":").last.map(String.init) ?? trackID)
            .appendingPathExtension("jpg")
    }

    private static func downsample(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary)
    }

    private func save(_ image: CGImage, to file: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        prune()
    }

    /// Conserva solo las `keep` más recientes (unos 5 MB).
    private func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys),
              files.count > Self.keep else { return }
        let byAge = files.sorted {
            let a = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return a < b
        }
        byAge.prefix(files.count - Self.keep).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
