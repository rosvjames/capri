import AppKit
import QuartzCore
import SwiftUI

/// Medidas de la vista de música del panel abierto ("Quédate un rato"), en puntos y respecto al cuerpo del
/// panel (origen arriba a la izquierda). El panel se centra en la cámara.
///
/// Capri se recuesta sobre la línea que separa su espacio de la banda del reproductor. Su arte va en dos capas:
/// detrás de la interfaz (cuerpo y pelo) y delante (lo que se apoya por encima de la línea, como los dedos).
/// Ninguna de las dos recibe clics.
enum MusicLayout {
    static let width: CGFloat = 680
    static let height: CGFloat = 260
    static let margin: CGFloat = 24

    /// Línea sobre la que se apoya Capri.
    static let separatorY: CGFloat = 160
    /// Hueco del arte: termina en la línea, a la derecha; el lado izquierdo queda para los iconos.
    static let art = CGRect(x: 192, y: 4, width: 468, height: 156)

    static let cover = CGRect(x: margin, y: 172, width: 56, height: 56)
    static let textX: CGFloat = 92
    static let titleSize: CGFloat = 15
    static let artistSize: CGFloat = 12

    /// Controles a la derecha de la banda, centrados en la carátula.
    static let controlsY: CGFloat = 200
    static let controlsRight: CGFloat = width - margin - 16
    static let controlSpacing: CGFloat = 46
    static let mainControl: CGFloat = 40
    static let control: CGFloat = 32

    /// Fila del progreso: tiempo, barra y duración.
    static let progressY: CGFloat = 244
    static let timeWidth: CGFloat = 36
    static let barHeight: CGFloat = 3
}

/// Iconos de las secciones del panel, arriba a la izquierda y lejos de la cámara. La activa va en verde y
/// subrayada.
enum SectionTabs {
    static let centersX: [CGFloat] = [26, 62]
    static let centerY: CGFloat = 16
    static let hit: CGFloat = 32
}

struct SectionTabsView: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(PanelSection.allCases.enumerated()), id: \.offset) { i, section in
                let active = model.section == section
                Button { model.selectedSection = section } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(active ? Theme.green : .white.opacity(0.7))
                        .frame(width: SectionTabs.hit, height: SectionTabs.hit)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(Theme.green)
                                .frame(width: 18, height: 2)
                                .padding(.bottom, 5)
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

/// Arte de Capri para la vista de música. Si no está en los recursos, el hueco queda vacío.
enum MusicArt {
    static let back = load("capri-musica-fondo") ?? load("capri-musica-provisional")
    static let front = load("capri-musica-frente")

    private static func load(_ name: String) -> NSImage? {
        Bundle.module.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }
}

struct MusicPanelView: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            art(MusicArt.back)

            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(width: MusicLayout.width - 2 * MusicLayout.margin, height: 1)
                .offset(x: MusicLayout.margin, y: MusicLayout.separatorY)

            if let song = model.nowPlaying {
                player(song)
            } else {
                empty
            }

            art(MusicArt.front)
            SectionTabsView(model: model)
        }
        .frame(width: MusicLayout.width, height: MusicLayout.height, alignment: .topLeading)
    }

    /// Capa de arte, apoyada en la línea y alineada a la derecha de su hueco.
    @ViewBuilder
    private func art(_ image: NSImage?) -> some View {
        if let image {
            let r = MusicLayout.art
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: r.width, height: r.height, alignment: .bottomTrailing)
                .offset(x: r.minX, y: r.minY)
                .allowsHitTesting(false)
        }
    }

    private func player(_ song: NowPlaying) -> some View {
        let c = MusicLayout.cover
        let controlsLeft = MusicLayout.controlsRight - 3 * MusicLayout.controlSpacing - MusicLayout.mainControl / 2
        return ZStack(alignment: .topLeading) {
            ArtworkThumb(image: model.artwork)
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
            .frame(width: controlsLeft - 16 - MusicLayout.textX, height: c.height, alignment: .leading)
            .offset(x: MusicLayout.textX, y: c.minY)

            controls(song)
            progress
        }
    }

    /// Anterior, pausa/reproducir, siguiente y repetir, de izquierda a derecha.
    private func controls(_ song: NowPlaying) -> some View {
        let x = { (i: Int) in MusicLayout.controlsRight - CGFloat(3 - i) * MusicLayout.controlSpacing }
        return ZStack(alignment: .topLeading) {
            control("backward.end.fill", help: "Anterior", centerX: x(0)) { model.musicCommand(.previous) }
            Button { model.musicCommand(.playPause) } label: {
                Image(systemName: song.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .frame(width: MusicLayout.mainControl, height: MusicLayout.mainControl)
                    .overlay(Circle().strokeBorder(Theme.green, lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(song.isPlaying ? "Pausa" : "Reproducir")
            .offset(x: x(1) - MusicLayout.mainControl / 2, y: MusicLayout.controlsY - MusicLayout.mainControl / 2)
            control("forward.end.fill", help: "Siguiente", centerX: x(2)) { model.musicCommand(.next) }
            control("repeat", help: model.repeating == true ? "Quitar la repetición" : "Repetir",
                    centerX: x(3), tint: model.repeating == true ? Theme.green : nil) { model.toggleRepeat() }
        }
    }

    private func control(_ symbol: String, help: String, centerX: CGFloat, tint: Color? = nil,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
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
        let y = MusicLayout.progressY
        let barX = MusicLayout.margin + MusicLayout.timeWidth + 4
        let barWidth = MusicLayout.width - 2 * barX
        let clock = model.clock
        return ZStack(alignment: .topLeading) {
            ElapsedLabel(clock: clock)
                .frame(width: MusicLayout.timeWidth, height: 14, alignment: .leading)
                .offset(x: MusicLayout.margin, y: y - 7)
            ProgressBar(clock: clock, seek: { model.seek($0) })
                .frame(width: barWidth, height: 14)
                .offset(x: barX, y: y - 7)
            Text(clock.map { formatTime($0.duration) } ?? "")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.dim)
                .frame(width: MusicLayout.timeWidth, height: 14, alignment: .trailing)
                .offset(x: MusicLayout.width - MusicLayout.margin - MusicLayout.timeWidth, y: y - 7)
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
            .font(.system(size: 11).monospacedDigit())
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
