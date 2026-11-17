import AtolyeCore
import AppKit
import SwiftUI

/// Üst çubuktaki hesap menüsü: etkin profil, limitler, giriş ve yeni profil.
struct ProfileMenu: View {
    let model: WorkshopModel
    private var profiles: Profiles { model.profiles }

    var body: some View {
        let active = profiles.active
        let alert = profiles.profiles.contains { profiles.needsWarning($0) || profiles.mismatch($0) != nil }
        Menu {
            Section(L("Claude oturumları bu profille açılır; açık olanlar kaldıkları yerden sürer")) {
                ForEach(profiles.profiles) { p in
                    Button { model.switchProfile(to: p.id) } label: {
                        Text((p.id == active.id ? "✓ " : "    ") + line(p))
                    }
                }
            }
            Divider()
            Menu(L("Giriş yap")) {
                ForEach(profiles.profiles) { p in
                    Button(p.displayName + (p.email.map { " · \($0)" } ?? "")) { model.login(profile: p.id) }
                }
            }
            Menu(L("Beklenen hesabı ayarla")) {
                ForEach(profiles.profiles) { p in
                    Button(p.displayName) {
                        if let e = Self.askEmail(title: L("{0} hangi hesapla kullanılacak?", p.displayName), current: p.email) {
                            profiles.setEmail(e, for: p.id)
                        }
                    }
                }
            }
            Button(L("Profil ekle…")) {
                guard let e = Self.askEmail(title: L("Yeni profil"), current: nil) else { return }
                let p = profiles.add(email: e)
                model.login(profile: p.id)
            }
        } label: {
            BarChip(icon: alert ? "exclamationmark.triangle.fill" : "person.crop.circle", title: active.displayName,
                    detail: profiles.limits[active.id]?.effectiveFiveHour(now: Date()).map { L("5 saat %{0}", "\(Int(($0 * 100).rounded()))") },
                    tint: alert ? .orange : nil)
        }
        // Düz stil: macOS'un menü stili etiketin rengini soldurmasın.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }

    private func line(_ p: AccountProfile) -> String {
        var parts = [p.displayName]
        if let e = profiles.loggedIn[p.id] ?? p.email { parts.append(e) } else { parts.append(L("giriş yok")) }
        let now = Date()
        if let u = profiles.limits[p.id] {
            if let f = u.effectiveFiveHour(now: now) { parts.append(L("5 saat %{0}", "\(Int((f * 100).rounded()))")) }
            if let s = u.effectiveSevenDay(now: now) { parts.append(L("hafta %{0}", "\(Int((s * 100).rounded()))")) }
        }
        if profiles.needsWarning(p) { parts.append(L("⚠︎ limite yakın")) }
        if let m = profiles.mismatch(p) { parts.append("⚠︎ " + m) }
        return parts.joined(separator: " · ")
    }

    private var help: String {
        let lines = profiles.profiles.map(line)
        return (lines + [L("Skill'ler, MCP'ler, ayarlar, hafıza ve geçmiş bütün profillerde ortak.")]).joined(separator: "\n")
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
