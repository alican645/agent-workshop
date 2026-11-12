import AjanTakipCore
import SwiftUI

/// Hap açıkken gösterilen oturum listesi.
struct SessionListView: View {
    let sessions: [Session]
    /// (cpu, ram) 0…1; nil ise sistem kullanımı bölümü gizlenir.
    let stats: (cpu: Double?, ram: Double?)?
    /// Detay penceresinde açık olan metrik.
    let openMetric: ProcessUsage.Metric?
    let accounts: AccountManager
    let todos: TodoManager
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
                if accounts.hasMultiple || !accounts.usage.isEmpty {
                    AccountsSection(accounts: accounts, now: context.date)
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
                    SessionRow(session: s, now: context.date, todo: todos.progress(for: s),
                               todoOpen: todos.openRoot != nil && todos.openRoot == todos.root(for: s),
                               hasCwd: s.cwd != nil,
                               onTodo: { todos.toggleWindow(for: s) })
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

/// Hesap başına 5 saatlik / 7 günlük kullanım; satıra tıklamak hesabı aktif yapar.
private struct AccountsSection: View {
    let accounts: AccountManager
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(accounts.store.profiles) { p in
                AccountRow(name: p.name, email: accounts.auth[p.id]?.email,
                           isActive: accounts.store.activeID == p.id,
                           usage: accounts.usage[p.id], now: now)
                    .contentShape(Rectangle())
                    .onTapGesture { accounts.setActive(p.id) }
            }
            if let dup = accounts.duplicateWarning {
                Text("⚠︎ \(dup)").font(.system(size: 10)).foregroundStyle(.yellow)
            }
        }
    }
}

private struct AccountRow: View {
    let name: String
    let email: String?
    let isActive: Bool
    let usage: AccountUsage?
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(isActive ? .green : .white.opacity(0.45))
            Text(name)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.7))
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)
            MiniBar(label: "5s", fraction: usage?.effectiveFiveHour(now: now), stale: isStale)
            MiniBar(label: "7g", fraction: usage?.effectiveSevenDay(now: now), stale: isStale)
        }
        .help(tooltip)
    }

    private var isStale: Bool { usage.map { now.timeIntervalSince($0.reportedAt) > 15 * 60 } ?? true }

    private var tooltip: String {
        var lines = [email ?? "giriş bilgisi yok"]
        guard let usage else { return (lines + ["henüz kullanım bildirilmedi"]).joined(separator: "\n") }
        lines.append("son bildirim: \(DurationFormat.short(now.timeIntervalSince(usage.reportedAt))) önce")
        if let r = usage.fiveHourResetsAt, r > now { lines.append("5s sıfırlanma: \(DurationFormat.short(r.timeIntervalSince(now))) sonra") }
        if let r = usage.sevenDayResetsAt, r > now { lines.append("7g sıfırlanma: \(DurationFormat.short(r.timeIntervalSince(now))) sonra") }
        return lines.joined(separator: "\n")
    }
}

private struct MiniBar: View {
    let label: String
    let fraction: Double?
    let stale: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, fraction ?? 0)))
                }
            }
            .frame(width: 44, height: 5)
            Text(fraction.map(SystemStats.percentText) ?? "–")
                .foregroundStyle(fraction == nil ? .white.opacity(0.5) : color)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
        .opacity(stale ? 0.6 : 1)
    }

    private var color: Color {
        let f = fraction ?? 0
        if f >= AccountStore.warningThreshold { return .red }
        if f >= 0.7 { return .yellow }
        return .white.opacity(0.85)
    }
}

private struct SessionRow: View {
    let session: Session
    let now: Date
    let todo: (done: Int, total: Int)?
    let todoOpen: Bool
    let hasCwd: Bool
    let onTodo: () -> Void
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
            todoBadge
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

    /// Dosya varsa "☑ 3/7"; yoksa yalnızca üzerine gelince soluk bir simge (yeni liste başlatmak için).
    @ViewBuilder private var todoBadge: some View {
        if let todo {
            HStack(spacing: 3) {
                Image(systemName: todoOpen ? "checklist.checked" : "checklist")
                Text("\(todo.done)/\(todo.total)").monospacedDigit()
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(todoOpen ? 0.95 : 0.6))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(.white.opacity(todoOpen ? 0.2 : 0.08)))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTodo)
            .help("TODO.local.md")
        } else if hasCwd && (hovering || todoOpen) {
            Image(systemName: "checklist")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(todoOpen ? 0.9 : 0.35))
                .contentShape(Rectangle())
                .onTapGesture(perform: onTodo)
                .help("TODO.local.md oluştur")
        }
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
