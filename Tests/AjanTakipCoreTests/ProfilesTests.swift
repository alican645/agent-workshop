import Foundation
import Testing
@testable import AjanTakipCore

private func tmp() throws -> String {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("prof-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
    return d
}

@Suite struct ProfileStoreTests {
    @Test func numberedProfilesAndEnvironment() throws {
        var s = AccountStore(home: "/h")
        let p2 = s.addProfile(email: "b@x.com")
        let p3 = s.addProfile(email: nil)
        #expect(p2.id == "profil-2" && p2.name == "Profil 2" && p2.configDir == "/h/.claude-profiles/profil-2")
        #expect(p2.email == "b@x.com" && p3.id == "profil-3")
        #expect(s.globalConfigPath(AccountStore.defaultID) == "/h/.claude.json")
        #expect(s.globalConfigPath("profil-2") == "/h/.claude-profiles/profil-2/.claude.json")
        #expect(s.environment("default") == [:])
        #expect(s.environment("profil-3") == ["CLAUDE_CONFIG_DIR": "/h/.claude-profiles/profil-3"])
        s.removeProfile(id: "profil-2")
        #expect(s.addProfile(email: nil).id == "profil-2")
    }

    @Test func decodesProfilesWithoutEmail() throws {
        let old = #"{"home":"/h","activeID":"p","profiles":[{"id":"p","name":"P","configDir":"/c"}]}"#
        let s = try JSONDecoder().decode(AccountStore.self, from: Data(old.utf8))
        #expect(s.profiles[0].email == nil)
    }
}

@Suite struct ProfileLinkTests {
    @Test func linksSharedItemsAndMergesHistory() throws {
        let root = try tmp(), main = root + "/main", prof = root + "/p2"
        let fm = FileManager.default
        for d in [main + "/skills", main + "/file-history/s1", main + "/sessions", prof + "/file-history/s2"] {
            try fm.createDirectory(atPath: d, withIntermediateDirectories: true)
        }
        try "{}".write(toFile: main + "/settings.json", atomically: true, encoding: .utf8)
        try "A\nB\n".write(toFile: main + "/history.jsonl", atomically: true, encoding: .utf8)
        try "B\nC\n".write(toFile: prof + "/history.jsonl", atomically: true, encoding: .utf8)
        try "x".write(toFile: prof + "/file-history/s2/f", atomically: true, encoding: .utf8)

        let changed = try ProfileLinker.link(profileDir: prof, mainDir: main)
        #expect(changed.sorted() == ["file-history", "history.jsonl", "settings.json", "skills"])
        for name in changed { #expect(try fm.destinationOfSymbolicLink(atPath: prof + "/" + name) == main + "/" + name) }
        #expect(try String(contentsOfFile: main + "/history.jsonl", encoding: .utf8) == "A\nB\nC\n")
        #expect(fm.fileExists(atPath: main + "/file-history/s2/f"))
        #expect(!fm.fileExists(atPath: prof + "/sessions"))
        #expect(fm.fileExists(atPath: prof + "/" + ProfileLinker.backupDir + "/history.jsonl"))
        #expect(try ProfileLinker.link(profileDir: prof, mainDir: main).isEmpty)
    }
}

@Suite struct ConfigSyncTests {
    private func j(_ s: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any]
    }

    @Test func firstSyncIsUnionAndKeepsAccount() {
        let a = j(#"{"oauthAccount":{"emailAddress":"a"},"mcpServers":{"x":{"command":"x"}},"projects":{"/p":{"allowedTools":["Bash"],"lastCost":1,"hasTrustDialogAccepted":true}}}"#)
        let b = j(#"{"oauthAccount":{"emailAddress":"b"},"mcpServers":{"y":{"command":"y"}},"projects":{}}"#)
        let r = ConfigSync.sync(configs: [a, b], base: nil)
        let nb = r.configs[1]
        #expect((nb["oauthAccount"] as? [String: Any])?["emailAddress"] as? String == "b")
        #expect(Set(((nb["mcpServers"] as? [String: Any]) ?? [:]).keys) == ["x", "y"])
        let p = (nb["projects"] as? [String: Any])?["/p"] as? [String: Any]
        #expect(p?["allowedTools"] as? [String] == ["Bash"] && p?["hasTrustDialogAccepted"] as? Bool == true)
        #expect(p?["lastCost"] != nil) // eksik proje kaydı diğer profilden kopyalanır
        #expect(r.changed == [true, true])
    }

    @Test func removalAndLatestChangePropagate() {
        let start = ConfigSync.sync(configs: [j(#"{"mcpServers":{"x":{"v":1},"z":{"v":1}},"projects":{"/p":{"allowedTools":["A","B"]}}}"#),
                                              j(#"{}"#)], base: nil)
        var a = start.configs[0], b = start.configs[1]
        a["mcpServers"] = ["z": ["v": 1]]                          // a: x'i sildi
        var pb = (b["projects"] as! [String: Any])["/p"] as! [String: Any]
        pb["allowedTools"] = ["A", "B", "C"]                        // b: C'yi ekledi
        b["projects"] = ["/p": pb]
        var bm = b["mcpServers"] as! [String: Any]; bm["z"] = ["v": 2]; b["mcpServers"] = bm // b: z'yi değiştirdi
        let r = ConfigSync.sync(configs: [a, b], base: start.base)
        for c in r.configs {
            #expect(Set(((c["mcpServers"] as? [String: Any]) ?? [:]).keys) == ["z"])
            #expect(((c["mcpServers"] as? [String: Any])?["z"] as? [String: Any])?["v"] as? Int == 2)
            #expect(((c["projects"] as? [String: Any])?["/p"] as? [String: Any])?["allowedTools"] as? [String] == ["A", "B", "C"])
        }
        #expect(r.changed == [true, true]) // a: z ve C gelir; b: x gider
    }

    @Test func runnerSkipsLockedAndWritesFiles() throws {
        let d = try tmp()
        let a = d + "/a.json", b = d + "/b.json", base = d + "/base.json"
        try #"{"mcpServers":{"x":{"command":"x"}}}"#.write(toFile: a, atomically: true, encoding: .utf8)
        try #"{"numStartups":3}"#.write(toFile: b, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: b + ".lock", withIntermediateDirectories: true)
        #expect(ConfigSync.run(files: [a, b], baseFile: base, backupDir: d + "/yedek") == nil)
        try FileManager.default.removeItem(atPath: b + ".lock")
        #expect(ConfigSync.run(files: [a, b], baseFile: base, backupDir: d + "/yedek") == [b])
        let nb = j(try String(contentsOfFile: b, encoding: .utf8))
        #expect((nb["mcpServers"] as? [String: Any])?["x"] != nil && nb["numStartups"] as? Int == 3)
        #expect(ConfigSync.run(files: [a, b], baseFile: base, backupDir: d + "/yedek") == [])
        #expect(try FileManager.default.contentsOfDirectory(atPath: d + "/yedek").count == 1)
    }
}

@Suite struct AtolyeIntegrationTests {
    @Test func statuslineBlockReplacesAjanTakip() {
        let old = "echo hi\n# >>> ajantakip >>>\ncurl x\n# <<< ajantakip <<<\n"
        let once = AtolyeIntegration.installStatusline(into: old)
        #expect(!once.contains("ajantakip") && once.contains("# >>> atolye >>>") && once.hasPrefix("echo hi\n"))
        #expect(AtolyeIntegration.installStatusline(into: once) == once)
    }

    @Test func limitFileNameMatchesShellMapping() {
        #expect(AtolyeIntegration.limitFileName(configDir: "/Users/a/.claude-profiles/p 2/") == "_Users_a_.claude-profiles_p_2.json")
    }

    @Test func removesOnlyAjanTakipHooks() throws {
        let s = #"{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"'/h/.config/ajantakip/ajantakip-hook.sh'"}]}],"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"'/h/.config/ajantakip/ajantakip-hook.sh'"},{"type":"command","command":"my.sh"}]}]}}"#
        let o = try #require(AtolyeIntegration.removingAjanTakipHooks(Data(s.utf8)))
        let obj = try JSONSerialization.jsonObject(with: o) as! [String: Any]
        let hooks = obj["hooks"] as! [String: Any]
        #expect(hooks["Stop"] == nil && obj["model"] as? String == "x")
        let pre = hooks["PreToolUse"] as! [[String: Any]]
        #expect((pre[0]["hooks"] as! [[String: Any]]).count == 1)
        #expect(AtolyeIntegration.removingAjanTakipHooks(o) == nil) // değişiklik yoksa nil
    }

    @Test func readsLimitFile() throws {
        let d = try tmp()
        let f = d + "/x.json"
        try #"{"five_hour":{"used_percentage":92,"resets_at":4102444800},"seven_day":{"used_percentage":40}}"#
            .write(toFile: f, atomically: true, encoding: .utf8)
        let u = try #require(AtolyeIntegration.readLimits(path: f))
        #expect(u.fiveHour == 0.92 && u.sevenDay == 0.4)
        #expect(AccountStore.needsWarning(u, now: Date()))
    }
}
