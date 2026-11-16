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
        Window("Atölye", id: "atolye") {
            // cmux gibi: solda hep oturum listesi; sağda atölye ya da açık projenin terminalleri.
            HStack(spacing: 0) {
                SessionSidebar(model: model)
                    .frame(width: 250)
                Divider()
                ZStack {
                    SceneView(model: model)
                    if let root = model.openRoom {
                        RoomView(model: model, root: root)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: model.openRoom)
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
        // Terminale tıklanınca o bölme odaklansın (tıklama AppKit görünümüne gider, SwiftUI görmez).
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            if let root = model.openRoom, let hit = e.window?.contentView?.hitTest(e.locationInWindow),
               let id = model.host.terminalID(containing: hit), let pane = model.room(root).paneID(of: .terminal(id)),
               model.room(root).focusedPaneID != pane {
                model.update(root) { $0.focusPane(pane) }
            }
            return e
        }
    }

    private static func handle(_ e: NSEvent, _ model: WorkshopModel) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), !mods.contains(.control) else { return false }
        let key = (e.charactersIgnoringModifiers ?? "").lowercased()
        if key == "0" {
            model.closeRoom()
            return true
        }
        guard let root = model.openRoom else { return false }
        let room = model.room(root)
        let panes = room.panes
        if let n = Int(key), (1...9).contains(n) {
            if n <= panes.count { model.update(root) { $0.focusPane(panes[n - 1].id) } }
            return true
        }
        switch key {
        case "t":
            model.add(mods.contains(.shift) ? .claude : .shell, in: root)
            return true
        case "d":
            model.split(.shell, in: root, edge: mods.contains(.shift) ? .bottom : .right)
            return true
        case "w":
            if let tab = room.focusedPane?.current { model.close(tab, in: root) }
            return true
        default:
            break
        }
        // ⌘[ / ⌘] — Türkçe klavyede aynı fiziksel tuşlar ğ / ü.
        let prev = key == "[" || e.keyCode == 33, next = key == "]" || e.keyCode == 30
        if prev || next {
            model.update(root) { $0.cycleTab(by: next ? 1 : -1) }
            return true
        }
        return false
    }
}
