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
                SessionListView(sessions: model.store.sessions) { session in
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

    /// Uyarı sonrası liste açılana kadar 1,2 sn periyotla yanıp sönen kenarlık.
    @ViewBuilder private var pulseBorder: some View {
        if let kind = model.pulsing {
            let color: Color = kind == .attention ? .orange : .green
            PhaseAnimator([0.2, 1.0]) { phase in
                Capsule().strokeBorder(color, lineWidth: 2).opacity(phase)
            } animation: { _ in .easeInOut(duration: 0.6) }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var counters: some View {
        let c = model.store.counts
        let hasSessions = c.working + c.waiting + c.done > 0
        let showStats = model.showSystemStats
        HStack(spacing: 10) {
            if !hasSessions && !showStats {
                Text("○").foregroundStyle(.secondary)
            }
            if c.working > 0 { Counter(symbol: "●", value: c.working, color: .blue) }
            if c.waiting > 0 { Counter(symbol: "◐", value: c.waiting, color: .orange) }
            if c.done > 0 { Counter(symbol: "✓", value: c.done, color: .green) }
            if showStats {
                if hasSessions {
                    Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 14)
                }
                StatLabel(title: "CPU", fraction: model.cpuUsage)
                StatLabel(title: "RAM", fraction: model.ramUsage)
            }
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

private struct StatLabel: View {
    let title: String
    let fraction: Double?

    var body: some View {
        HStack(spacing: 3) {
            Text(title).foregroundStyle(.white.opacity(0.55)).font(.system(size: 10, weight: .semibold, design: .rounded))
            Text(fraction.map(SystemStats.percentText) ?? "–")
                .foregroundStyle(color)
                .monospacedDigit()
                .frame(minWidth: 30, alignment: .leading)
        }
    }

    private var color: Color {
        guard let fraction else { return .white.opacity(0.55) }
        switch LoadLevel(fraction: fraction) {
        case .normal: return .white
        case .high: return .yellow
        case .critical: return .red
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
