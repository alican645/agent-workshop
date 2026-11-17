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
            Section("Claude oturumları bu profille açılır; açık olanlar kaldıkları yerden sürer") {
                ForEach(profiles.profiles) { p in
                    Button { model.switchProfile(to: p.id) } label: {
                        Text((p.id == active.id ? "✓ " : "    ") + line(p))
                    }
                }
            }
            Divider()
            Menu("Giriş yap") {
                ForEach(profiles.profiles) { p in
                    Button(p.name + (p.email.map { " · \($0)" } ?? "")) { model.login(profile: p.id) }
                }
            }
            Menu("Beklenen hesabı ayarla") {
                ForEach(profiles.profiles) { p in
                    Button(p.name) {
                        if let e = Self.askEmail(title: "\(p.name) hangi hesapla kullanılacak?", current: p.email) {
                            profiles.setEmail(e, for: p.id)
                        }
                    }
                }
            }
            Button("Profil ekle…") {
                guard let e = Self.askEmail(title: "Yeni profil", current: nil) else { return }
                let p = profiles.add(email: e)
                model.login(profile: p.id)
            }
        } label: {
            BarChip(icon: alert ? "exclamationmark.triangle.fill" : "person.crop.circle", title: active.name,
                    detail: profiles.limits[active.id]?.effectiveFiveHour(now: Date()).map { "5 saat %\(Int(($0 * 100).rounded()))" },
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
        var parts = [p.name]
        if let e = profiles.loggedIn[p.id] ?? p.email { parts.append(e) } else { parts.append("giriş yok") }
        let now = Date()
        if let u = profiles.limits[p.id] {
            if let f = u.effectiveFiveHour(now: now) { parts.append("5 saat %\(Int((f * 100).rounded()))") }
            if let s = u.effectiveSevenDay(now: now) { parts.append("hafta %\(Int((s * 100).rounded()))") }
        }
        if profiles.needsWarning(p) { parts.append("⚠︎ limite yakın") }
        if let m = profiles.mismatch(p) { parts.append("⚠︎ " + m) }
        return parts.joined(separator: " · ")
    }

    private var help: String {
        let lines = profiles.profiles.map(line)
        return (lines + ["Skill'ler, MCP'ler, ayarlar, hafıza ve geçmiş bütün profillerde ortak."]).joined(separator: "\n")
    }

    static func askEmail(title: String, current: String?) -> String? {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = "Bu profilde girişli olması gereken Claude hesabının e-postası (boş bırakılabilir). "
            + "Farklı bir hesapla girişliyse Atölye uyarır."
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        f.stringValue = current ?? ""
        f.placeholderString = "ornek@gmail.com"
        a.accessoryView = f
        a.addButton(withTitle: "Tamam")
        a.addButton(withTitle: "Vazgeç")
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        return f.stringValue.trimmingCharacters(in: .whitespaces)
    }
}
