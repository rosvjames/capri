import AppKit
import QuartzCore
import SwiftUI

/// Medidas de la vista de música del panel abierto ("Quédate un rato"), en puntos y respecto al cuerpo del
/// panel (origen arriba a la izquierda). El panel se centra en la cámara. Las fija el diseño (440 × 188, entrega
/// del 2026-11-04): lo justo para Capri recostada y un reproductor legible, sin franjas vacías.
///
/// Capri se recuesta sobre la línea que separa su espacio de la banda del reproductor. Su arte va en capas sobre
/// un lienzo común de 440 × 132 pt: detrás de la interfaz (cuerpo, melena, cara) y delante (los dedos que cuelgan
/// sobre el borde). La banda del reproductor tapa lo que el cuerpo tenga por debajo de la línea. Ninguna capa
/// recibe clics.
enum MusicLayout {
    static let width: CGFloat = 440
    static let height: CGFloat = 188
    static let topRadius: CGFloat = 6
    static let bottomRadius: CGFloat = 24
    static let margin: CGFloat = 16

    /// Línea sobre la que se apoya Capri.
    static let separatorY: CGFloat = 112
    static let separatorThickness: CGFloat = 0.5
    /// Lienzo del arte final: todas las poses comparten tamaño y anclajes (codo en (360, 112), dedos en
    /// x 300–328 / y 109–121, cara en x 290–344 / y 50–94, por debajo de la cámara).
    static let artCanvas = CGRect(x: 0, y: 0, width: 440, height: 132)

    static let cover = CGRect(x: margin, y: 122, width: 40, height: 40)
    static let coverRadius: CGFloat = 4
    static let text = CGRect(x: 66, y: 119, width: 170, height: 46)
    static let titleSize: CGFloat = 13
    static let artistSize: CGFloat = 11

    /// Me gusta, anterior, pausa, siguiente y repetir.
    static let controlCenters: [CGFloat] = [274, 308, 342, 376, 410]
    static let controlsY: CGFloat = 142
    static let mainControl: CGFloat = 34
    static let control: CGFloat = 28
    static let mainIcon: CGFloat = 16
    static let icon: CGFloat = 13

    /// Fila del progreso: tiempo, barra (zona de clic) y duración.
    static let elapsed = CGRect(x: margin, y: 169, width: 28, height: 14)
    static let bar = CGRect(x: 48, y: 169, width: 344, height: 14)
    static let duration = CGRect(x: 396, y: 169, width: 28, height: 14)
    static let barHeight: CGFloat = 3
    static let timeSize: CGFloat = 10
}

/// Botón que cuelga bajo el panel de música y abre la burbuja de Spotify.
struct BubbleToggle: View {
    @ObservedObject var model: AssistantModel
    static let size = CGSize(width: 56, height: 18)
    static let gap: CGFloat = 4

    var body: some View {
        Button { model.toggleBubble() } label: {
            Image(systemName: model.bubbleOpen ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(model.bubbleOpen ? Theme.green : .white.opacity(0.8))
                .frame(width: Self.size.width, height: Self.size.height)
                .background(Capsule().fill(Theme.panel))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(model.bubbleOpen ? "Cerrar Spotify" : "Abrir Spotify aquí")
    }
}

/// Iconos de las secciones del panel, arriba a la izquierda y lejos de la cámara. La activa va en verde y
/// subrayada.
enum SectionTabs {
    /// Pendientes y Agentes irán en x 80 y 110 cuando existan.
    static let centersX: [CGFloat] = [20, 50]
    static let centerY: CGFloat = 15
    static let hit: CGFloat = 28
    /// Subrayado de la activa: 18 × 2, arriba en y 24.
    static let underlineY: CGFloat = 24
}

struct SectionTabsView: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(PanelSection.allCases.enumerated()), id: \.offset) { i, section in
                let active = model.section == section
                Button { model.selectedSection = section } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(active ? Theme.green : .white.opacity(0.7))
                        .frame(width: SectionTabs.hit, height: SectionTabs.hit)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(Theme.green)
                                .frame(width: 18, height: 2)
                                .padding(.bottom, SectionTabs.centerY + SectionTabs.hit / 2 - SectionTabs.underlineY - 2)
                                .opacity(active ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.title)
                .offset(x: SectionTabs.centersX[i] - SectionTabs.hit / 2, y: SectionTabs.centerY - SectionTabs.hit / 2)
            }
        }
    }
}

struct MusicPanelView: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Capri detrás de la interfaz (cuerpo, melena, cara).
            MusicCapriLayer(front: false, playing: model.nowPlaying?.isPlaying == true)

            // Banda del reproductor: tapa lo que el cuerpo tenga por debajo de la línea.
            Rectangle()
                .fill(Theme.panel)
                .frame(width: MusicLayout.width, height: MusicLayout.height - MusicLayout.separatorY)
                .offset(y: MusicLayout.separatorY)
                .allowsHitTesting(false)
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(width: MusicLayout.width - 2 * MusicLayout.margin, height: MusicLayout.separatorThickness)
                .offset(x: MusicLayout.margin, y: MusicLayout.separatorY)

            if let song = model.nowPlaying {
                player(song)
            } else {
                empty
            }

            // Los dedos que cuelgan por delante del borde.
            MusicCapriLayer(front: true)
            SectionTabsView(model: model)
        }
        .frame(width: MusicLayout.width, height: MusicLayout.height, alignment: .topLeading)
    }

    private func player(_ song: NowPlaying) -> some View {
        let c = MusicLayout.cover, t = MusicLayout.text
        return ZStack(alignment: .topLeading) {
            ArtworkThumb(image: model.artwork, radius: MusicLayout.coverRadius)
                .frame(width: c.width, height: c.height)
                .offset(x: c.minX, y: c.minY)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: MusicLayout.titleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(song.artist)
                    .font(.system(size: MusicLayout.artistSize))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            .truncationMode(.tail)
            // Su alto natural: dos líneas de título y el artista miden ~46,1 pt y, ajustado a 46, SwiftUI recortaba
            // el título a una línea.
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: t.width, height: t.height, alignment: .leading)
            .offset(x: t.minX, y: t.minY)
            .help(song.artist.isEmpty ? song.title : "\(song.title) · \(song.artist)")

            controls(song)
            progress
        }
    }

    /// Me gusta, anterior, pausa/reproducir, siguiente y repetir, de izquierda a derecha.
    private func controls(_ song: NowPlaying) -> some View {
        let x = { (i: Int) in MusicLayout.controlCenters[i] }
        let liked = model.liked == true
        return ZStack(alignment: .topLeading) {
            control(liked ? "heart.fill" : "heart", help: liked ? "Quitar de Tus me gusta" : "Me gusta",
                    centerX: x(0), tint: liked ? Theme.green : nil) { model.toggleLike() }
            control("backward.end", help: "Anterior", centerX: x(1)) { model.musicCommand(.previous) }
            Button { model.musicCommand(.playPause) } label: {
                // Símbolo verde, sin contorno, como en el diseño.
                Image(systemName: song.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: MusicLayout.mainIcon, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .frame(width: MusicLayout.mainControl, height: MusicLayout.mainControl)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(song.isPlaying ? "Pausa" : "Reproducir")
            .offset(x: x(2) - MusicLayout.mainControl / 2, y: MusicLayout.controlsY - MusicLayout.mainControl / 2)
            control("forward.end", help: "Siguiente", centerX: x(3)) { model.musicCommand(.next) }
            control("repeat", help: model.repeating == true ? "Quitar la repetición" : "Repetir",
                    centerX: x(4), tint: model.repeating == true ? Theme.green : nil) { model.toggleRepeat() }
        }
    }

    private func control(_ symbol: String, help: String, centerX: CGFloat, tint: Color? = nil,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: MusicLayout.icon, weight: .semibold))
                .foregroundStyle(tint ?? .white.opacity(0.85))
                .frame(width: MusicLayout.control, height: MusicLayout.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .offset(x: centerX - MusicLayout.control / 2, y: MusicLayout.controlsY - MusicLayout.control / 2)
    }

    /// Tiempo transcurrido, barra (se puede pulsar para saltar) y duración. Sin reloj, solo la barra vacía.
    private var progress: some View {
        let e = MusicLayout.elapsed, bar = MusicLayout.bar, d = MusicLayout.duration
        let clock = model.clock
        return ZStack(alignment: .topLeading) {
            ElapsedLabel(clock: clock)
                .frame(width: e.width, height: e.height, alignment: .leading)
                .offset(x: e.minX, y: e.minY)
            ProgressBar(clock: clock, seek: { model.seek($0) })
                .frame(width: bar.width, height: bar.height)
                .offset(x: bar.minX, y: bar.minY)
            Text(clock.map { formatTime($0.duration) } ?? "")
                .font(.system(size: MusicLayout.timeSize).monospacedDigit())
                .foregroundStyle(Theme.dim)
                .frame(width: d.width, height: d.height, alignment: .trailing)
                .offset(x: d.minX, y: d.minY)
        }
    }

    private var empty: some View {
        HStack(spacing: 14) {
            Text("Nada sonando en Spotify")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)
            Button("Abrir Spotify") {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicWatcher.spotifyID) else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.green)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .overlay(Capsule().strokeBorder(Theme.green, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .frame(width: MusicLayout.width, height: MusicLayout.height - MusicLayout.separatorY)
        .offset(y: MusicLayout.separatorY)
    }
}

func formatTime(_ seconds: TimeInterval) -> String {
    let s = Int(max(0, seconds))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Tiempo transcurrido. Mientras suena se redibuja solo esta etiqueta, una vez por segundo y justo al cambiar
/// el segundo; en pausa no se redibuja.
private struct ElapsedLabel: View {
    let clock: PlaybackClock?

    var body: some View {
        if let clock, clock.playing {
            // Primer cambio de segundo después de la lectura.
            let start = clock.at.addingTimeInterval(1 - clock.position.truncatingRemainder(dividingBy: 1))
            TimelineView(.periodic(from: start, by: 1)) { ctx in label(clock.position(at: ctx.date)) }
        } else {
            label(clock?.position ?? 0).opacity(clock == nil ? 0 : 1)
        }
    }

    private func label(_ t: TimeInterval) -> some View {
        Text(formatTime(t))
            .font(.system(size: MusicLayout.timeSize).monospacedDigit())
            .foregroundStyle(Theme.dim)
    }
}

/// Barra de progreso. Avanza con Core Animation en el servidor de ventanas (como las barras del notch): la app
/// no dibuja nada mientras la canción suena. Pulsarla salta a ese punto.
private struct ProgressBar: View {
    let clock: PlaybackClock?
    let seek: (TimeInterval) -> Void
    @Environment(\.snapshotRendering) private var snapshot

    var body: some View {
        // `ImageRenderer` no dibuja vistas de AppKit: en las capturas, la misma barra quieta en SwiftUI.
        if snapshot {
            Canvas { g, size in
                let h = MusicLayout.barHeight, y = size.height / 2
                let x = clock.map { size.width * $0.position / $0.duration } ?? 0
                g.fill(Path(roundedRect: CGRect(x: 0, y: y - h / 2, width: size.width, height: h), cornerRadius: h / 2),
                       with: .color(.white.opacity(0.2)))
                g.fill(Path(roundedRect: CGRect(x: 0, y: y - h / 2, width: x, height: h), cornerRadius: h / 2), with: .color(Theme.green))
                if clock != nil { g.fill(Path(ellipseIn: CGRect(x: x - 4.5, y: y - 4.5, width: 9, height: 9)), with: .color(Theme.green)) }
            }
        } else {
            ProgressBarLayer(clock: clock, seek: seek)
        }
    }
}

private struct ProgressBarLayer: NSViewRepresentable {
    let clock: PlaybackClock?
    let seek: (TimeInterval) -> Void

    func makeNSView(context: Context) -> ProgressBarView { ProgressBarView() }

    func updateNSView(_ view: ProgressBarView, context: Context) {
        view.onSeek = { fraction in
            guard let clock else { return }
            seek(fraction * clock.duration)
        }
        view.show(clock)
    }
}

final class ProgressBarView: NSView {
    var onSeek: (Double) -> Void = { _ in }
    private let track = CALayer()
    private let fill = CALayer()
    private let knob = CALayer()
    private var shown: PlaybackClock?
    private static let knobSize: CGFloat = 9

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        track.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        fill.backgroundColor = NSColor(Theme.green).cgColor
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        knob.backgroundColor = NSColor(Theme.green).cgColor
        knob.cornerRadius = Self.knobSize / 2
        for l in [track, fill, knob] {
            l.actions = ["bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(l)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let clock = shown
        shown = nil
        show(clock)
    }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        guard bounds.width > 0 else { return }
        onSeek(Double(min(max(x / bounds.width, 0), 1)))
    }

    func show(_ clock: PlaybackClock?) {
        guard clock != shown else { return }
        shown = clock
        let h = MusicLayout.barHeight, w = bounds.width, midY = bounds.midY
        track.frame = CGRect(x: 0, y: midY - h / 2, width: w, height: h)
        track.cornerRadius = h / 2
        fill.cornerRadius = h / 2
        for l in [fill, knob] { l.removeAllAnimations() }
        knob.isHidden = clock == nil
        knob.bounds = CGRect(x: 0, y: 0, width: Self.knobSize, height: Self.knobSize)
        guard let clock, clock.duration > 0, w > 0 else {
            fill.bounds = CGRect(x: 0, y: 0, width: 0, height: h)
            fill.position = CGPoint(x: 0, y: midY)
            return
        }
        let now = Date()
        let from = w * clock.position(at: now) / clock.duration
        fill.position = CGPoint(x: 0, y: midY)
        fill.bounds = CGRect(x: 0, y: 0, width: from, height: h)
        knob.position = CGPoint(x: from, y: midY)
        let remaining = clock.duration - clock.position(at: now)
        guard clock.playing, remaining > 0 else { return }
        // Hasta el final de la canción a velocidad constante; el siguiente aviso de Spotify la corrige.
        let width = CABasicAnimation(keyPath: "bounds.size.width")
        width.fromValue = from
        width.toValue = w
        let x = CABasicAnimation(keyPath: "position.x")
        x.fromValue = from
        x.toValue = w
        for a in [width, x] {
            a.duration = remaining
            a.timingFunction = CAMediaTimingFunction(name: .linear)
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
        }
        fill.add(width, forKey: "progreso")
        knob.add(x, forKey: "progreso")
    }
}
