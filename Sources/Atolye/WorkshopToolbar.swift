import SwiftUI

/// Atölye ekranının üst çubuğu.
struct WorkshopToolbar: View {
    let model: WorkshopModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Atölye").font(.headline).foregroundStyle(Theme.barText)
            Spacer()
            GitHubButton(github: model.github)
            ProfileMenu(model: model)
            if model.todayTokens > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 11))
                    Text("Bugün ≈ \(UsageFormat.usd(model.todayCost))").font(.system(size: 12, weight: .semibold))
                    Text("· \(UsageFormat.tokens(model.todayTokens)) token").font(.system(size: 12))
                }
                .foregroundStyle(Theme.barMuted)
                .help("Bugün bütün Claude oturumlarında (kapananlar dahil) harcanan token ve API karşılığı.\n\(UsageFormat.note)")
            }
            Button { model.addProject() } label: {
                Label("Proje ekle", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.barText.opacity(0.08)))
                    .foregroundStyle(Theme.barText)
            }
            .buttonStyle(.plain)
            .help("Bir proje klasörünü atölyeye sabitle")
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Theme.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Üst çubukta GitHub panosunu açan düğme; girişliyse serini gösterir.
private struct GitHubButton: View {
    let github: GitHubModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button { openWindow(id: "github") } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.3x3.fill").font(.system(size: 11))
                Text("GitHub").font(.system(size: 12, weight: .semibold))
                if let s = github.stats, s.currentStreak > 0 {
                    Text("· \(s.currentStreak) gün 🔥").font(.system(size: 12))
                }
            }
            .foregroundStyle(Theme.barMuted)
        }
        .buttonStyle(.plain)
        .help("GitHub katkıların")
        .task { github.refreshIfStale() }
    }
}
