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
            // Atölye hep görünür; açık projenin terminalleri sağdaki yan panelde.
            HSplitView {
                SceneView(model: model)
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                if let root = model.openRoom {
                    RoomView(model: model, root: root)
                        .frame(minWidth: 380, idealWidth: 760, maxWidth: .infinity, maxHeight: .infinity)
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

    static func install(_ model: WorkshopModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            handle(e, model) ? nil : e
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
        if let n = Int(key), (1...9).contains(n) {
            if n <= room.panes.count { model.update(root) { $0.focusedPane = n - 1 } }
            return true
        }
        switch key {
        case "t":
            model.add(mods.contains(.shift) ? .claude : .shell, in: root)
            return true
        case "w":
            let p = room.focusedPane
            if room.panes.indices.contains(p), let tab = room.panes[p].current { model.close(tab, in: root) }
            return true
        default:
            break
        }
        // ⌘[ / ⌘] — Türkçe klavyede aynı fiziksel tuşlar ğ / ü.
        let prev = key == "[" || e.keyCode == 33, next = key == "]" || e.keyCode == 30
        if prev || next {
            let p = room.focusedPane
            guard room.panes.indices.contains(p), room.panes[p].tabs.count > 1 else { return true }
            let n = room.panes[p].tabs.count
            model.update(root) { $0.panes[p].selected = ($0.panes[p].selected + (next ? 1 : n - 1)) % n }
            return true
        }
        return false
    }
}
