import AjanTakipCore
import AppKit
import os

/// Robota tıklanınca oturumun cmux sekmesine geçer. Geçici: 2. aşamada terminal uygulama içine gelince
/// bu dosya (ve Core'daki `ProcessEnv`) kaldırılacak.
enum CmuxLink {
    private static let bundleID = "com.cmuxterm.app"
    private static let bundledCLI = "/Applications/cmux.app/Contents/Resources/bin/cmux"
    private static let log = Logger(subsystem: "com.ajantakip.atolye", category: "cmux")

    @MainActor
    static func focus(pid: Int32) {
        // cmux dışında açılmış oturum: yapılacak bir şey yok.
        guard let ids = ProcessEnv.cmuxIDs(pid: pid) else { return }
        guard let cli = ExecutableLocator.find("cmux", preferred: [bundledCLI],
                                               pathEnv: ProcessInfo.processInfo.environment["PATH"],
                                               isExecutable: FileManager.default.isExecutableFile(atPath:)) else {
            log.error("cmux CLI bulunamadı")
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            run(cli, ["select-workspace", "--workspace", ids.workspace])
            if let surface = ids.surface { run(cli, ["focus-panel", "--panel", surface, "--workspace", ids.workspace]) }
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
            if p.terminationStatus != 0 { log.error("cmux \(args.first ?? "") → \(p.terminationStatus)") }
        } catch {
            log.error("cmux çalıştırılamadı: \(error.localizedDescription)")
        }
    }
}
