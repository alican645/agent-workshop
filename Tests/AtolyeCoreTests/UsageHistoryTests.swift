import Foundation
import Testing
@testable import AtolyeCore

@Suite struct UsageHistoryTests {
    @Test func mergeKeepsLargerDay() {
        // Kayıtlar silinince hesaplanan gün küçülür; saklanan kalır. Yeni günler eklenir, büyüyen gün güncellenir.
        let stored = ["2026-10-01": DailyUsage(tokens: 500, cost: 5), "2026-11-17": DailyUsage(tokens: 10, cost: 0.1)]
        let computed = ["2026-10-01": DailyUsage(tokens: 100, cost: 1), "2026-11-17": DailyUsage(tokens: 40, cost: 0.4),
                        "2026-11-18": DailyUsage(tokens: 7, cost: 0.07)]
        let m = UsageHistory.merge(stored: stored, computed: computed)
        #expect(m == ["2026-10-01": DailyUsage(tokens: 500, cost: 5), "2026-11-17": DailyUsage(tokens: 40, cost: 0.4),
                      "2026-11-18": DailyUsage(tokens: 7, cost: 0.07)])
    }

    @Test func yearEndsTodayAndFillsGaps() {
        let days = UsageHistory.year(["2026-11-16": DailyUsage(tokens: 3, cost: 0)], today: "2026-11-18")
        #expect(days.count == 365)
        #expect(days.last == ContributionDay(date: "2026-11-18", count: 0))
        #expect(days[days.count - 3] == ContributionDay(date: "2026-11-16", count: 3))
        #expect(days.first?.date == "2025-11-19")
    }

    @Test func summary() {
        let d: [String: DailyUsage] = [
            "2026-10-31": DailyUsage(tokens: 900, cost: 9),
            "2026-11-01": DailyUsage(tokens: 100, cost: 1),
            "2026-11-12": DailyUsage(tokens: 50, cost: 0.5),
            "2026-11-17": DailyUsage(tokens: 20, cost: 0.2),
            "2026-11-18": DailyUsage(tokens: 30, cost: 0.3),
        ]
        let s = UsageSummary(days: d, today: "2026-11-18")
        #expect(s.today == DailyUsage(tokens: 30, cost: 0.3))
        #expect(s.lastSevenDays.tokens == 100)          // 12, 17, 18
        #expect(s.thisMonth.tokens == 200)              // kasım
        #expect(s.busiest?.date == "2026-10-31")
        #expect(s.busiest?.usage.tokens == 900)
        #expect(s.currentStreak == 2)
        #expect(s.longestStreak == 2)
        #expect(s.firstDay == "2026-10-31")
        #expect(s.yearTokens == 1100)
    }

    @Test func emptySummary() {
        let s = UsageSummary(days: [:], today: "2026-11-18")
        #expect(s.today.tokens == 0 && s.busiest == nil && s.firstDay == nil && s.currentStreak == 0)
    }

    @Test func storeRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).json")
        #expect(UsageHistory.load(from: url) == [:])
        let d = ["2026-11-18": DailyUsage(tokens: 12, cost: 0.5)]
        try UsageHistory.save(d, to: url)
        #expect(UsageHistory.load(from: url) == d)
    }
}

@Suite struct SessionUsageByDayTests {
    @Test func groupsTokensAndCostByLocalDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        var s = SessionUsage()
        let d1 = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 23, minute: 30))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 0, minute: 10))!
        s.dated = [(d1, 1.0, 100), (d2, 0.5, 40), (d2, 0.25, 10)]
        #expect(s.byDay(calendar: cal) == ["2026-11-17": DailyUsage(tokens: 100, cost: 1.0),
                                           "2026-11-18": DailyUsage(tokens: 50, cost: 0.75)])
    }
}
