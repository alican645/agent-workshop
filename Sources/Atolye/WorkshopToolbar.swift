import AtolyeCore
import SwiftUI

/// Atölye ekranının üst çubuğu.
struct WorkshopToolbar: View {
    let model: WorkshopModel

    var body: some View {
        HStack(spacing: 6) {
            Text("Agent Workshop").font(.headline).foregroundStyle(Theme.barText)
            Spacer()
            // Pencereler
            GitHubButton(github: model.github)
            RobotsButton()
            BarSeparator()
            // Hesap ve harcama
            ProfileMenu(model: model)
            if model.todayTokens > 0 {
                BarChip(icon: "chart.bar.xaxis", title: L("Bugün ≈ {0}", UsageFormat.usd(model.todayCost)),
                        detail: L("{0} token", UsageFormat.tokens(model.todayTokens)), interactive: false)
                    .help(L("Bugün bütün Claude oturumlarında (kapananlar dahil) harcanan token ve API karşılığı.") + "\n" + UsageFormat.note)
            }
            BarSeparator()
            Button { model.addProject() } label: {
                BarChip(icon: "plus", title: L("Proje ekle"), tint: Theme.focus)
            }
            .buttonStyle(.plain)
            .help(L("Bir proje klasörünü atölyeye sabitle"))
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
            BarChip(icon: "square.grid.3x3.fill", title: "GitHub",
                    detail: github.stats.flatMap { $0.currentStreak > 0 ? L("{0} gün 🔥", "\($0.currentStreak)") : nil })
        }
        .buttonStyle(.plain)
        .help(L("GitHub katkıların"))
        .task { github.refreshIfStale() }
    }
}

/// Üst çubukta Robotlar penceresini açan düğme.
private struct RobotsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button { openWindow(id: "robots") } label: {
            BarChip(icon: "figure.wave", title: L("Robotlar"))
        }
        .buttonStyle(.plain)
        .help(L("Atölyedeki robotları seç, kendi .glb robotunu ekle"))
    }
}

/// Üst çubuktaki bütün öğelerin ortak görünümü: aynı boyda, yuvarlak köşeli bir çip.
/// `tint` verilirse dolgulu (öne çıkan eylem ya da uyarı), yoksa açık zeminli.
struct BarChip: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var tint: Color? = nil
    var interactive = true
    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(title).font(.system(size: 12, weight: .semibold))
            if let detail {
                Text(detail).font(.system(size: 12)).opacity(tint == nil ? 1 : 0.85)
                    .foregroundStyle(tint == nil ? Theme.barMuted : .white)
            }
        }
        .lineLimit(1)
        .foregroundStyle(tint == nil ? Theme.barText : .white)
        .padding(.horizontal, 9).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(fill))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { hover = interactive && $0 }
        .fixedSize()
    }

    private var fill: Color {
        if let tint { return hover ? tint.opacity(0.85) : tint }
        return Theme.barText.opacity(hover ? 0.12 : 0.06)
    }
}

/// Üst çubukta grupları ayıran ince çizgi.
private struct BarSeparator: View {
    var body: some View {
        Rectangle().fill(Theme.barText.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 4)
    }
}
