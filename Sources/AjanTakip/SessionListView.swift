import AjanTakipCore
import SwiftUI

/// Hap açıkken gösterilen oturum listesi.
struct SessionListView: View {
    let sessions: [Session]
    /// (cpu, ram) 0…1; nil ise sistem kullanımı bölümü gizlenir.
    let stats: (cpu: Double?, ram: Double?)?
    /// Detay penceresinde açık olan metrik.
    let openMetric: ProcessUsage.Metric?
    let onToggleMetric: (ProcessUsage.Metric) -> Void
    let onSelect: (Session) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                if let stats {
                    VStack(spacing: 5) {
                        usageSection(.cpu, title: "CPU", fraction: stats.cpu)
                        usageSection(.memory, title: "RAM", fraction: stats.ram)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.horizontal, 8)
                }
                if sessions.isEmpty {
                    Text("Aktif oturum yok")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                ForEach(sessions) { s in
                    SessionRow(session: s, now: context.date)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(s) }
                }
            }
            .padding(6)
        }
        .frame(width: 340, alignment: .leading)
        .font(.system(size: 12, design: .rounded))
    }
}

extension SessionListView {
    fileprivate func usageSection(_ metric: ProcessUsage.Metric, title: String, fraction: Double?) -> some View {
        UsageBar(title: title, fraction: fraction, isOpen: openMetric == metric)
            .contentShape(Rectangle())
            .onTapGesture { onToggleMetric(metric) }
            .help("Programlara göre ayrıntı")
    }
}

/// "CPU ████░░░░ 34%" satırı; renk yüke göre beyaz/sarı/kırmızı.
private struct UsageBar: View {
    let title: String
    let fraction: Double?
    var isOpen = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 28, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, fraction ?? 0)))
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.4), value: fraction)
            Text(fraction.map(SystemStats.percentText) ?? "–")
                .foregroundStyle(fraction == nil ? .white.opacity(0.55) : color)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            Image(systemName: isOpen ? "arrow.up.forward.square.fill" : "arrow.up.forward.square")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(isOpen ? 0.9 : 0.45))
                .frame(width: 10)
        }
    }

    private var color: Color {
        switch LoadLevel(fraction: fraction ?? 0) {
        case .normal: return .white.opacity(0.85)
        case .high: return .yellow
        case .critical: return .red
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let now: Date
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(session.state.symbol)
                .foregroundStyle(session.state.color)
                .frame(width: 14)
            Text(session.projectName)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            Text(detail)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if session.workspace == nil {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.white.opacity(0.4))
                    .help("cmux dışında")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering ? 0.12 : 0)))
        .onHover { hovering = $0 }
    }

    private var detail: String {
        let elapsed = DurationFormat.short(now.timeIntervalSince(session.stateSince))
        if session.state == .done { return "bitti · \(elapsed) önce" }
        return "\(session.activity) · \(elapsed)"
    }
}

extension SessionState {
    var symbol: String {
        switch self {
        case .waiting: "◐"
        case .working: "●"
        case .done: "✓"
        case .idle: "○"
        }
    }

    var color: Color {
        switch self {
        case .waiting: .orange
        case .working: .blue
        case .done: .green
        case .idle: .gray
        }
    }
}
