import AppKit
import SwiftUI

// Renderizado a PNG sin permisos de grabación de pantalla, para verificar la interfaz:
//   Capri --snapshot ruta.png [modo] [colapsado] [sinpermisos] [musica] [t=ms]
//       panel del notch en un modo (expandido por defecto), con las métricas del notch real;
//       t=ms muestra el loop de Capri a esos milisegundos de haberse abierto;
//       musica simula una canción sonando con una carátula sintética (no usa la de Spotify)
//   Capri --gallery ruta.png                       las 9 expresiones de A-002 en cuadrícula 3×3
//   Capri --icon ruta.png                          icono de la barra de menús a 18, 36 y 144 px, en barra clara y oscura
//   Capri --timing-check                           imprime los cambios de dibujo que programa el reproductor (2 loops)

@MainActor
func writeSnapshot(to path: String, mode: AssistantMode, expanded: Bool = true, elapsedMs: Double = 0, withoutPermissions: Bool = false,
                   music: Bool = false) {
    let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    let model = AssistantModel(metrics: screen.map(NotchMetrics.of) ?? NotchMetrics(width: 185, height: 32))
    _ = NotchFrames.shared  // decodificar antes de fijar la hora, para que el instante capturado sea el pedido
    model.expanded = expanded
    model.mode = mode
    model.permissions.overrideForPreview(Dictionary(uniqueKeysWithValues: Permission.allCases.map {
        ($0, withoutPermissions ? PermissionState.notDetermined : .granted)
    }))
    model.expandedAt = Date().addingTimeInterval(-elapsedMs / 1000)
    if music {
        model.nowPlaying = NowPlaying(trackID: "spotify:track:prueba", title: "Canción de prueba", artist: "Artista de prueba",
                                      album: "Álbum", isPlaying: true)
        model.artwork = syntheticArtwork()
    }
    let size = model.windowSize
    let view = NotchView(model: model)
        .frame(width: size.width, height: size.height)
        .background(Color(white: 0.18))
        .environment(\.snapshotRendering, true)
    writePNG(view, to: path)
}

/// Carátula de prueba: degradado con la paleta de Capri, del tamaño que guarda `ArtworkCache`.
private func syntheticArtwork() -> NSImage {
    let side = CGFloat(ArtworkCache.maxPixels)
    return NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
        NSGradient(colors: [NSColor(Theme.violet), NSColor(Theme.red), NSColor(Theme.green)])?.draw(in: r, angle: 45)
        return true
    }
}

@MainActor
func writeGallery(to path: String) {
    let all = CapriExpression.allCases
    let view = VStack(spacing: 0) {
        ForEach(0..<3, id: \.self) { r in
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { c in
                    CapriFaceView(face: all[r * 3 + c].face)
                        .frame(width: 300, height: 300)
                }
            }
        }
    }
    .background(Color(white: 0.46))
    writePNG(view, to: path)
}

@MainActor
private func writePNG(_ view: some View, to path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { print("snapshot failed"); return }
    try? png.write(to: URL(fileURLWithPath: path))
}

/// Recorre el calendario real del reproductor (el mismo que usa TimelineView) durante dos loops.
func printExposureSchedule() {
    let frames = NotchFrames.shared
    let origin = Date(timeIntervalSinceReferenceDate: 0)
    // Reloj simulado que avanza a cada entrada, como si cada actualización ocurriera a su hora.
    var clock = origin
    let schedule = ExposureSchedule(origin: origin, frames: frames, now: { clock })
    let entries = schedule.entries(from: origin, mode: .normal)
    for _ in 0..<(frames.exposures.count * 2) {
        guard let date = entries.next() else { break }
        clock = date
        let t = date.timeIntervalSince(origin)
        print(String(format: "%.0f", t * 1000), frames.exposures[frames.index(at: t)].frame)
    }
}

/// Vista previa del icono como lo pinta macOS: negro en barra clara y blanco en barra oscura.
func writeIconPreview(to path: String) {
    let sizes: [CGFloat] = [18, 36, 144]
    let pad: CGFloat = 12
    let width = sizes.reduce(pad) { $0 + $1 + pad }
    let height = (sizes.max() ?? 0) + 2 * pad
    let canvas = NSImage(size: NSSize(width: width, height: height * 2), flipped: false) { _ in
        for (row, (bar, ink)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black), (NSColor(white: 0.16, alpha: 1), NSColor.white)].enumerated() {
            let y = CGFloat(1 - row) * height
            bar.setFill()
            NSRect(x: 0, y: y, width: width, height: height).fill()
            var x = pad
            for s in sizes {
                let icon = MenuBarIcon.make(size: s)
                let tinted = NSImage(size: icon.size, flipped: false) { r in
                    icon.draw(in: r)
                    ink.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: x, y: y + (height - s) / 2, width: s, height: s))
                x += s + pad
            }
        }
        return true
    }
    guard let tiff = canvas.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { print("icon preview failed"); return }
    try? png.write(to: URL(fileURLWithPath: path))
}
