import SwiftUI

/// Atölye ekranının üst çubuğu.
struct WorkshopToolbar: View {
    let model: WorkshopModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Atölye").font(.headline).foregroundStyle(Theme.barText)
            Spacer()
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
