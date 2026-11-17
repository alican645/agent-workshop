import AjanTakipCore
import AppKit
import ServiceManagement
import SwiftUI

struct MenuBarContent: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if let error = model.serverError {
            Text("⚠︎ \(error)")
            Divider()
        }
        Toggle("Ses", isOn: $model.soundEnabled)
        Toggle("Hapı göster", isOn: $model.pillVisible)
        Toggle("Sistem kullanımını göster", isOn: $model.showSystemStats)
        Divider()
        Button(model.hooksInstalled ? "Hook'ları kaldır" : "Hook'ları kur") {
            HookSetup.toggle(model: model)
        }
        Menu("Claude hesapları") {
            ForEach(model.accounts.store.profiles) { p in
                Menu((model.accounts.store.activeID == p.id ? "● " : "") + model.accounts.label(p)) {
                    Button("Aktif yap") { model.accounts.setActive(p.id) }
                    Button("Giriş yap…") { model.accounts.openLogin(p) }
                    if p.id != AccountStore.defaultID {
                        Button("Listeden kaldır") { model.accounts.removeProfile(p.id) }
                    }
                }
            }
            Divider()
            Button("Hesap ekle…") { AccountSetup.add(model: model) }
            Button("Giriş durumunu yenile") { model.accounts.refreshAuth() }
            Divider()
            Button(model.accounts.integrationInstalled ? "Kabuk entegrasyonunu kaldır" : "Kabuk entegrasyonunu kur") {
                AccountSetup.toggleIntegration(model: model)
            }
        }
        Toggle("Girişte başlat", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    HookSetup.showError("Girişte başlatma ayarlanamadı: \(error.localizedDescription)")
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        Divider()
        Button("Çıkış") { NSApp.terminate(nil) }
    }
}

/// Hook script'ini ~/.config/ajantakip altına kopyalar ve ~/.claude/settings.json'a ekler/çıkarır.
@MainActor
enum HookSetup {
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    static var scriptURL: URL { home.appendingPathComponent(".config/ajantakip/ajantakip-hook.sh") }

    static func refresh(model: AppModel) {
        model.hooksInstalled = (try? HookInstaller.readFile(at: settingsURL)).map(HookInstaller.isInstalled) ?? false
    }

    static func toggle(model: AppModel) {
        do {
            if model.hooksInstalled {
                try HookInstaller.uninstallFile(at: settingsURL, now: .now)
            } else {
                try installScript()
                try FileManager.default.createDirectory(
                    at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try HookInstaller.installFile(at: settingsURL, command: HookInstaller.shellQuoted(scriptURL.path),
                                              now: .now)
                refresh(model: model)
                showInfo("Hook'lar kuruldu.",
                         "Açık olan Claude Code oturumları yeni hook'ları görmez. Takip edilmeleri için o oturumları kapatıp yeniden başlat; yeni açılan oturumlar otomatik takip edilir.")
            }
        } catch HookInstallerError.unreadableSettings {
            showError("~/.claude/settings.json okunamadı veya geçerli JSON değil. Dosyaya dokunulmadı.")
        } catch {
            showError("Hook kurulumu başarısız: \(error.localizedDescription)")
        }
        refresh(model: model)
    }

    private static func installScript() throws {
        guard let source = Bundle.main.url(forResource: "ajantakip-hook", withExtension: "sh") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: scriptURL.path) { try fm.removeItem(at: scriptURL) }
        try fm.copyItem(at: source, to: scriptURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    static func showInfo(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    static func showError(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "AjanTakip"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// Hesap ekleme ve kabuk entegrasyonu diyalogları.
@MainActor
enum AccountSetup {
    static func add(model: AppModel) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Claude hesabı ekle"
        alert.informativeText = "Profil için bir ad gir (ör. \"iş\"). Ardından cmux'ta yeni bir sekmede giriş açılır; tarayıcıda claude.ai ile giriş yaparsın. AjanTakip şifreni görmez."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Profil adı"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Ekle ve giriş yap")
        alert.addButton(withTitle: "Vazgeç")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let p = try model.accounts.addProfile(name: field.stringValue)
            model.accounts.openLogin(p)
            if !model.accounts.integrationInstalled {
                HookSetup.showInfo("Profil eklendi.",
                    "Hesapların kullanımını görmek ve aktif hesabı seçmek için menüden \"Kabuk entegrasyonunu kur\" seçeneğini de kullan.")
            }
        } catch AccountError.emptyName {
            HookSetup.showError("Profil adı boş olamaz.")
        } catch AccountError.duplicateName {
            HookSetup.showError("Bu adda bir profil zaten var.")
        } catch {
            HookSetup.showError("Profil oluşturulamadı: \(error.localizedDescription)")
        }
    }

    static func toggleIntegration(model: AppModel) {
        let installing = !model.accounts.integrationInstalled
        do {
            try model.accounts.toggleIntegration(port: AppModel.configuredPort())
            if installing {
                HookSetup.showInfo("Kabuk entegrasyonu kuruldu.",
                    "~/.zshrc ve ~/.claude/statusline-command.sh dosyalarının yedeği alındı. Yeni açılan terminallerde `claude`, haptan seçtiğin hesapla başlar; açık terminallerde `source ~/.zshrc` çalıştır.")
            }
        } catch {
            HookSetup.showError("Kabuk dosyaları güncellenemedi: \(error.localizedDescription)")
        }
    }
}
