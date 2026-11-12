import AjanTakipCore
import AppKit
import os

/// Bir oturumun cmux workspace'ine ve sekmesine geçer.
enum CmuxNavigator {
    static let bundleID = "com.cmuxterm.app"
    private static let bundledCLI = "/Applications/cmux.app/Contents/Resources/bin/cmux"
    private static let log = Logger(subsystem: "com.ajantakip.app", category: "cmux")

    static func cliPath() -> String? {
        if FileManager.default.isExecutableFile(atPath: bundledCLI) { return bundledCLI }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin"
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/cmux"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
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
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
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
