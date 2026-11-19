import Foundation
import Testing
@testable import AtolyeCore

@Suite struct HookInstallTests {
    private let exe = "/Users/u/Library/Application Support/Atolye/bin/atolye-hook"

    private func parse(_ s: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    private func handlers(_ root: [String: Any], _ event: String) -> [[String: Any]] {
        let groups = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }

    @Test func installsIntoEmptySettings() throws {
        let out = try #require(AtolyeIntegration.installHooks(into: "", executable: exe))
        let root = try parse(out)
        let pr = handlers(root, "PermissionRequest")
        #expect(pr.count == 1)
        #expect(pr[0]["command"] as? String == "\"\(exe)\"")
        #expect(pr[0]["timeout"] as? Int == 86400)
        #expect(handlers(root, "PostToolUse").count == 1 && handlers(root, "PostToolUseFailure").count == 1)
        #expect(handlers(root, "PostToolUse")[0]["timeout"] == nil)
    }

    @Test func keepsUserSettingsAndHooks() throws {
        let user = """
        {"theme":"dark","hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"my-lint"}]}],
         "Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
        """
        let root = try parse(try #require(AtolyeIntegration.installHooks(into: user, executable: exe)))
        #expect(root["theme"] as? String == "dark")
        #expect(handlers(root, "PostToolUse").map { $0["command"] as? String } == ["my-lint", "\"\(exe)\""])
        #expect(handlers(root, "Stop").count == 1)
    }

    @Test func idempotentAndReplacesOldPath() throws {
        let once = try #require(AtolyeIntegration.installHooks(into: "{}", executable: "/old/atolye-hook"))
        let twice = try #require(AtolyeIntegration.installHooks(into: once, executable: exe))
        let again = try #require(AtolyeIntegration.installHooks(into: twice, executable: exe))
        #expect(twice == again)
        let pr = handlers(try parse(twice), "PermissionRequest")
        #expect(pr.count == 1 && pr[0]["command"] as? String == "\"\(exe)\"")
    }

    @Test func uninstallLeavesOthers() throws {
        let user = #"{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"my-lint"}]}]}}"#
        let installed = try #require(AtolyeIntegration.installHooks(into: user, executable: exe))
        let root = try parse(try #require(AtolyeIntegration.uninstallHooks(from: installed)))
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == ["PostToolUse"])
        #expect(handlers(root, "PostToolUse").map { $0["command"] as? String } == ["my-lint"])
        let bare = try parse(try #require(AtolyeIntegration.uninstallHooks(from: AtolyeIntegration.installHooks(into: "{}", executable: exe)!)))
        #expect(bare["hooks"] == nil)
    }

    @Test func refusesBrokenJSON() {
        #expect(AtolyeIntegration.installHooks(into: "{ not json", executable: exe) == nil)
        #expect(AtolyeIntegration.installHooks(into: #"{"hooks":"x"}"#, executable: exe) == nil)
    }
}
