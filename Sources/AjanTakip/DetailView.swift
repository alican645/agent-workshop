import AjanTakipCore
import AppKit
import SwiftUI

/// CPU veya RAM için programlara göre ayrıntı penceresinin içeriği.
struct DetailView: View {
    let model: AppModel
    let moveWindow: (NSPoint) -> Void
    let windowTopLeft: () -> NSPoint
    let contentSizeChanged: (CGSize) -> Void

    @State private var dragStart: (mouse: NSPoint, window: NSPoint)?
    private static let gb = 1_073_741_824.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let metric = model.detailMetric {
                header(metric)
                if metric == .memory { memoryBreakdown } else { cpuBar }
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                programList(metric)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .font(.system(size: 12, design: .rounded))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.6)))
                .environment(\.colorScheme, .dark))
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            DispatchQueue.main.async { contentSizeChanged(size) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Başlık (sürükleme alanı)

    private func header(_ metric: ProcessUsage.Metric) -> some View {
        HStack(spacing: 8) {
            Text(metric == .cpu ? "CPU" : "RAM")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(headerValue(metric))
                .foregroundStyle(.white.opacity(0.75))
                .monospacedDigit()
            Spacer(minLength: 8)
            Button { model.closeDetail() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Kapat")
        }
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private func headerValue(_ metric: ProcessUsage.Metric) -> String {
        switch metric {
        case .cpu:
            let p = model.cpuUsage.map(SystemStats.percentText) ?? "–"
            return "\(p) · \(model.cores) çekirdek"
        case .memory:
            return model.memorySample.map(SystemStats.memoryHeader) ?? "–"
        }
    }

    // MARK: Üst grafikler

    private var cpuBar: some View {
        SegmentBar(segments: [(model.cpuUsage ?? 0, loadColor(model.cpuUsage ?? 0))])
    }

    @ViewBuilder private var memoryBreakdown: some View {
        if let m = model.memorySample, m.totalBytes > 0 {
            let total = Double(m.totalBytes)
            let parts: [(String, UInt64, Color)] = [
                ("Uygulamalar", m.appBytes, .blue),
                ("Sistem", m.wiredBytes, .orange),
                ("Sıkıştırılmış", m.compressedBytes, .purple),
                ("Önbellek", m.cacheBytes, .white.opacity(0.35)),
            ]
            SegmentBar(segments: parts.map { (Double($0.1) / total, $0.2) })
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      spacing: 4) {
                ForEach(parts, id: \.0) { name, bytes, color in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                        Text(name).foregroundStyle(.white.opacity(0.7))
                        Text(ProcessUsage.memoryText(bytes)).foregroundStyle(.white).monospacedDigit()
                    }
                    .font(.system(size: 11, design: .rounded))
                }
            }
            Text("Önbellek boş sayılır; gerektiğinde boşaltılır. Program değerleri sıkıştırılmış belleği de içerir.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Program listesi

    @ViewBuilder private func programList(_ metric: ProcessUsage.Metric) -> some View {
        if !model.processesReady {
            Text("ölçülüyor…").foregroundStyle(.white.opacity(0.5))
        } else {
            let b = ProcessUsage.breakdown(model.processUsage, by: metric, limit: 10,
                                           cores: model.cores, totalCPU: model.cpuUsage)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(b.top, id: \.name) { item in
                    row(item.name, value(item, metric))
                }
                if metric == .memory, b.otherCount > 0 {
                    row("Diğer \(b.otherCount) program", ProcessUsage.memoryText(b.otherMemoryBytes), dim: true)
                }
                if metric == .cpu {
                    row("Diğer + sistem", ProcessUsage.cpuText(b.otherCPUShare), dim: true)
                }
            }
        }
    }

    private func value(_ item: AppUsage, _ metric: ProcessUsage.Metric) -> String {
        metric == .cpu ? ProcessUsage.cpuText(ProcessUsage.machineShare(item, cores: model.cores))
                       : ProcessUsage.memoryText(item.memoryBytes)
    }

    private func row(_ name: String, _ value: String, dim: Bool = false) -> some View {
        HStack {
            Text(name).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(.white.opacity(dim ? 0.5 : 0.9))
            Spacer(minLength: 8)
            Text(value).monospacedDigit().foregroundStyle(.white.opacity(dim ? 0.5 : 0.8))
        }
    }

    private func loadColor(_ f: Double) -> Color {
        switch LoadLevel(fraction: f) {
        case .normal: .white.opacity(0.85)
        case .high: .yellow
        case .critical: .red
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                if dragStart == nil { dragStart = (mouse, windowTopLeft()) }
                guard let s = dragStart else { return }
                moveWindow(NSPoint(x: s.window.x + mouse.x - s.mouse.x, y: s.window.y + mouse.y - s.mouse.y))
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// Yatay, parçalı kullanım çubuğu (her parça 0…1 oranında).
private struct SegmentBar: View {
    let segments: [(Double, Color)]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        Rectangle().fill(seg.1).frame(width: geo.size.width * min(1, max(0, seg.0)))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.4), value: segments.map(\.0))
    }
}
