import AppKit
import SwiftUI

// Renderizado a PNG sin permisos de grabación de pantalla, para verificar la interfaz:
//   Capri --snapshot ruta.png [modo] [colapsado]   panel del notch en un modo (expandido por defecto)
//   Capri --gallery ruta.png                       las 9 expresiones de A-002 en cuadrícula 3×3

@MainActor
func writeSnapshot(to path: String, mode: AssistantMode, expanded: Bool = true) {
    let model = AssistantModel(metrics: NotchMetrics(width: 190, height: 32))
    model.expanded = expanded
    model.mode = mode
    let size = CGSize(width: Layout.expandedW + 2 * Layout.panelPadX, height: Layout.expandedH + Layout.panelPadY)
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
