import AjanTakipCore
import AppKit
import SwiftUI

@main
struct AjanTakipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("AjanTakip", systemImage: "capsule.fill") {
            Button("Çıkış") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var panel: PillPanel?
    private var server: EventServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        var panelRef: PillPanel?
        let view = PillView(
            model: model,
            moveWindow: { panelRef?.move(topLeft: $0) },
            windowTopLeft: { panelRef?.topLeft ?? .zero },
            contentSizeChanged: { panelRef?.fit(contentSize: $0) })
        let panel = PillPanel(rootView: view)
        panelRef = panel
        panel.orderFrontRegardless()
        self.panel = panel

        startServer()
        model.startPruneTimer()
    }

    private func startServer() {
        let model = model
        let server = EventServer(port: AppModel.configuredPort()) { event in
            Task { @MainActor in model.handle(event) }
        }
        do {
            try server.start { message in
                Task { @MainActor in model.serverError = message }
            }
            self.server = server
        } catch {
            model.serverError = "Sunucu başlatılamadı: \(error.localizedDescription)"
        }
    }
}
