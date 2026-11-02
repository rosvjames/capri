import AppKit
import SwiftUI

// Renderizado a PNG sin permisos de grabación de pantalla, para verificar la interfaz:
//   Capri --snapshot ruta.png [modo] [colapsado] [t=ms]
//       panel del notch en un modo (expandido por defecto), con las métricas del notch real;
//       t=ms muestra el loop de Capri a esos milisegundos de haberse abierto
//   Capri --gallery ruta.png                       las 9 expresiones de A-002 en cuadrícula 3×3
//   Capri --timing-check                           imprime los cambios de dibujo que programa el reproductor (2 loops)

@MainActor
func writeSnapshot(to path: String, mode: AssistantMode, expanded: Bool = true, elapsedMs: Double = 0) {
    let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    let model = AssistantModel(metrics: screen.map(NotchMetrics.of) ?? NotchMetrics(width: 185, height: 32))
    _ = NotchFrames.shared  // decodificar antes de fijar la hora, para que el instante capturado sea el pedido
    model.expanded = expanded
    model.mode = mode
    model.expandedAt = Date().addingTimeInterval(-elapsedMs / 1000)
    let size = model.windowSize
    let view = NotchView(model: model)
        .frame(width: size.width, height: size.height)
        .background(Color(white: 0.18))
    writePNG(view, to: path)
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
