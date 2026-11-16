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
            SceneView(model: model)
                .frame(minWidth: 800, minHeight: 520)
                .ignoresSafeArea()
                .onAppear { model.start() }
        }
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)
    }
}
