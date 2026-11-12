import Foundation
import Testing
@testable import AjanTakipCore

private let cmd = "/Users/u/.config/ajantakip/ajantakip-hook.sh"

private func entries(_ s: [String: Any], _ event: String) -> [[String: Any]] {
    ((s["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
}
private func commands(_ s: [String: Any], _ event: String) -> [String] {
    entries(s, event).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
}

@Suite struct HookInstallerTests {
    @Test func installIntoEmpty() {
        let s = HookInstaller.install(into: [:], command: cmd)
        #expect(HookInstaller.events.count == 7)
        for e in HookInstaller.events {
            #expect(commands(s, e) == [cmd], "event \(e)")
        }
        #expect(entries(s, "PreToolUse")[0]["matcher"] as? String == "*")
        #expect(entries(s, "PostToolUse")[0]["matcher"] as? String == "*")
        #expect(entries(s, "Stop")[0]["matcher"] == nil)
        #expect(HookInstaller.isInstalled(s))
        #expect(!HookInstaller.isInstalled([:]))
    }

    @Test func installPreservesExistingHooks() {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "other.sh"]]]]],
        ]
        let s = HookInstaller.install(into: existing, command: cmd)
        #expect(s["model"] as? String == "opus")
        #expect(commands(s, "PreToolUse") == ["other.sh", cmd])
    }

    @Test func installTwiceNoDuplicate() {
        let s = HookInstaller.install(into: HookInstaller.install(into: [:], command: cmd), command: cmd)
        for e in HookInstaller.events { #expect(commands(s, e) == [cmd]) }
    }

    @Test func uninstallRemovesOnlyOurs() {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "other.sh"]]]]],
        ]
        let s = HookInstaller.uninstall(from: HookInstaller.install(into: existing, command: cmd))
        #expect(commands(s, "PreToolUse") == ["other.sh"])
        #expect((s["hooks"] as? [String: Any])?["Stop"] == nil)
        #expect(!HookInstaller.isInstalled(s))
        let empty = HookInstaller.uninstall(from: HookInstaller.install(into: ["model": "opus"], command: cmd))
        #expect(empty["hooks"] == nil)
        #expect(empty["model"] as? String == "opus")
    }

    @Test func installFileBacksUpAndRejectsCorrupt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var comps = DateComponents(year: 2026, month: 11, day: 12, hour: 13, minute: 0, second: 0)
        comps.timeZone = .current
        let now = try #require(Calendar(identifier: .gregorian).date(from: comps))

        // dosya yok → {} gibi davranır, yedek yok
        let missing = dir.appendingPathComponent("a/settings.json")
        try FileManager.default.createDirectory(at: missing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HookInstaller.installFile(at: missing, command: cmd, now: now)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: missing)) as! [String: Any]
        #expect(HookInstaller.isInstalled(written))
        #expect(try FileManager.default.contentsOfDirectory(atPath: missing.deletingLastPathComponent().path) == ["settings.json"])

        // geçerli dosya → yedek
        let valid = dir.appendingPathComponent("settings.json")
        try Data(#"{"model":"opus"}"#.utf8).write(to: valid)
        try HookInstaller.installFile(at: valid, command: cmd, now: now)
        let backup = dir.appendingPathComponent("settings.json.bak-20261112-130000")
        #expect(try Data(contentsOf: backup) == Data(#"{"model":"opus"}"#.utf8))
        try HookInstaller.uninstallFile(at: valid, now: now.addingTimeInterval(1))
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: valid)) as! [String: Any]
        #expect(!HookInstaller.isInstalled(after))
        #expect(after["model"] as? String == "opus")

        // bozuk → hata, dosya değişmez
        let corrupt = dir.appendingPathComponent("bad.json")
        let bytes = Data("{not json".utf8)
        try bytes.write(to: corrupt)
        #expect(throws: HookInstallerError.unreadableSettings) {
            try HookInstaller.installFile(at: corrupt, command: cmd, now: now)
        }
        #expect(try Data(contentsOf: corrupt) == bytes)
    }
}

@Suite struct HookCommandQuotingTests {
    @Test func pathWithSpaceIsSingleQuoted() {
        #expect(HookInstaller.shellQuoted("/Users/Ali Can/.config/ajantakip/ajantakip-hook.sh")
                == "'/Users/Ali Can/.config/ajantakip/ajantakip-hook.sh'")
    }

    @Test func embeddedSingleQuoteEscaped() {
        #expect(HookInstaller.shellQuoted("/a'b/x.sh") == #"'/a'\''b/x.sh'"#)
    }

    @Test func quotedCommandStillRecognizedAsOurs() {
        let s = HookInstaller.install(into: [:], command: HookInstaller.shellQuoted("/Users/A B/ajantakip-hook.sh"))
        #expect(HookInstaller.isInstalled(s))
        #expect(!HookInstaller.isInstalled(HookInstaller.uninstall(from: s)))
    }
}
