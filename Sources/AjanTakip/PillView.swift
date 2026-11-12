import AjanTakipCore
import AppKit
import SwiftUI

/// Hap: kapalıyken durum sayaçları; tıklanınca altında oturum listesi açılır.
struct PillView: View {
    let model: AppModel
    /// Sürükleme sırasında pencerenin yeni üst-sol noktasını uygular.
    let moveWindow: (NSPoint) -> Void
    let windowTopLeft: () -> NSPoint
    /// SwiftUI içeriğinin ölçüsünü panele bildirir.
    let contentSizeChanged: (CGSize) -> Void
    /// Sürükleme bitince panel en yakın kenara yaslanır.
    let dragEnded: () -> Void

    @State private var dragStart: (mouse: NSPoint, window: NSPoint)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            pill
            if model.isExpanded {
                SessionListView(sessions: model.store.sessions,
                                stats: model.showSystemStats ? (model.cpuUsage, model.ramUsage) : nil,
                                processes: ProcessPanel(metric: model.expandedMetric, items: model.topProcesses,
                                                        ready: model.processesReady),
                                onToggleMetric: { model.toggleMetric($0) }) { session in
                    model.isExpanded = false
                    CmuxNavigator.focus(session)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.6)))
                        .environment(\.colorScheme, .dark))
            }
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            DispatchQueue.main.async { contentSizeChanged(size) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pill: some View {
        counters
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(PillBackground())
            .overlay { pulseBorder }
            .contentShape(Capsule())
            .gesture(drag)
            .onTapGesture { model.isExpanded.toggle() }
            .keyframeAnimator(initialValue: 0.0, trigger: model.shakeCount) { content, x in
                content.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    for x in [-4.0, 4, -4, 4, -2, 0] { LinearKeyframe(x, duration: 0.4 / 6) }
                }
            }
            .padding(.horizontal, 4)  // titreme için pay
    }

    /// Uyarı sonrası kenarlık 3 kez yanıp söner, sonra liste açılana kadar sabit kalır
    /// (sürekli animasyon ~%3 CPU harcıyordu).
    @ViewBuilder private var pulseBorder: some View {
        if let kind = model.pulsing {
            PulseBorder(color: kind == .attention ? .orange : .green)
                .id(model.lastAlert?.at)  // her yeni uyarıda yeniden yanıp söner
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var counters: some View {
        let c = model.store.counts
        HStack(spacing: 10) {
            if c.working + c.waiting + c.done == 0 {
                Text("○").foregroundStyle(.secondary)
            }
            if c.working > 0 { Counter(symbol: "●", value: c.working, color: .blue) }
            if c.waiting > 0 { Counter(symbol: "◐", value: c.waiting, color: .orange) }
            if c.done > 0 { Counter(symbol: "✓", value: c.done, color: .green) }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                if dragStart == nil { dragStart = (mouse, windowTopLeft()) }
                guard let s = dragStart else { return }
                moveWindow(NSPoint(x: s.window.x + mouse.x - s.mouse.x, y: s.window.y + mouse.y - s.mouse.y))
            }
            .onEnded { _ in
                dragStart = nil
                dragEnded()
            }
    }
}

private struct PulseBorder: View {
    let color: Color
    @State private var bright = false

    var body: some View {
        Capsule()
            .strokeBorder(color, lineWidth: 2)
            .opacity(bright ? 1 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatCount(5, autoreverses: true)) { bright = true }
            }
    }
}

private struct Counter: View {
    let symbol: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(symbol).foregroundStyle(color)
            Text("\(value)").foregroundStyle(.white).monospacedDigit()
        }
    }
}

struct PillBackground: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Color.black.opacity(0.55)))
            .environment(\.colorScheme, .dark)
    }
}
