import SwiftUI

struct NotchView: View {
    @ObservedObject var model: AssistantModel

    private var active: Bool { model.mode != .idle }

    var body: some View {
        let m = model.metrics
        let top: CGFloat = model.expanded ? 18 : 6
        let bottom: CGFloat = model.expanded ? 26 : 12
        // El cuerpo visible es 2*top más angosto que el frame (las esquinas cóncavas).
        let w = (model.expanded ? Layout.expandedW : (active ? m.width + 2 * Layout.collapsedSide : m.width)) + 2 * top
        let h = model.expanded ? Layout.expandedH : m.height

        ZStack(alignment: .top) {
            NotchShape(topRadius: top, bottomRadius: bottom)
                .fill(.black)
                .overlay(alignment: .top) {
                    content(top: top)
                        .clipShape(NotchShape(topRadius: top, bottomRadius: bottom))
                }
                .overlay {
                    NotchShape(topRadius: top, bottomRadius: bottom)
                        .stroke(LinearGradient(colors: [Theme.red.opacity(0), Theme.red.opacity(active || model.expanded ? 0.8 : 0.35)],
                                               startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .shadow(color: Theme.red.opacity(model.expanded ? 0.45 : (active ? 0.35 : 0.0)), radius: 14, y: 4)
                .frame(width: w, height: h)
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
            // Estado colapsado: Capri a un lado del notch físico, onda al otro, línea inferior respirando.
            collapsedAccessories(m, top: top)
                .opacity(model.expanded ? 0 : 1)

            expandedContent(m, top: top)
                .opacity(model.expanded ? 1 : 0)
                .animation(.easeOut(duration: 0.18).delay(model.expanded ? 0.12 : 0), value: model.expanded)
        }
    }

    private func collapsedAccessories(_ m: NotchMetrics, top: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            HStack {
                LiveCapriFace(mode: model.mode)
                    .frame(width: m.height + 4, height: m.height + 4)
                    .padding(.leading, top + 4)
                    .opacity(active ? 1 : 0)
                Spacer()
                WaveformView(mode: model.mode, bars: 4)
                    .frame(width: 22, height: 12)
                    .padding(.trailing, top + 12)
                    .opacity(active ? 1 : 0)
            }
            .frame(maxHeight: .infinity)

            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Capsule().fill(Theme.red)
                    .frame(width: m.width * 0.55, height: 1.5)
                    .shadow(color: Theme.red, radius: 5)
                    .opacity(0.35 + 0.35 * (0.5 + 0.5 * sin(t * 1.6)))
            }
            .opacity(active ? 0 : 1)
        }
        // Altura fija: si no, el contenido expandido (oculto) estira el ZStack y saca esto de la zona visible.
        .frame(height: m.height)
    }

    private func expandedContent(_ m: NotchMetrics, top: CGFloat) -> some View {
        HStack(spacing: 16) {
            LiveCapriFace(mode: model.mode)
                .frame(width: 100, height: 100)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    GlitchText(text: "CAPRI", intensity: active ? 0.9 : 0.35)
                    Text("//").font(Theme.mono(12)).foregroundStyle(Theme.dim)
                    Text(model.mode.label).font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.red)
                }
                WaveformView(mode: model.mode)
                    .frame(height: 22)
                Text(model.mode.sampleLine)
                    .font(Theme.mono(12))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, top + 16)
        .padding(.top, m.height + 4)
        .padding(.bottom, 14)
        .overlay { Scanlines() }
    }
}
