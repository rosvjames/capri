import AppKit
import SwiftUI

/// Columna de música del panel abierto (C-29): carátula, canción, artista y controles de Spotify.
///
/// Va a la izquierda de la columna de Capri y ensancha el panel hacia ese lado, así que Capri y sus
/// fotogramas no se mueven. Medidas en píxeles de la maqueta v3, escaladas como el resto del panel.
enum MusicColumn {
    static let width: CGFloat = 330
    fileprivate static let left: CGFloat = 32
    fileprivate static let artwork: CGFloat = 66  // deja aire sobre los controles
    fileprivate static let top: CGFloat = 62      // a la altura de "CAPRI"
    fileprivate static let controlsY: CGFloat = 142  // fila del botón Hablar
    fileprivate static let controlsH: CGFloat = 52
}

struct MusicColumnView: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        let s = model.geometry.s
        let textX = MusicColumn.left + MusicColumn.artwork + 12
        ZStack(alignment: .topLeading) {
            if let song = model.nowPlaying {
                ArtworkThumb(image: model.artwork)
                    .frame(width: MusicColumn.artwork * s, height: MusicColumn.artwork * s)
                    .offset(x: MusicColumn.left * s, y: MusicColumn.top * s)

                VStack(alignment: .leading, spacing: 3 * s) {
                    Text(song.title)
                        .font(.system(size: 23.33 * s, weight: .semibold))  // como el mensaje de Capri
                        .foregroundStyle(.white)
                    Text(song.artist)
                        .font(.system(size: 19.75 * s, weight: .regular))
                        .foregroundStyle(Theme.dim)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: (MusicColumn.width - textX - 16) * s, alignment: .leading)
                .offset(x: textX * s, y: (MusicColumn.top - 4) * s)

                controls(playing: song.isPlaying, s: s)
                    .offset(x: MusicColumn.left * s, y: MusicColumn.controlsY * s)
            }
        }
        .frame(width: MusicColumn.width * s, height: model.geometry.height, alignment: .topLeading)
    }

    private func controls(playing: Bool, s: CGFloat) -> some View {
        let green = Theme.green
        let h = MusicColumn.controlsH * s
        return HStack(spacing: 22 * s) {
            control("backward.fill", help: "Anterior", size: 25 * s) { model.musicCommand(.previous) }
            // Pausa/reproducir con el mismo contorno verde que el botón Hablar.
            Button { model.musicCommand(.playPause) } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 25 * s, weight: .medium))
                    .foregroundStyle(green)
                    .frame(width: h, height: h)
                    .overlay(Circle().strokeBorder(green, lineWidth: 3 * s))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(playing ? "Pausa" : "Reproducir")
            control("forward.fill", help: "Siguiente", size: 25 * s) { model.musicCommand(.next) }
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
