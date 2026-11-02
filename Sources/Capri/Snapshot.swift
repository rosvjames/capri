import AppKit
import SwiftUI

/// Renderiza el notch a PNG sin permisos de grabación de pantalla: `Capri --snapshot ruta.png [modo]`.
@MainActor
func writeSnapshot(to path: String, mode: AssistantMode) {
    let model = AssistantModel(metrics: NotchMetrics(width: 190, height: 32))
    model.expanded = true
    model.mode = mode
    let size = CGSize(width: Layout.expandedW + 2 * Layout.panelPadX, height: Layout.expandedH + Layout.panelPadY)
    let view = NotchView(model: model)
        .frame(width: size.width, height: size.height)
        .background(Color(white: 0.18))
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { print("snapshot failed"); return }
    try? png.write(to: URL(fileURLWithPath: path))
}
