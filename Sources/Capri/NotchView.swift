import SwiftUI

struct NotchView: View {
    @ObservedObject var model: AssistantModel

    private var active: Bool { model.mode != .idle }

    var body: some View {
        let m = model.metrics, g = model.geometry
        let top: CGFloat = model.expanded ? g.topRadius : 6
        let bottom: CGFloat = model.expanded ? g.bottomRadius : 12
        // El cuerpo visible es 2*top más angosto que el frame (las esquinas cóncavas).
        let w = (model.expanded ? g.bodyWidth : (active ? m.width + 2 * Layout.collapsedSide : m.width)) + 2 * top
        let h = model.expanded ? g.height : m.height
        // Abierto, el panel sigue la maqueta v3 (no está centrado en la cámara); cerrado, se centra en ella.
        let dx = model.expanded ? g.offsetX : 0

        ZStack(alignment: .top) {
            NotchShape(topRadius: top, bottomRadius: bottom)
                .fill(Theme.panel)
                .overlay(alignment: .top) {
                    content(top: top)
                        .clipShape(NotchShape(topRadius: top, bottomRadius: bottom))
                }
                .overlay {
                    // El borde y el brillo rojos solo marcan el estado cerrado activo: en reposo el notch
                    // se ve como el de la pantalla, y la maqueta abierta no los lleva.
                    NotchShape(topRadius: top, bottomRadius: bottom)
                        .stroke(LinearGradient(colors: [Theme.red.opacity(0), Theme.red.opacity(0.8)],
                                               startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        .opacity(!model.expanded && active ? 1 : 0)
                }
                .shadow(color: Theme.red.opacity(!model.expanded && active ? 0.35 : 0), radius: 14, y: 4)
                .frame(width: w, height: h)
                .offset(x: dx)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: model.expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.mode)
        .contentShape(Rectangle())
        .onTapGesture { if model.expanded { model.mode = model.mode.next } }
    }

    @ViewBuilder
    private func content(top: CGFloat) -> some View {
        let m = model.metrics
        ZStack(alignment: .top) {
            // Estado colapsado activo: Capri a un lado del notch físico, onda al otro.
            // Con `if` y no con opacidad: una vista oculta con opacidad 0 sigue animándose y gastando CPU.
            if !model.expanded {
                collapsedAccessories(m, top: top)
                    .transition(.opacity)
            }

            expandedContent(m, top: top)
                .opacity(model.expanded ? 1 : 0)
                .animation(.easeOut(duration: 0.18).delay(model.expanded ? 0.12 : 0), value: model.expanded)
        }
    }

    private func collapsedAccessories(_ m: NotchMetrics, top: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if active {
                HStack {
                    LiveCapriFace(mode: model.mode)
                        .frame(width: m.height + 4, height: m.height + 4)
                        .padding(.leading, top + 4)
                    Spacer()
                    WaveformView(mode: model.mode, bars: 4)
                        .frame(width: 22, height: 12)
                        .padding(.trailing, top + 12)
                }
                .frame(maxHeight: .infinity)
                .transition(.opacity)
            }
            // En reposo no se dibuja nada: el notch se ve igual que el de la pantalla.
        }
        // Altura fija: si no, el contenido expandido (oculto) estira el ZStack y saca esto de la zona visible.
        .frame(height: m.height)
    }

    private func expandedContent(_ m: NotchMetrics, top: CGFloat) -> some View {
        Group {
            if model.expanded {
                ExpandedPresenceView(geometry: model.geometry, origin: model.expandedAt)
                    .padding(.leading, top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
