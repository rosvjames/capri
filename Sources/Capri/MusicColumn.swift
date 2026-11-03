import AppKit
import SwiftUI

/// Columna de música del panel abierto (C-29): carátula, canción, artista y controles de Spotify.
///
/// Ocupa justo el sitio de la interfaz de Capri (CAPRI, mensaje, Hablar), que con música no aporta nada:
/// el panel no cambia de tamaño, sigue centrado, y Capri y sus fotogramas no se mueven.
/// Medidas en píxeles de la maqueta v3, escaladas como el resto del panel.
enum MusicColumn {
    fileprivate static let left: CGFloat = 32      // donde empieza "CAPRI"
    fileprivate static let right: CGFloat = 190    // poco después del borde del botón Hablar
    fileprivate static let artwork: CGFloat = 40
    fileprivate static let top: CGFloat = 60       // a la altura de "CAPRI"
    fileprivate static let controlsY: CGFloat = 142  // fila del botón Hablar
    fileprivate static let controlsH: CGFloat = 52
}

struct MusicColumnView: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.geometry.s
        let textX = MusicColumn.left + MusicColumn.artwork + 10
        ZStack(alignment: .topLeading) {
            if let song = model.nowPlaying {
                ArtworkThumb(image: model.artwork)
                    .frame(width: MusicColumn.artwork * s, height: MusicColumn.artwork * s)
                    .offset(x: MusicColumn.left * s, y: MusicColumn.top * s)

                // El título puede ocupar dos líneas: el hueco hasta los controles lo permite.
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(song.title)
                        .font(.system(size: 21 * s, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(song.artist)
                        .font(.system(size: 18 * s, weight: .regular))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                .truncationMode(.tail)
                .frame(width: (MusicColumn.right - textX) * s, alignment: .topLeading)
                .offset(x: textX * s, y: MusicColumn.top * s)

                controls(playing: song.isPlaying, s: s)
                    .frame(width: (MusicColumn.right - MusicColumn.left) * s)
                    .offset(x: MusicColumn.left * s, y: MusicColumn.controlsY * s)
            }
        }
        .frame(width: model.geometry.bodyWidth, height: model.geometry.height, alignment: .topLeading)
    }

    private func controls(playing: Bool, s: CGFloat) -> some View {
        let green = Theme.green
        let h = MusicColumn.controlsH * s
        return HStack(spacing: 0) {
            control("backward.fill", help: "Anterior", size: 22 * s) { model.musicCommand(.previous) }
            Spacer(minLength: 0)
            // Pausa/reproducir con el mismo contorno verde que el botón Hablar.
            Button { model.musicCommand(.playPause) } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 24 * s, weight: .medium))
                    .foregroundStyle(green)
                    .frame(width: h, height: h)
                    .overlay(Circle().strokeBorder(green, lineWidth: 3 * s))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(playing ? "Pausa" : "Reproducir")
            Spacer(minLength: 0)
            control("forward.fill", help: "Siguiente", size: 22 * s) { model.musicCommand(.next) }
        }
        .frame(height: h)
    }

    private func control(_ symbol: String, help: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: size * 1.6, height: size * 1.6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
