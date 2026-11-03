import AppKit

/// Icono de Capri para la barra de menús: su máscara angular con los dos ojos de anillo y tres puntas
/// de melena. Es una imagen plantilla (monocroma): macOS la pinta en blanco o negro según la barra.
enum MenuBarIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let k = rect.width / 18
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * k, y: y * k) }
            NSColor.black.setFill()

            // Puntas de melena sobre la máscara.
            for (base, tip) in [((3.0, 7.0), (2.0, 1.0)), ((8.0, 6.0), (9.5, 0.5)), ((13.5, 5.5), (16.5, 1.5))] {
                let spike = NSBezierPath()
                spike.move(to: p(base.0 - 2, base.1))
                spike.line(to: p(tip.0, tip.1))
                spike.line(to: p(base.0 + 2, base.1))
                spike.close()
                spike.fill()
            }

            // Máscara con los ojos recortados (regla par-impar: los anillos quedan como huecos).
            let mask = NSBezierPath()
            mask.move(to: p(0.5, 6.5))
            mask.line(to: p(17.5, 5.0))
            mask.line(to: p(16.0, 13.0))
            mask.line(to: p(9.0, 15.5))
            mask.line(to: p(2.0, 13.5))
            mask.close()
            for c in [p(5.8, 10.0), p(12.2, 9.4)] {
                let r = 3.0 * k
                mask.appendOval(in: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
            mask.windingRule = .evenOdd
            mask.fill()

            // Iris con la pupila hueca: anillos concéntricos, como los ojos de Capri.
            for c in [p(5.8, 10.0), p(12.2, 9.4)] {
                let iris = NSBezierPath()
                for r in [2.0 * k, 0.8 * k] {
                    iris.appendOval(in: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                }
                iris.windingRule = .evenOdd
                iris.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Capri"
        return image
    }
}
