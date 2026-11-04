import SwiftUI

struct NotchView: View {
    @ObservedObject var model: AssistantModel

    private var active: Bool { model.mode != .idle }
    /// Suena Spotify y Capri está en reposo: carátula y barras a los lados del notch cerrado (C-29).
    /// Si Capri escucha o habla, tiene prioridad; en pausa el notch vuelve a verse como el de la pantalla.
    private var showsMusic: Bool { !active && model.nowPlaying?.isPlaying == true }

    var body: some View {
        let m = model.metrics, g = model.geometry
        let top: CGFloat = model.expanded ? g.topRadius : 6
        let bottom: CGFloat = model.expanded ? g.bottomRadius : 12
        // El cuerpo visible es 2*top más angosto que el frame (las esquinas cóncavas).
        let w = (model.expanded ? g.bodyWidth : (active || showsMusic ? m.width + 2 * Layout.collapsedSide : m.width)) + 2 * top
        let h = model.expanded ? g.height + model.stripHeight : m.height
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
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showsMusic)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.showsStrip)
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
                    WaveformView(mode: model.mode, bars: 4, level: model.mode == .listening ? model.audioLevel : nil)
                        .frame(width: 22, height: 12)
                        .padding(.trailing, top + 12)
                }
                .frame(maxHeight: .infinity)
                .transition(.opacity)
            } else if showsMusic {
                // Sin borde ni brillo rojos: esos marcan a Capri activa, la música solo acompaña.
                HStack {
                    ArtworkThumb(image: model.artwork)
                        .frame(width: m.height - 10, height: m.height - 10)
                        .padding(.leading, top + 12)
                    Spacer()
                    MusicBars()
                        .frame(width: 18, height: 12)
                        .padding(.trailing, top + 14)
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
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        // Con música, su columna ocupa el sitio de la interfaz de Capri; Capri no se mueve (C-29).
                        ExpandedPresenceView(model: model, permissions: model.permissions, showsInterface: !model.showsMusicPanel)
                        if model.showsMusicPanel {
                            MusicColumnView(model: model)
                                .transition(.opacity)
                        }
                    }
                    if model.showsStrip, let copyable = model.copyable {
                        CopyStripView(model: model, text: copyable)
                            .transition(.opacity)
                    }
                }
                .padding(.leading, top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
