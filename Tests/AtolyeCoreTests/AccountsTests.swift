import Foundation
import Testing
@testable import AtolyeCore

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
        #expect(names == ["CLAUDE.md", "history.jsonl", "plugins", "projects", "settings.json"])
    }
}

@Suite struct ShellSnippetTests {
    let block = "# >>> ajantakip >>>\nX\n# <<< ajantakip <<<\n"

}

@Suite struct ResetCountdownTests {
    func text(_ seconds: TimeInterval) -> String? { AccountUsage.resetIn(now.addingTimeInterval(seconds), now: now) }

    @Test func formatsRemainingTime() {
        #expect(text(30) == "1 dk")
        #expect(text(45 * 60) == "45 dk")
        #expect(text(2 * 3600) == "2 sa")
        #expect(text(2 * 3600 + 10 * 60) == "2 sa 10 dk")
        #expect(text(3 * 86400) == "3 gün")
        #expect(text(3 * 86400 + 4 * 3600 + 59 * 60) == "3 gün 4 sa")
    }

    @Test func pastOrUnknownIsNil() {
        #expect(text(0) == nil)
        #expect(text(-60) == nil)
        #expect(AccountUsage.resetIn(nil, now: now) == nil)
    }
}
