import AppKit
import AtolyeCore

/// Agent Workshop'un Claude Code ayarlarına eklediği parçalar için kullanıcının seçimi.
struct IntegrationChoice: Equatable {
    /// `~/.claude/settings.json`'a PermissionRequest hook'u: izin ve sorular balondan cevaplanır.
    var hooks: Bool
    /// statusline betiğine limit bloğu: hesap limitleri Atölye'de görünür.
    var statusline: Bool

    private static let key = "integrationChoice"

    /// Kaydedilmiş seçim; hiç sorulmadıysa nil.
    static var saved: IntegrationChoice? {
        guard let d = UserDefaults.standard.dictionary(forKey: key) else { return nil }
        return IntegrationChoice(hooks: d["hooks"] as? Bool ?? false, statusline: d["statusline"] as? Bool ?? false)
    }

    func save() {
        UserDefaults.standard.set(["hooks": hooks, "statusline": statusline], forKey: Self.key)
    }
}

enum IntegrationSetup {
    /// Seçimi soran pencere. "Şimdi değil" ilk açılışta hiçbir şeyi kurmamak demektir (seçim kaydedilir);
    /// sonradan açılan pencerede "Vazgeç" seçimi değiştirmez (nil).
    @MainActor
    static func ask(current: IntegrationChoice?) -> IntegrationChoice? {
        let alert = NSAlert()
        alert.messageText = L("Claude Code entegrasyonu")
        alert.informativeText = L("Agent Workshop, Claude Code ayarlarına iki küçük parça ekleyebilir. Değişen dosyaların aslı önce yedeklenir; istediğin zaman bu menüden kaldırabilirsin.")
        let hooks = NSButton(checkboxWithTitle: L("Balondan cevap: ~/.claude/settings.json'a hook ekle (izinler, sorular ve plan onayları her oturumda balondan cevaplanır)"), target: nil, action: nil)
        let status = NSButton(checkboxWithTitle: L("Limit göstergesi: statusline betiğine hesap limitlerini kaydeden bir blok ekle"), target: nil, action: nil)
        hooks.state = (current?.hooks ?? true) ? .on : .off
        status.state = (current?.statusline ?? true) ? .on : .off
        for b in [hooks, status] {
            b.lineBreakMode = .byWordWrapping
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 380).isActive = true
        }
        let stack = NSStackView(views: [hooks, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.frame = NSRect(x: 0, y: 0, width: 380, height: 90)
        alert.accessoryView = stack
        alert.addButton(withTitle: L("Uygula"))
        alert.addButton(withTitle: current == nil ? L("Şimdi değil") : L("Vazgeç"))
        let r = alert.runModal()
        if r == .alertFirstButtonReturn {
            return IntegrationChoice(hooks: hooks.state == .on, statusline: status.state == .on)
        }
        return current == nil ? IntegrationChoice(hooks: false, statusline: false) : nil
    }
}
