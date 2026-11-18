import AtolyeCore
import AppKit
import SwiftUI
import WebKit

/// Uygulamanın dili: Sistem / English / Türkçe. Seçim açılışta uygulanır; değişince uygulama yeniden açılır
/// (terminaller arka plandaki yardımcıda yaşadığı için oturumlar kopmaz).
@MainActor
enum AppLanguage {
    static let key = "language"

    static var preference: L10n.Preference {
        L10n.Preference(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    /// Arayüz kurulmadan önce bir kez.
    static func setUp() {
        // Sistem dili: uygulamanın kendi AppleLanguages ayarı değil, Mac'in genel ayarı.
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        let lang = L10n.resolve(preference, preferred: global ?? Locale.preferredLanguages)
        let table = lang == "en" ? L10n.loadTable(SceneView.webRoot().appendingPathComponent("i18n/en.json")) : [:]
        L10n.use(language: lang, table: table)
        // AppKit'in kendi menü ve panelleri de aynı dilde olsun (bir sonraki açılıştan itibaren kesin).
        UserDefaults.standard.set([lang], forKey: "AppleLanguages")
    }

    static func choose(_ p: L10n.Preference) {
        guard p != preference else { return }
        UserDefaults.standard.set(p.rawValue, forKey: key)
        relaunch()
    }

    private static func relaunch() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else {
            let a = NSAlert()
            a.messageText = L("Dil, uygulama yeniden açılınca değişecek.")
            a.runModal()
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// Sahne sayfalarına sözlük: sayfa açılmadan `window.LANG` ve `window.I18N`.
    static var webScript: WKUserScript {
        let json = (try? JSONEncoder().encode(L10n.isEnglish ? L10n.table : [:])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return WKUserScript(source: "window.LANG = '\(L10n.language)'; window.I18N = \(json);",
                            injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }
}

/// Uygulama menüsündeki dil seçimi.
struct LanguageMenu: View {
    var body: some View {
        Menu(L("Dil")) {
            ForEach(L10n.Preference.allCases, id: \.self) { p in
                Button((p == AppLanguage.preference ? "✓ " : "    ") + Self.title(p)) { AppLanguage.choose(p) }
            }
        }
    }

    static func title(_ p: L10n.Preference) -> String {
        switch p {
        case .system: L("Sistem dili")
        case .en: "English"
        case .tr: "Türkçe"
        }
    }
}
