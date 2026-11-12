import AjanTakipCore
import AppKit
import SwiftUI

@main
struct AjanTakipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("AjanTakip", systemImage: "capsule.fill") {
            MenuBarContent(model: delegate.model)
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
        if model.pillVisible { panel.orderFrontRegardless() }
        self.panel = panel
        HookSetup.refresh(model: model)

        startServer()
        model.startPruneTimer()
        installCollapseMonitors()
    }

    /// Liste açıkken: başka bir yere tıklamak veya Esc listeyi kapatır.
    private func installCollapseMonitors() {
        let model = model
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated {
                if model.isExpanded { model.isExpanded = false }
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, model.isExpanded {  // Esc
                model.isExpanded = false
                return nil
            }
            return event
        }
        observeUIState()
    }

    /// Liste açılınca paneli key yap (Esc için); "Hapı göster" ayarını panele uygula.
    private func observeUIState() {
        withObservationTracking {
            _ = model.isExpanded
            _ = model.pillVisible
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.panel?.allowsKey = self.model.isExpanded
                if self.model.pillVisible {
                    self.panel?.orderFrontRegardless()
                    if self.model.isExpanded {
                        self.panel?.makeKey()
                    } else if self.panel?.isKeyWindow == true {
                        self.panel?.resignKey()
                    }
                } else {
                    self.model.isExpanded = false
                    self.panel?.orderOut(nil)
                }
                self.observeUIState()
            }
        }
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
