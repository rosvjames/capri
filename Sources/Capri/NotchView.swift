import SwiftUI

struct NotchView: View {
    @ObservedObject var model: AssistantModel

    private var active: Bool { model.mode != .idle }

    var body: some View {
        let m = model.metrics
        let top: CGFloat = model.expanded ? 18 : 6
        let bottom: CGFloat = model.expanded ? 26 : 12
        // El cuerpo visible es 2*top más angosto que el frame (las esquinas cóncavas).
        let w = (model.expanded ? Layout.expandedW : (active ? m.width + 76 : m.width)) + 2 * top
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
                        .stroke(LinearGradient(colors: [Theme.crimson.opacity(0), Theme.crimson.opacity(active || model.expanded ? 0.8 : 0.35)],
                                               startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .shadow(color: Theme.crimson.opacity(model.expanded ? 0.45 : (active ? 0.35 : 0.0)), radius: 14, y: 4)
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
            // Estado colapsado: indicadores a los lados del notch físico + línea inferior respirando.
            collapsedAccessories(m)
                .opacity(model.expanded ? 0 : 1)

            expandedContent(m, top: top)
                .opacity(model.expanded ? 1 : 0)
                .animation(.easeOut(duration: 0.18).delay(model.expanded ? 0.12 : 0), value: model.expanded)
        }
    }

    private func collapsedAccessories(_ m: NotchMetrics) -> some View {
        ZStack(alignment: .bottom) {
            HStack {
                Circle().fill(Theme.crimson).frame(width: 6, height: 6)
                    .shadow(color: Theme.crimson, radius: 4)
                    .padding(.leading, 26)
                    .opacity(active ? 1 : 0)
                Spacer()
                WaveformView(mode: model.mode, bars: 4)
                    .frame(width: 22, height: 12)
                    .padding(.trailing, 26)
                    .opacity(active ? 1 : 0)
            }
            .frame(maxHeight: .infinity)

            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Capsule().fill(Theme.crimson)
                    .frame(width: m.width * 0.55, height: 1.5)
                    .shadow(color: Theme.crimson, radius: 5)
                    .opacity(0.35 + 0.35 * (0.5 + 0.5 * sin(t * 1.6)))
            }
            .opacity(active ? 0 : 1)
        }
    }

    private func expandedContent(_ m: NotchMetrics, top: CGFloat) -> some View {
        HStack(spacing: 18) {
            CoreAvatar(mode: model.mode)
                .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    GlitchText(text: "CAPRI", intensity: active ? 0.9 : 0.35)
                    Text("//").font(Theme.mono(12)).foregroundStyle(Theme.dim)
                    Text(model.mode.label).font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.crimson)
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
        .padding(.horizontal, top + 22)
        .padding(.top, m.height + 6)
        .padding(.bottom, 16)
        .overlay { Scanlines() }
    }
}
