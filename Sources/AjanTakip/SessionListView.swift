import AjanTakipCore
import SwiftUI

/// Hap açıkken gösterilen oturum listesi.
struct SessionListView: View {
    let sessions: [Session]
    let onSelect: (Session) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
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
