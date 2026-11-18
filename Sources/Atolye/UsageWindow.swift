import AtolyeCore
import SwiftUI

/// Günlük token kullanımı: GitHub katkı grafiği gibi bir yıllık ısı haritası ve özet kartları.
struct UsageWindow: View {
    let model: WorkshopModel
    private var history: UsageHistoryModel { model.usageHistory }

    var body: some View {
        let s = history.summary
        let today = UsageMeter.dayKey(Date())
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                HStack(spacing: 12) {
                    StatCard(title: L("Bugün"), value: UsageFormat.tokens(s.today.tokens), note: "≈ " + UsageFormat.usd(s.today.cost))
                    StatCard(title: L("Son 7 gün"), value: UsageFormat.tokens(s.lastSevenDays.tokens), note: "≈ " + UsageFormat.usd(s.lastSevenDays.cost))
                    StatCard(title: L("Bu ay"), value: UsageFormat.tokens(s.thisMonth.tokens), note: "≈ " + UsageFormat.usd(s.thisMonth.cost))
                    StatCard(title: L("Seri"), value: "\(s.currentStreak) 🔥", note: s.currentStreak == 1 ? L("gün") : L("gün üst üste"),
                             highlight: s.currentStreak > 1 && s.currentStreak == s.longestStreak)
                    StatCard(title: L("En yoğun gün"), value: s.busiest.map { UsageFormat.tokens($0.usage.tokens) } ?? "–",
                             note: s.busiest.map { Self.dateText($0.date) + " · ≈ " + UsageFormat.usd($0.usage.cost) } ?? L("henüz yok"))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("{0} token · son bir yıl", UsageFormat.tokens(s.yearTokens))).font(.headline)
                    Heatmap(days: UsageHistory.year(history.days, today: today), color: Self.orange) { day in
                        let u = history.days[day.date]
                        return Self.dateText(day.date) + ": " + L("{0} token", UsageFormat.tokens(day.count))
                            + (u.map { $0.cost > 0 ? " · ≈ " + UsageFormat.usd($0.cost) : "" } ?? "")
                    }
                    Text(historyNote(s)).font(.caption).foregroundStyle(GHTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).background(RoundedRectangle(cornerRadius: 12).fill(GHTheme.card))
                Text(UsageFormat.note).font(.caption).foregroundStyle(GHTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .frame(minWidth: 860, minHeight: 460)
        .background(GHTheme.background)
        .foregroundStyle(GHTheme.text)
        .onAppear { history.refresh(configDirs: model.profiles.profiles.map(\.configDir), force: true) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 26)).foregroundStyle(Theme.focus)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Kullanım")).font(.title2.bold())
                Text(L("Bütün Claude oturumları ve hesaplar, yardımcı ajanlar dahil")).font(.callout).foregroundStyle(GHTheme.muted)
            }
            Spacer()
            if history.loading {
                ProgressView().controlSize(.small)
            } else if let t = history.lastUpdated {
                (Text(L("güncellendi") + " ") + Text(t, format: .relative(presentation: .named))).font(.caption).foregroundStyle(GHTheme.muted)
            }
            Button { history.refresh(configDirs: model.profiles.profiles.map(\.configDir), force: true) } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(history.loading).help(L("Şimdi tazele"))
        }
    }

    private func historyNote(_ s: UsageSummary) -> String {
        let since = s.firstDay.map { L("Kayıtlar {0} tarihinden beri.", Self.dateText($0)) + " " } ?? ""
        return since + L("Claude Code eski oturum kayıtlarını siler (varsayılan 30 gün); Agent Workshop günlük toplamları ayrıca saklar, grafik zamanla bir yıla tamamlanır.")
    }

    /// "2026-11-18" → yerel kısa tarih.
    static func dateText(_ key: String) -> String {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return key }
        return d.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.locale))
    }

    /// Turuncu tonlar (atölyenin vurgu rengi); 0 = kullanım yok.
    static func orange(_ level: Int) -> Color {
        switch level {
        case 1: Color(red: 1.0, green: 0.85, blue: 0.68)
        case 2: Color(red: 1.0, green: 0.70, blue: 0.42)
        case 3: Color(red: 0.97, green: 0.52, blue: 0.18)
        case 4...: Color(red: 0.78, green: 0.36, blue: 0.06)
        default: Color(red: 0.88, green: 0.86, blue: 0.82)
        }
    }
}
