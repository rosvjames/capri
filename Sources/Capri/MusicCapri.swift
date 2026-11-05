import AppKit
import QuartzCore
import SwiftUI

// Capri recostada en la vista de música, en dos capas sobre el lienzo común (440 × 132 pt) y con sus gestos.
//
// Detrás de la interfaz va el cuerpo (reposo, parpadeo o mirada); delante del borde, los dedos (reposo, índice o
// medio). Los gestos cambian la imagen de una capa a saltos, con los tiempos del diseño, y solo se programan por
// eventos: un temporizador por gesto, nunca uno por cuadro. Con el panel cerrado no queda ninguno.

enum MusicBackPose: CaseIterable { case rest, blink, gaze }
enum MusicFrontPose: CaseIterable { case rest, index, middle }

/// Los seis dibujos, decodificados una sola vez.
enum MusicCapriArt {
    static let back: [MusicBackPose: CGImage] = [
        .rest: load("capri-musica-fondo"), .blink: load("capri-musica-fondo-parpadeo"), .gaze: load("capri-musica-fondo-mirada"),
    ].compactMapValues { $0 }
    static let front: [MusicFrontPose: CGImage] = [
        .rest: load("capri-musica-frente"), .index: load("capri-musica-frente-indice"), .middle: load("capri-musica-frente-medio"),
    ].compactMapValues { $0 }

    static var available: Bool { back[.rest] != nil }

    private static func load(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// Decide qué dibujo se ve en cada capa. Gestos (del diseño, 2026-11-04):
/// - Al abrir el panel, terminada la apertura: parpadeo 80 ms → mirada lateral 1 s → parpadeo 80 ms → reposo.
///   Una vez por apertura y con 3,5 s de descanso entre una y otra.
/// - Parpadeo suelto cada 4–8 s, nunca justo antes o después de la mirada.
/// - Mientras suena, tamborileo cada 6–12 s: índice, medio, reposo, índice, medio, reposo (120 ms cada uno).
///   En pausa, quieta.
/// Un gesto a la vez: la mirada y el parpadeo esperan a que acabe el tamborileo, y al revés.
@MainActor
final class MusicCapriDirector {
    static let shared = MusicCapriDirector()

    private var backLayers: [ObjectIdentifier: CALayer] = [:]
    private var frontLayers: [ObjectIdentifier: CALayer] = [:]
    private(set) var back: MusicBackPose = .rest
    private(set) var front: MusicFrontPose = .rest
    private var visible = false
    private var playing = false
    /// Gesto en curso: sus pasos pendientes se cancelan juntos.
    private var gesture: [DispatchWorkItem] = []
    private var blinkWork: DispatchWorkItem?
    private var tapWork: DispatchWorkItem?
    private var lastGaze = Date.distantPast
    private var lastGestureEnd = Date.distantPast

    static let openingDelay: TimeInterval = 0.5
    static let gazeCooldown: TimeInterval = 3.5

    // MARK: Capas

    func attach(_ layer: CALayer, front isFront: Bool) {
        let id = ObjectIdentifier(layer)
        if isFront { frontLayers[id] = layer } else { backLayers[id] = layer }
        show(layer, isFront: isFront)
        updateVisibility()
    }

    func detach(_ layer: CALayer) {
        let id = ObjectIdentifier(layer)
        backLayers[id] = nil
        frontLayers[id] = nil
        updateVisibility()
    }

    private func show(_ layer: CALayer, isFront: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = isFront ? MusicCapriArt.front[front] : MusicCapriArt.back[back]
        CATransaction.commit()
    }

    private func set(back pose: MusicBackPose) {
        guard pose != back else { return }
        back = pose
        backLayers.values.forEach { show($0, isFront: false) }
    }

    private func set(front pose: MusicFrontPose) {
        guard pose != front else { return }
        front = pose
        frontLayers.values.forEach { show($0, isFront: true) }
    }

    // MARK: Estado

    /// La vista de música está en pantalla si alguna de sus capas está en una ventana.
    private func updateVisibility() {
        let now = !backLayers.isEmpty
        guard now != visible else { return }
        visible = now
        if visible { opened() } else { closed() }
    }

    func setPlaying(_ value: Bool) {
        guard value != playing else { return }
        playing = value
        if playing { scheduleTap() } else {
            tapWork?.cancel()
            // En pausa, quieta: si estaba tamborileando, vuelve a reposo.
            if front != .rest { cancelGesture() }
        }
    }

    private func opened() {
        let wait = max(Self.openingDelay, Self.gazeCooldown - Date().timeIntervalSince(lastGaze))
        run([(.back(.blink), 0.08), (.back(.gaze), 1.0), (.back(.blink), 0.08), (.back(.rest), 0)], after: wait) { [weak self] in
            self?.lastGaze = Date()
        }
        scheduleBlink()
        if playing { scheduleTap() }
    }

    private func closed() {
        cancelGesture()
        blinkWork?.cancel()
        tapWork?.cancel()
        blinkWork = nil
        tapWork = nil
    }

    // MARK: Gestos

    private enum Step { case back(MusicBackPose), front(MusicFrontPose) }

    /// Pasos con la duración de cada dibujo; el último deja el reposo. Si hay otro gesto en curso, este espera.
    private func run(_ steps: [(Step, TimeInterval)], after delay: TimeInterval, started: (() -> Void)? = nil) {
        let start = DispatchWorkItem { [weak self] in
            guard let self, self.visible else { return }
            guard self.gesture.isEmpty else {
                // Otro gesto en curso: se intenta al terminar.
                return self.run(steps, after: 0.8, started: started)
            }
            started?()
            var t: TimeInterval = 0
            for (i, (step, duration)) in steps.enumerated() {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    switch step {
                    case .back(let pose): self.set(back: pose)
                    case .front(let pose): self.set(front: pose)
                    }
                    if i == steps.count - 1 {
                        self.gesture = []
                        self.lastGestureEnd = Date()
                    }
                }
                gesture.append(work)
                DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: work)
                t += duration
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: start)
        gestureStarts.append(start)
    }

    /// Inicios programados que aún no empezaron (para cancelarlos al cerrar).
    private var gestureStarts: [DispatchWorkItem] = []

    private func cancelGesture() {
        (gesture + gestureStarts).forEach { $0.cancel() }
        gesture = []
        gestureStarts = []
        set(back: .rest)
        set(front: .rest)
    }

    private func scheduleBlink() {
        blinkWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.visible else { return }
            // Ni durante ni justo después de otro gesto (la mirada ya parpadea).
            if self.gesture.isEmpty, Date().timeIntervalSince(self.lastGestureEnd) > 1.5 {
                self.run([(.back(.blink), 0.08), (.back(.rest), 0)], after: 0)
            }
            self.scheduleBlink()
        }
        blinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 4...8), execute: work)
    }

    private func scheduleTap() {
        tapWork?.cancel()
        guard visible, playing else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.visible, self.playing else { return }
            let beat: TimeInterval = 0.12
            self.run([(.front(.index), beat), (.front(.middle), beat), (.front(.rest), beat),
                      (.front(.index), beat), (.front(.middle), beat), (.front(.rest), 0)], after: 0)
            self.scheduleTap()
        }
        tapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 6...12), execute: work)
    }
}

/// Una capa de Capri en la vista de música. En las capturas (`ImageRenderer` no dibuja AppKit), una imagen fija.
struct MusicCapriLayer: View {
    let front: Bool
    var playing = false
    @Environment(\.snapshotRendering) private var snapshot

    var body: some View {
        let r = MusicLayout.artCanvas
        Group {
            if snapshot {
                if let image = front ? MusicCapriArt.front[MusicCapriSnapshot.front] : MusicCapriArt.back[MusicCapriSnapshot.back] {
                    Image(decorative: image, scale: 2).resizable().interpolation(.high)
                }
            } else {
                MusicCapriLayerView(front: front, playing: playing)
            }
        }
        .frame(width: r.width, height: r.height)
        .offset(x: r.minX, y: r.minY)
        .allowsHitTesting(false)
    }
}

/// Pose de las capturas (`--snapshot … musica pose=mirada|parpadeo|indice|medio`).
enum MusicCapriSnapshot {
    nonisolated(unsafe) static var back: MusicBackPose = .rest
    nonisolated(unsafe) static var front: MusicFrontPose = .rest
}

private struct MusicCapriLayerView: NSViewRepresentable {
    let front: Bool
    let playing: Bool

    func makeNSView(context: Context) -> MusicCapriNSView { MusicCapriNSView(front: front) }

    func updateNSView(_ view: MusicCapriNSView, context: Context) {
        if !front { MusicCapriDirector.shared.setPlaying(playing) }
    }

    static func dismantleNSView(_ view: MusicCapriNSView, coordinator: ()) {
        view.detach()
    }
}

final class MusicCapriNSView: NSView {
    private let front: Bool
    private let art = CALayer()

    init(front: Bool) {
        self.front = front
        super.init(frame: .zero)
        wantsLayer = true
        art.contentsGravity = .resize
        art.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(art)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Los clics pasan a la interfaz de debajo.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        art.frame = bounds
        art.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { MusicCapriDirector.shared.attach(art, front: front) } else { detach() }
    }

    func detach() { MusicCapriDirector.shared.detach(art) }
}
