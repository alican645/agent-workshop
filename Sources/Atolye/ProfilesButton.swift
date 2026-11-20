import AtolyeCore
import AppKit
import SwiftUI

/// Üst çubukta Profiller penceresini açan düğme: etkin profil, 5 saatlik limit ve sıfırlanmaya kalan süre.
struct ProfilesButton: View {
    let model: WorkshopModel
    @Environment(\.openWindow) private var openWindow
    private var profiles: Profiles { model.profiles }

    var body: some View {
        let active = profiles.active
        let alert = profiles.profiles.contains { profiles.needsWarning($0) || profiles.mismatch($0) != nil }
        Button { openWindow(id: "profiles") } label: {
            // Dakikada bir yenilenir: sıfırlanmaya kalan süre akar.
            TimelineView(.everyMinute) { ctx in
                BarChip(icon: alert ? "exclamationmark.triangle.fill" : "person.crop.circle", title: active.displayName,
                        detail: detail(active, now: ctx.date), tint: alert ? .orange : nil)
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))" }

    private func detail(_ p: AccountProfile, now: Date) -> String? {
        guard let u = profiles.limits[p.id], let f = u.effectiveFiveHour(now: now) else { return nil }
        let text = L("5 saat %{0}", percent(f))
        guard let r = AccountUsage.resetIn(u.fiveHourResetsAt, now: now) else { return text }
        return text + " · " + r
    }

    private var help: String {
        let now = Date()
        let lines = profiles.profiles.map { p -> String in
            var parts = [p.displayName]
            if let u = profiles.limits[p.id] {
                if let f = u.effectiveFiveHour(now: now) { parts.append(L("5 saat %{0}", percent(f))) }
                if let s = u.effectiveSevenDay(now: now) { parts.append(L("hafta %{0}", percent(s))) }
            }
            if profiles.needsWarning(p) { parts.append(L("⚠︎ limite yakın")) }
            if let m = profiles.mismatch(p) { parts.append("⚠︎ " + m) }
            return parts.joined(separator: " · ")
        }
        return (lines + [L("Tıkla: profiller, limitler, giriş.")]).joined(separator: "\n")
    }

    static func askEmail(title: String, current: String?) -> String? {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = L("Bu profilde girişli olması gereken Claude hesabının e-postası (boş bırakılabilir). Farklı bir hesapla girişliyse Agent Workshop uyarır.")
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        f.stringValue = current ?? ""
        f.placeholderString = L("ornek@gmail.com")
        a.accessoryView = f
        a.addButton(withTitle: L("Tamam"))
        a.addButton(withTitle: L("Vazgeç"))
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        return f.stringValue.trimmingCharacters(in: .whitespaces)
    }
}
