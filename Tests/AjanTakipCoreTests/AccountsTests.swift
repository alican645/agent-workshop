import Foundation
import Testing
@testable import AjanTakipCore

private let home = "/Users/u"
private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct UsageReportTests {
    @Test func parsesRateLimitsAndConfigDir() throws {
        let body = #"{"five_hour":{"used_percentage":72.5,"resets_at":1800003600},"seven_day":{"used_percentage":59,"resets_at":1800300000}}"#
        let r = try #require(UsageReport.parse(body: Data(body.utf8), headers: ["x-claude-config-dir": "/Users/u/.claude-profiles/is"], now: now))
        #expect(r.configDir == "/Users/u/.claude-profiles/is")
        #expect(r.usage.fiveHour == 0.725)
        #expect(r.usage.fiveHourResetsAt == Date(timeIntervalSince1970: 1_800_003_600))
        #expect(r.usage.sevenDay == 0.59)
        #expect(r.usage.reportedAt == now)
    }

    @Test func emptyConfigDirHeaderMeansDefault() throws {
        let r = try #require(UsageReport.parse(body: Data(#"{"five_hour":{"used_percentage":1}}"#.utf8), headers: ["x-claude-config-dir": ""], now: now))
        #expect(r.configDir == nil)
    }

    @Test func missingRateLimitsIsNil() {
        #expect(UsageReport.parse(body: Data("{}".utf8), headers: [:], now: now) == nil)
        #expect(UsageReport.parse(body: Data("null".utf8), headers: [:], now: now) == nil)
    }
}

@Suite struct AccountUsageTests {
    @Test func resetPassedMeansZero() {
        let u = AccountUsage(fiveHour: 0.9, fiveHourResetsAt: now.addingTimeInterval(-1),
                             sevenDay: 0.5, sevenDayResetsAt: now.addingTimeInterval(100), reportedAt: now)
        #expect(u.effectiveFiveHour(now: now) == 0)
        #expect(u.effectiveSevenDay(now: now) == 0.5)
    }
}

@Suite struct AccountStoreTests {
    @Test func defaultProfileAlwaysPresent() {
        let s = AccountStore(home: home)
        #expect(s.profiles.map(\.id) == ["default"])
        #expect(s.activeID == "default")
        #expect(s.profiles[0].configDir == "/Users/u/.claude")
    }

    @Test func addProfileSlugifiesAndDedupes() throws {
        var s = AccountStore(home: home)
        let p = try s.addProfile(name: "İş Hesabı")
        #expect(p.id == "is-hesabi")
        #expect(p.configDir == "/Users/u/.claude-profiles/is-hesabi")
        #expect(throws: AccountError.duplicateName) { try s.addProfile(name: "iş hesabı") }
        #expect(throws: AccountError.emptyName) { try s.addProfile(name: "  ") }
    }

    @Test func profileForConfigDir() throws {
        var s = AccountStore(home: home)
        let p = try s.addProfile(name: "ikinci")
        #expect(s.profileID(forConfigDir: nil) == "default")
        #expect(s.profileID(forConfigDir: "/Users/u/.claude") == "default")
        #expect(s.profileID(forConfigDir: "/Users/u/.claude/") == "default")
        #expect(s.profileID(forConfigDir: p.configDir) == "ikinci")
        #expect(s.profileID(forConfigDir: "/elsewhere") == nil)
    }

    @Test func activeConfigDirForShell() throws {
        var s = AccountStore(home: home)
        let p = try s.addProfile(name: "ikinci")
        #expect(s.activeConfigDirForShell == "")
        s.activeID = p.id
        #expect(s.activeConfigDirForShell == p.configDir)
    }

    @Test func removeProfileResetsActive() throws {
        var s = AccountStore(home: home)
        let p = try s.addProfile(name: "ikinci")
        s.activeID = p.id
        s.removeProfile(id: p.id)
        #expect(s.activeID == "default")
        s.removeProfile(id: "default")
        #expect(s.profiles.count == 1)
    }

    @Test func codableRoundTrip() throws {
        var s = AccountStore(home: home)
        _ = try s.addProfile(name: "ikinci")
        s.activeID = "ikinci"
        let back = try JSONDecoder().decode(AccountStore.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func warningOnlyForActiveAtThreshold() {
        let high = AccountUsage(fiveHour: 0.9, fiveHourResetsAt: now.addingTimeInterval(60), sevenDay: nil, sevenDayResetsAt: nil, reportedAt: now)
        let low = AccountUsage(fiveHour: 0.89, fiveHourResetsAt: now.addingTimeInterval(60), sevenDay: nil, sevenDayResetsAt: nil, reportedAt: now)
        #expect(AccountStore.needsWarning(high, now: now))
        #expect(!AccountStore.needsWarning(low, now: now))
        let weekly = AccountUsage(fiveHour: 0.1, fiveHourResetsAt: nil, sevenDay: 0.95, sevenDayResetsAt: now.addingTimeInterval(60), reportedAt: now)
        #expect(AccountStore.needsWarning(weekly, now: now))
    }
}

@Suite struct ProfileLinkerTests {
    @Test func linksOnlySharedItemsThatExist() {
        let names = ProfileLinker.sharedItems(existingIn: ["settings.json", "CLAUDE.md", "plugins", "history.jsonl", ".credentials.json", "projects"])
        #expect(names == ["CLAUDE.md", "plugins", "projects", "settings.json"])
    }
}

@Suite struct ShellSnippetTests {
    let block = "# >>> ajantakip >>>\nX\n# <<< ajantakip <<<\n"

    @Test func insertAppendsOnce() {
        let once = ShellSnippet.insert(block, into: "export A=1\n")
        #expect(once == "export A=1\n\n" + block)
        #expect(ShellSnippet.insert(block, into: once) == once)
    }

    @Test func insertReplacesOldBlock() {
        let old = "a\n# >>> ajantakip >>>\nOLD\n# <<< ajantakip <<<\nb\n"
        #expect(ShellSnippet.insert(block, into: old) == "a\n" + block + "b\n")
    }

    @Test func removeDeletesBlockOnly() {
        #expect(ShellSnippet.remove(from: "a\n\n" + block) == "a\n")
        #expect(ShellSnippet.remove(from: "a\n") == "a\n")
    }

    @Test func containsBlock() {
        #expect(ShellSnippet.contains(in: "x\n" + block))
        #expect(!ShellSnippet.contains(in: "x\n"))
    }
}

@Suite struct AccountIntegrationTests {
    @Test func authStatusParse() {
        let s = AuthStatus.parse(Data(#"{"loggedIn":true,"email":"a@b.c","subscriptionType":"max","orgName":"x"}"#.utf8))
        #expect(s == AuthStatus(loggedIn: true, email: "a@b.c", plan: "max"))
        #expect(AuthStatus.parse(Data("garbage".utf8)) == nil)
    }

    @Test func statuslineBlockPostsUsage() {
        let b = AccountIntegration.statuslineBlock(port: 47823)
        #expect(b.hasPrefix(ShellSnippet.begin + "\n"))
        #expect(b.hasSuffix(ShellSnippet.end + "\n"))
        #expect(b.contains("http://127.0.0.1:47823/usage"))
        #expect(b.contains("X-Claude-Config-Dir: ${CLAUDE_CONFIG_DIR:-}"))
        #expect(b.contains(".rate_limits"))
    }

    @Test func zshBlockWrapsClaude() {
        let b = AccountIntegration.zshBlock
        #expect(b.contains("claude() {"))
        #expect(b.contains("command claude"))
        #expect(b.contains(".config/ajantakip/active-profile"))
    }

    @Test func profilesFileListsAllConfigDirs() throws {
        var s = AccountStore(home: home)
        try s.addProfile(name: "İş")
        #expect(s.profilesFileContents == "/Users/u/.claude\n/Users/u/.claude-profiles/is\n")
    }

    /// Gerçek zsh'de bloğu çalıştırır; sahte `claude` her çağrıyı `CFG=<dizin> <argümanlar> stdin=<ilk satır>` olarak loglar.
    private func runZsh(_ script: String, prelude: String = "", profiles: Bool = true, failSecond: Bool = false) throws -> (log: [String], status: Int32, home: String) {
        let fm = FileManager.default
        let h = fm.temporaryDirectory.appendingPathComponent("ajantakip-zsh-\(UUID().uuidString)").path
        let bin = h + "/bin", cfg = h + "/.config/ajantakip"
        try fm.createDirectory(atPath: bin, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: cfg, withIntermediateDirectories: true)
        let fake = """
            #!/bin/sh
            line=""; [ -t 0 ] || read -r line
            echo "CFG=${CLAUDE_CONFIG_DIR:-} $* stdin=$line" >> "\(h)/log"
            \(failSecond ? "[ -n \"$CLAUDE_CONFIG_DIR\" ] && exit 1" : "")
            exit 0
            """
        try fake.write(toFile: bin + "/claude", atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin + "/claude")
        try (h + "/.claude-profiles/is").write(toFile: cfg + "/active-profile", atomically: true, encoding: .utf8)
        if profiles {
            try "\(h)/.claude\n\(h)/.claude-profiles/is\n".write(toFile: cfg + "/profiles", atomically: true, encoding: .utf8)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-f", "-c", prelude + "\n" + AccountIntegration.zshBlock + "\n" + script]
        p.environment = ["HOME": h, "PATH": bin + ":/usr/bin:/bin"]
        p.standardInput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        let log = ((try? String(contentsOfFile: h + "/log", encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
        return (log, p.terminationStatus, h)
    }

    @Test func zshBlockFansOutMcpToAllProfiles() throws {
        let r = try runZsh("claude mcp add x -- y")
        #expect(r.status == 0)
        #expect(r.log == ["CFG= mcp add x -- y stdin=", "CFG=\(r.home)/.claude-profiles/is mcp add x -- y stdin="])
        let rm = try runZsh("claude mcp remove x")
        #expect(rm.log.count == 2)
    }

    @Test func zshBlockRunsProjectScopeOnce() throws {
        for args in ["-s project", "--scope project", "--scope=project"] {
            let r = try runZsh("claude mcp add \(args) x -- y")
            #expect(r.log.count == 1, "\(args)")
        }
    }

    @Test func zshBlockKeepsNormalBehavior() throws {
        let r = try runZsh("claude --version")
        #expect(r.log == ["CFG=\(r.home)/.claude-profiles/is --version stdin="])
        let list = try runZsh("claude mcp list")
        #expect(list.log.count == 1)
        let noFile = try runZsh("claude mcp add x", profiles: false)
        #expect(noFile.log.count == 1)
    }

    @Test func zshBlockContinuesAfterFailureAndReturnsError() throws {
        let r = try runZsh("claude mcp add x", failSecond: true)
        #expect(r.log.count == 2)
        #expect(r.status == 1)
    }

    /// cmux, .zshrc'den sonra ilk istemde (precmd) kendi `claude()` fonksiyonunu kurar; bunu taklit eder.
    private let fakeCmux = """
        autoload -Uz add-zsh-hook
        _cmux_fix_path() { add-zsh-hook -d precmd _cmux_fix_path; claude() { command claude --via-cmux "$@"; } }
        add-zsh-hook precmd _cmux_fix_path
        """
    private let firstPrompt = "for f in $precmd_functions; do $f; done"

    @Test func zshBlockSurvivesCmuxReplacingClaude() throws {
        let r = try runZsh("\(firstPrompt); claude --version", prelude: fakeCmux)
        #expect(r.log == ["CFG=\(r.home)/.claude-profiles/is --via-cmux --version stdin="])
        let mcp = try runZsh("\(firstPrompt); claude mcp add x", prelude: fakeCmux)
        #expect(mcp.log == ["CFG= --via-cmux mcp add x stdin=", "CFG=\(mcp.home)/.claude-profiles/is --via-cmux mcp add x stdin="])
    }

    @Test func zshBlockPromptHookIsHarmlessWithoutCmux() throws {
        let r = try runZsh("\(firstPrompt); \(firstPrompt); claude --version")
        #expect(r.log == ["CFG=\(r.home)/.claude-profiles/is --version stdin="])
    }

    @Test func zshBlockLeavesStdinToClaude() throws {
        let r = try runZsh("print ok | claude mcp add-from-claude-desktop")
        #expect(r.log.first?.hasSuffix("stdin=ok") == true)
    }

    @Test func duplicateEmailDetection() {
        let emails = ["default": "a@b.c", "ikinci": "A@B.C"]
        #expect(AccountIntegration.duplicateOf("ikinci", emails: emails) == "default")
        #expect(AccountIntegration.duplicateOf("default", emails: ["default": "a@b.c", "x": "z@z"]) == nil)
    }
}
