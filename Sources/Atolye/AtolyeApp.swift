import AtolyeCore
import AppKit
import SwiftUI

@main
struct AtolyeApp: App {
    @State private var model: WorkshopModel = {
        AppLanguage.setUp()
        return WorkshopModel()
    }()

    init() {
        // `swift run` ile paket dışından açılınca da normal pencere uygulaması olsun.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Agent Workshop", id: "atolye") {
            // cmux gibi: solda hep oturum listesi; sağda atölye ya da açık projenin terminalleri.
            HStack(spacing: 0) {
                // Panel ağaçta kalır; genişliği daralırken kendisi sola kayar (yumuşak geçiş).
                let hidden = model.sidebarHidden
                SessionSidebar(model: model)
                    .frame(width: 250)
                    .offset(x: hidden ? -250 : 0)
                    .opacity(hidden ? 0 : 1)
                    .frame(width: hidden ? 0 : 250, alignment: .leading)
                    .clipped()
                    .allowsHitTesting(!hidden)
                    .accessibilityHidden(hidden)
                Divider().opacity(hidden ? 0 : 1)
                VStack(spacing: 0) {
                    WorkshopToolbar(model: model)
                    // Terminaller sahnenin üstünde yüzen pencereler; sahne hep görünür.
                    ZStack {
                        SceneView(model: model)
                        DeskView(model: model)
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 520)
            .environment(\.locale, L10n.locale)
            .ignoresSafeArea()
            .onAppear {
                model.start()
                KeyRouter.install(model)
            }
        }
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)
        // İlk sahne ana penceredir: açılışta ve Dock simgesine tıklanınca o açılır.
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(after: .appSettings) {
                LanguageMenu()
                Button(L("Claude Code entegrasyonu…")) { model.askIntegration() }
            }
            CommandGroup(before: .windowList) { MainWindowButton() }
            CommandGroup(replacing: .sidebar) {
                Button(model.sidebarHidden ? L("Sol paneli göster") : L("Sol paneli gizle")) { model.toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.control, .command])
            }
            CommandMenu(L("Terminaller")) {
                Button(L("Tüm terminalleri kapat…")) { model.killAllTerminals() }
            }
        }
        // Üst çubuktaki düğmeyle açılan kişisel GitHub panosu (açılışta gösterilmez).
        Window("GitHub", id: "github") {
            GitHubWindow(github: model.github)
                .environment(\.locale, L10n.locale)
        }
        .defaultSize(width: 900, height: 680)
        .defaultLaunchBehavior(.suppressed)
        // Robot havuzu: hazır robotlar ve kendi .glb robotları.
        Window(L("Robotlar"), id: "robots") {
            RobotsWindow(model: model)
                .environment(\.locale, L10n.locale)
        }
        .defaultSize(width: 520, height: 560)
        .defaultLaunchBehavior(.suppressed)
        // Projelerin TODO.local.md maddeleri.
        Window(L("Yapılacaklar"), id: "todos") {
            TodoWindow(model: model)
                .environment(\.locale, L10n.locale)
        }
        .defaultSize(width: 820, height: 560)
        .defaultLaunchBehavior(.suppressed)
        // Projelerin RUN.local.json çalıştırma kartları.
        Window(L("Çalıştırma kartları"), id: "runs") {
            RunCardsWindow(model: model)
                .environment(\.locale, L10n.locale)
        }
        .defaultSize(width: 860, height: 520)
        .defaultLaunchBehavior(.suppressed)
        // Günlük token kullanımı (üst çubuktaki "Bugün" çipinden).
        Window(L("Kullanım"), id: "usage") {
            UsageWindow(model: model)
                .environment(\.locale, L10n.locale)
        }
        .defaultSize(width: 920, height: 520)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// Pencere menüsünde ana pencereyi yeniden açan öğe (kapatıldıysa).
private struct MainWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Agent Workshop") { openWindow(id: "atolye") }.keyboardShortcut("0")
    }
}

/// Atölye kısayolları: yalnız ⌘ ile; geri kalan her tuş (Esc dahil) terminale gider.
@MainActor
enum KeyRouter {
    private static var monitor: Any?

    private static var clickMonitor: Any?

    static func install(_ model: WorkshopModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            handle(e, model) ? nil : e
        }
        // Terminale tıklanınca penceresi öne gelsin (tıklama AppKit görünümüne gider, SwiftUI görmez).
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            if let hit = e.window?.contentView?.hitTest(e.locationInWindow),
               let id = model.host.terminalID(containing: hit), let w = model.desk.window(of: .terminal(id)),
               model.desk.front?.id != w.id {
                model.changeDesk { $0.raise(w.id) }
            }
            return e
        }
    }

    private static func handle(_ e: NSEvent, _ model: WorkshopModel) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), !mods.contains(.control) else { return false }
        let key = (e.charactersIgnoringModifiers ?? "").lowercased()
        let desk = model.desk
        let visible = desk.windows.filter { !$0.minimized }
        if let n = Int(key), (1...9).contains(n) {
            if n <= visible.count { model.changeDesk { $0.raise(visible[n - 1].id) } }
            return true
        }
        switch key {
        case "t":
            guard let root = model.frontRoot ?? model.snapshot?.zones.first?.id else { return false }
            model.newWindow(mods.contains(.shift) ? .claude : .shell, in: root)
            return true
        case "w":
            guard let w = desk.front else { return false }
            model.closeWindow(w.id)
            return true
        case "m":
            guard let w = desk.front else { return false }
            model.tuck([w.id])
            return true
        default:
            break
        }
        // ⌘` ya da ⌘[ / ⌘] (Türkçe klavyede ğ / ü): pencereler arasında geç.
        let prev = key == "[" || e.keyCode == 33, next = key == "]" || e.keyCode == 30 || e.keyCode == 50
        if (prev || next) && visible.count > 1 {
            model.changeDesk { $0.cycle(by: next ? 1 : -1) }
            return true
        }
        return false
    }
}
