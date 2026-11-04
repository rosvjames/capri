import AppKit
import SwiftUI

/// Franja inferior del panel abierto con lo que hay que leer o copiar de una respuesta (C-03):
/// comandos, código, enlaces. Capri no los dice en voz; aquí se leen y se copian con un botón.
///
/// El panel crece hacia abajo solo lo que ocupa el texto (hasta `maxLines` líneas; lo copiado va completo).
/// Medidas en píxeles de la maqueta v3, escaladas como el resto del panel.
enum CopyStrip {
    fileprivate static let padLeft: CGFloat = 44
    fileprivate static let padRight: CGFloat = 44
    fileprivate static let padTop: CGFloat = 22
    fileprivate static let padBottom: CGFloat = 34   // la esquina inferior es redonda
    fileprivate static let gap: CGFloat = 24
    fileprivate static let fontSize: CGFloat = 21    // ~11,5 pt con el notch de 185 pt
    fileprivate static let buttonW: CGFloat = 132
    fileprivate static let buttonH: CGFloat = 42
    fileprivate static let maxLines = 4

    fileprivate static func font(_ g: ExpandedGeometry) -> NSFont {
        .monospacedSystemFont(ofSize: fontSize * g.s, weight: .regular)
    }

    fileprivate static func textWidth(_ g: ExpandedGeometry) -> CGFloat {
        g.bodyWidth - (padLeft + padRight + gap + buttonW) * g.s
    }

    private static func measure(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        ceil((text as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin], attributes: [.font: font]).height)
    }

    /// Alto del texto, recortado a `maxLines` líneas.
    fileprivate static func textHeight(for text: String, geometry g: ExpandedGeometry) -> CGFloat {
        let font = font(g)
        let line = measure("Ág", font: font, width: 1000)
        return min(measure(text, font: font, width: textWidth(g)), line * CGFloat(maxLines))
    }

    static func height(for text: String, geometry g: ExpandedGeometry) -> CGFloat {
        (padTop + padBottom) * g.s + max(buttonH * g.s, textHeight(for: text, geometry: g))
    }

    static func maxHeight(geometry g: ExpandedGeometry) -> CGFloat {
        height(for: Array(repeating: "Ág", count: maxLines).joined(separator: "\n"), geometry: g)
    }
}

struct CopyStripView: View {
    @ObservedObject var model: AssistantModel
    let text: String

    var body: some View {
        let g = model.geometry, s = g.s
        let textHeight = CopyStrip.textHeight(for: text, geometry: g)
        HStack(alignment: .center, spacing: CopyStrip.gap * s) {
            Text(text)
                .font(Font(CopyStrip.font(g)))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(CopyStrip.maxLines)
                .truncationMode(.tail)
                .frame(width: CopyStrip.textWidth(g), height: textHeight, alignment: .leading)
            copyButton(s)
        }
        .padding(.leading, CopyStrip.padLeft * s)
        .padding(.top, CopyStrip.padTop * s)
        .padding(.bottom, CopyStrip.padBottom * s)
        .frame(width: g.bodyWidth, height: CopyStrip.height(for: text, geometry: g), alignment: .topLeading)
        .overlay(alignment: .top) {
            // Separa la franja de Capri: sus fotogramas terminan justo en el borde del panel.
            LinearGradient(colors: [Theme.red.opacity(0), Theme.red.opacity(0.55), Theme.red.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .padding(.horizontal, CopyStrip.padLeft * s)
        }
    }

    private func copyButton(_ s: CGFloat) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            model.stripCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [model] in model.stripCopied = false }
        } label: {
            HStack(spacing: 8 * s) {
                Image(systemName: model.stripCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 20 * s, weight: .medium))
                Text(model.stripCopied ? "Copiado" : "Copiar")
                    .font(.system(size: 18.84 * s, weight: .semibold))
            }
            .foregroundStyle(Theme.green)
            .frame(width: CopyStrip.buttonW * s, height: CopyStrip.buttonH * s)
            .overlay(Capsule().strokeBorder(Theme.green, lineWidth: 3 * s))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Copiar al portapapeles")
    }
}
