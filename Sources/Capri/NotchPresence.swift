import AppKit
import ImageIO
import SwiftUI

// Panel expandido según el prototipo aprobado v3 (art/final/notch-fiel-v3/): Capri en fotogramas
// completos, reproducidos con los dibujos y duraciones de timing.json, y la interfaz como UI nativa.
// La geometría sale de la maqueta (layout.json, en px) escalada con el notch real de la pantalla.

/// Geometría de la maqueta v3, en píxeles de la maqueta de 1024×352.
struct NotchV3Layout: Decodable {
    struct Rect: Decodable { let x, y, w, h: CGFloat }
    struct Panel: Decodable { let x, y, w, h, topFlareRadius, bottomRadius: CGFloat }
    struct Element: Decodable {
        let x, y: CGFloat
        let w, h, capHeight, size, stroke: CGFloat?
        let text: String?
        let color: String
    }

    let notch: Rect
    let panel: Panel
    let characterCrop: Rect
    let panelBlack: String
    let ui: [String: Element]

    static let shared: NotchV3Layout = loadResourceJSON("notch-v3-layout")
}

/// Medidas del panel expandido en puntos, para el notch real de esta pantalla.
struct ExpandedGeometry {
    let layout: NotchV3Layout
    /// Puntos por píxel de maqueta: el notch de la maqueta se escala al ancho del notch real.
    let s: CGFloat

    init(metrics: NotchMetrics, layout: NotchV3Layout = .shared) {
        self.layout = layout
        s = metrics.width / layout.notch.w
    }

    private var notchCenterX: CGFloat { layout.notch.x + layout.notch.w / 2 }
    /// Bordes del cuerpo del panel respecto al centro del notch. En la maqueta el panel no está centrado.
    var minX: CGFloat { (layout.panel.x - notchCenterX) * s }
    var maxX: CGFloat { (layout.panel.x + layout.panel.w - notchCenterX) * s }
    var bodyWidth: CGFloat { layout.panel.w * s }
    var height: CGFloat { layout.panel.h * s }
    var offsetX: CGFloat { (minX + maxX) / 2 }
    var topRadius: CGFloat { layout.panel.topFlareRadius * s }
    var bottomRadius: CGFloat { layout.panel.bottomRadius * s }

    /// Rectángulo de maqueta → coordenadas del cuerpo del panel (origen arriba a la izquierda).
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: (x - layout.panel.x) * s, y: (y - layout.panel.y) * s, width: w * s, height: h * s)
    }
}

/// Los fotogramas del loop, decodificados una sola vez al arrancar la app.
final class NotchFrames {
    struct Exposure { let frame: String; let image: CGImage; let start: TimeInterval; let duration: TimeInterval }

    static let shared = NotchFrames()

    let exposures: [Exposure]
    let loop: TimeInterval

    private init() {
        struct Timing: Decodable {
            struct Entry: Decodable { let frame: String; let durationMs: Int }
            let sequenceDurationMs: Int
            let sequence: [Entry]
        }
        let timing: Timing = loadResourceJSON("notch-v3-timing")
        var images: [String: CGImage] = [:]
        var list: [Exposure] = []
        var t: TimeInterval = 0
        for entry in timing.sequence {
            let image = images[entry.frame] ?? decodePNG("notch-v3-\(entry.frame)")
            images[entry.frame] = image
            let d = TimeInterval(entry.durationMs) / 1000
            list.append(Exposure(frame: entry.frame, image: image, start: t, duration: d))
            t += d
        }
        precondition(abs(t * 1000 - Double(timing.sequenceDurationMs)) < 0.5, "La secuencia no suma su duración")
        exposures = list
        loop = t
    }

    /// Exposición visible a `elapsed` segundos del inicio del loop.
    func index(at elapsed: TimeInterval) -> Int {
        let t = max(0, elapsed).truncatingRemainder(dividingBy: loop)
        return exposures.lastIndex { $0.start <= t + 1e-6 } ?? 0
    }

    /// Momento (en segundos desde el origen) en que termina la exposición visible a `elapsed`.
    func nextChange(after elapsed: TimeInterval) -> TimeInterval {
        let elapsed = max(0, elapsed)
        let cycleStart = (elapsed / loop).rounded(.down) * loop
        let e = exposures[index(at: elapsed)]
        return cycleStart + e.start + e.duration
    }
}

/// Actualiza la vista exactamente al cambiar de dibujo, no a la frecuencia de la pantalla.
struct ExposureSchedule: TimelineSchedule {
    let origin: Date
    let frames: NotchFrames
    /// Reloj de referencia; se sustituye en la comprobación de tiempos.
    var now: () -> Date = Date.init

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next = startDate
        let origin = origin, frames = frames, now = now
        return AnyIterator {
            let current = next
            // SwiftUI puede pedir el calendario desde una fecha antigua y recorrerlo hasta el presente.
            // Se salta directo al cambio de dibujo posterior a ahora para no avanzar exposición a exposición.
            let from = max(current, now()).timeIntervalSince(origin)
            next = origin.addingTimeInterval(frames.nextChange(after: from))
            return current
        }
    }
}

/// Reproduce el loop desde `origin` (el momento en que se abrió el panel).
struct CapriFramePlayer: View {
    let origin: Date
    private let frames = NotchFrames.shared

    var body: some View {
        TimelineView(ExposureSchedule(origin: origin, frames: frames)) { ctx in
            Image(decorative: frames.exposures[frames.index(at: ctx.date.timeIntervalSince(origin))].image, scale: 1)
                .resizable()
                .interpolation(.high)
        }
    }
}

/// Contenido del panel expandido: Capri + interfaz nativa, colocados en coordenadas de la maqueta.
struct ExpandedPresenceView: View {
    let geometry: ExpandedGeometry
    let origin: Date
    @ObservedObject var permissions: PermissionCenter

    // Tamaños de letra calibrados contra la maqueta (px de maqueta; ver tools/preparar_notch_v3.py).
    private enum FontPx {
        static let title: CGFloat = 19.75      // bold 11 pt con el notch de 185 pt
        static let message: CGFloat = 23.33    // semibold 13 pt
        static let button: CGFloat = 18.84     // semibold 10,5 pt
        static let icon: CGFloat = 25
    }

    var body: some View {
        let g = geometry, l = geometry.layout, crop = l.characterCrop
        let r = g.rect(crop.x, crop.y, crop.w, crop.h)
        ZStack(alignment: .topLeading) {
            CapriFramePlayer(origin: origin)
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)

            if let title = l.ui["title"], let dot = l.ui["dot"], let message = l.ui["message"], let button = l.ui["button"] {
                text(title, size: FontPx.title, weight: .bold, kerning: 0.4)
                // Verde: lista para hablar. Rojo: le falta algún permiso.
                Circle()
                    .fill(permissions.allGranted ? Color(hexString: dot.color) : Theme.red)
                    .frame(width: (dot.size ?? 15) * g.s, height: (dot.size ?? 15) * g.s)
                    .offset(x: g.rect(dot.x, dot.y, 0, 0).minX, y: g.rect(dot.x, dot.y, 0, 0).minY)
                text(message, size: FontPx.message, weight: .semibold)
                talkButton(button)
            }
        }
        .frame(width: g.bodyWidth, height: g.height, alignment: .topLeading)
    }

    /// Texto colocado por su línea base: arriba de las mayúsculas en `e.y`, como en la maqueta.
    private func text(_ e: NotchV3Layout.Element, size px: CGFloat, weight: NSFont.Weight, kerning: CGFloat = 0) -> some View {
        let g = geometry
        let font = NSFont.systemFont(ofSize: px * g.s, weight: weight)
        let baseline = (e.y + (e.capHeight ?? 0)) * g.s
        return Text(e.text ?? "")
            .font(Font(font))
            .kerning(kerning)
            .foregroundStyle(Color(hexString: e.color))
            .fixedSize()
            .offset(x: (e.x - g.layout.panel.x) * g.s, y: baseline - font.ascender)
    }

    private func talkButton(_ e: NotchV3Layout.Element) -> some View {
        let g = geometry
        let frame = g.rect(e.x, e.y, e.w ?? 0, e.h ?? 0)
        let green = Color(hexString: e.color)
        let ready = permissions.allGranted
        return Button {
            // Sin permisos, el botón los pide. Con ellos, hablar llega en el paso 4 de la Fase 2.
            if !ready { permissions.requestMissing() }
        } label: {
            HStack(spacing: 11 * g.s) {
                Image(systemName: ready ? "mic" : "lock.open")
                    .font(.system(size: FontPx.icon * g.s, weight: .medium))
                Text(ready ? (e.text ?? "") : "Permisos")
                    .font(.system(size: FontPx.button * g.s, weight: .semibold))
            }
            .foregroundStyle(green)
            .frame(width: frame.width, height: frame.height)
            .overlay(Capsule().strokeBorder(green, lineWidth: (e.stroke ?? 2) * g.s))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(ready ? "Disponible cuando Capri tenga voz"
                    : "Capri necesita: " + permissions.missing.map(\.title).joined(separator: ", "))
        .offset(x: frame.minX, y: frame.minY)
    }
}

extension Color {
    init(hexString: String) {
        self.init(hex: UInt32(hexString, radix: 16) ?? 0)
    }
}

func loadResourceJSON<T: Decodable>(_ name: String) -> T {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let value = try? JSONDecoder().decode(T.self, from: data)
    else { fatalError("No se pudo leer el recurso \(name).json") }
    return value
}

private func decodePNG(_ name: String) -> CGImage {
    guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    else { fatalError("Falta el fotograma \(name).png") }
    return image
}
