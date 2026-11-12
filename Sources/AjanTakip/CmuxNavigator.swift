import AjanTakipCore
import AppKit
import os

/// Bir oturumun cmux workspace'ine ve sekmesine geçer.
enum CmuxNavigator {
    static let bundleID = "com.cmuxterm.app"
    private static let bundledCLI = "/Applications/cmux.app/Contents/Resources/bin/cmux"
    private static let log = Logger(subsystem: "com.ajantakip.app", category: "cmux")

    static func cliPath() -> String? {
        ExecutableLocator.find("cmux", preferred: [bundledCLI],
                               pathEnv: ProcessInfo.processInfo.environment["PATH"],
                               isExecutable: FileManager.default.isExecutableFile(atPath:))
    }

    @MainActor
    static func focus(_ s: Session) {
        activateCmux()
        guard let ws = s.workspace else { return }
        guard let cli = cliPath() else {
            log.error("cmux CLI bulunamadı")
            return
        }
        let surface = s.surface
        DispatchQueue.global(qos: .userInitiated).async {
            run(cli, ["select-workspace", "--workspace", ws])
            if let surface {
                run(cli, ["focus-panel", "--panel", surface, "--workspace", ws])
            }
        }
    }

    @MainActor
    private static func activateCmux() {
        // Erişimsiz (accessory) bir uygulamadan NSRunningApplication.activate() reddedilebilir;
        // openApplication(activates: true) çalışan uygulamayı da öne getirir.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    private static func run(_ cli: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                log.error("cmux \(args.joined(separator: " ")) → \(p.terminationStatus)")
            }
        } catch {
            log.error("cmux çalıştırılamadı: \(error.localizedDescription)")
        }
    }
}
