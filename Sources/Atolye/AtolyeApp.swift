import AjanTakipCore
import AppKit
import SwiftUI

@main
struct AtolyeApp: App {
    @State private var model = WorkshopModel()

    init() {
        // `swift run` ile paket dışından açılınca da normal pencere uygulaması olsun.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        // Üst çubuktaki düğmeyle açılan kişisel GitHub panosu (açılışta gösterilmez).
        Window("GitHub", id: "github") {
            GitHubWindow(github: model.github)
        }
        .defaultSize(width: 900, height: 680)
        .defaultLaunchBehavior(.suppressed)
        // Robot havuzu: hazır robotlar ve kendi .glb robotları.
        Window("Robotlar", id: "robots") {
            RobotsWindow(model: model)
        }
        .defaultSize(width: 520, height: 560)
        .defaultLaunchBehavior(.suppressed)
        Window("Atölye", id: "atolye") {
            // cmux gibi: solda hep oturum listesi; sağda atölye ya da açık projenin terminalleri.
            HStack(spacing: 0) {
                SessionSidebar(model: model)
                    .frame(width: 250)
                Divider()
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
            .ignoresSafeArea()
            .onAppear {
                model.start()
                KeyRouter.install(model)
            }
        }
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Terminaller") {
                Button("Tüm terminalleri kapat…") { model.killAllTerminals() }
            }
        }
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
