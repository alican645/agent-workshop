import AtolyeCore
import AppKit
import SwiftUI

/// Profiller penceresi (GitHub panosuyla aynı görünüm): her Claude hesabı bir kart; limitler, sıfırlanmaya
/// kalan süre, giriş durumu; profile geçme, giriş yapma, beklenen hesabı ayarlama ve profil ekleme.
struct ProfilesWindow: View {
    let model: WorkshopModel
    private var profiles: Profiles { model.profiles }
    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 14)]

    var body: some View {
        // Dakikada bir yenilenir: sıfırlanmaya kalan süre akar.
        TimelineView(.everyMinute) { ctx in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(profiles.profiles) { card($0, now: ctx.date) }
                    }
                    Text(L("Skill'ler, MCP'ler, ayarlar, hafıza ve geçmiş bütün profillerde ortak."))
                        .font(.caption).foregroundStyle(GHTheme.muted)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 660, minHeight: 420)
        .background(GHTheme.background)
        .foregroundStyle(GHTheme.text)
        .onAppear { profiles.refresh() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "person.2.fill").font(.system(size: 28)).foregroundStyle(Theme.focus)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Profiller")).font(.title2.bold())
                Text(L("Claude oturumları bu profille açılır; açık olanlar kaldıkları yerden sürer"))
                    .font(.callout).foregroundStyle(GHTheme.muted)
            }
            Spacer()
            Button { addProfile() } label: {
                Label(L("Profil ekle"), systemImage: "plus").padding(.horizontal, 10).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Theme.focus)
        }
    }

    // MARK: Kart

    private func card(_ p: AccountProfile, now: Date) -> some View {
        let isActive = p.id == profiles.active.id
        let login = profiles.loggedIn[p.id] ?? p.email
        let u = profiles.limits[p.id]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.displayName).font(.system(size: 15, weight: .semibold))
                    Text(login ?? L("giriş yok")).font(.caption).foregroundStyle(GHTheme.muted)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if isActive {
                    Label(L("Etkin"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.focus)
                } else {
                    Button(L("Bu profile geç")) { model.switchProfile(to: p.id) }.controlSize(.small)
                }
            }
            if let u {
                LimitBar(title: L("5 saatlik"), value: u.effectiveFiveHour(now: now),
                         reset: AccountUsage.resetIn(u.fiveHourResetsAt, now: now))
                LimitBar(title: L("Haftalık"), value: u.effectiveSevenDay(now: now),
                         reset: AccountUsage.resetIn(u.sevenDayResetsAt, now: now))
            } else {
                Text(L("Limit bilgisi henüz yok; bu profilde bir Claude oturumu açılınca gelir."))
                    .font(.caption).foregroundStyle(GHTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if profiles.needsWarning(p, now: now) { warning(L("Limite yakın")) }
            if let m = profiles.mismatch(p) { warning(m) }
            HStack(spacing: 8) {
                Button(L("Giriş yap")) { model.login(profile: p.id) }
                Button(L("Beklenen hesap…")) {
                    if let e = ProfilesButton.askEmail(title: L("{0} hangi hesapla kullanılacak?", p.displayName), current: p.email) {
                        profiles.setEmail(e, for: p.id)
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(GHTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isActive ? Theme.focus : .clear, lineWidth: 2))
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }

    private func addProfile() {
        guard let e = ProfilesButton.askEmail(title: L("Yeni profil"), current: nil) else { return }
        let p = profiles.add(email: e)
        model.login(profile: p.id)
    }
}

/// Bir limit: ad, yüzde, doluluk çubuğu ve sıfırlanmaya kalan süre.
private struct LimitBar: View {
    let title: String
    let value: Double?
    let reset: String?

    var body: some View {
        let v = min(max(value ?? 0, 0), 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text(value.map { "%\(Int(($0 * 100).rounded()))" } ?? "–")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(GHTheme.background)
                    Capsule().fill(color(v)).frame(width: max(g.size.width * v, v > 0 ? 4 : 0))
                }
            }
            .frame(height: 6)
            if let reset {
                Text(L("{0} sonra sıfırlanır", reset)).font(.caption2).foregroundStyle(GHTheme.muted)
            }
        }
    }

    private func color(_ v: Double) -> Color {
        v >= AccountStore.warningThreshold ? Color(red: 0.85, green: 0.33, blue: 0.31)
            : v >= 0.7 ? Color.orange : Color(red: 0.23, green: 0.65, blue: 0.48)
    }
}
