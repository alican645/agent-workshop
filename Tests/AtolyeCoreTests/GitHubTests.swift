import Foundation
import Testing
@testable import AtolyeCore

@Suite struct GitHubDeviceFlowTests {
    @Test func parsesDeviceCode() throws {
        let d = Data(#"{"device_code":"dc","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":899,"interval":5}"#.utf8)
        let c = try #require(GitHubDeviceCode.parse(d))
        #expect(c.deviceCode == "dc" && c.userCode == "ABCD-1234" && c.interval == 5 && c.expiresIn == 899)
        #expect(c.verificationURI.absoluteString == "https://github.com/login/device")
    }

    @Test func parsesTokenPollResponses() {
        func p(_ s: String) -> GitHubTokenPoll { GitHubTokenPoll.parse(Data(s.utf8)) }
        #expect(p(#"{"access_token":"gho_x","token_type":"bearer","scope":"read:user,repo"}"#) == .token("gho_x"))
        #expect(p(#"{"error":"authorization_pending"}"#) == .pending)
        #expect(p(#"{"error":"slow_down","interval":10}"#) == .slowDown(10))
        #expect(p(#"{"error":"expired_token"}"#) == .failed("Kodun süresi doldu, yeniden dene."))
        #expect(p(#"{"error":"access_denied"}"#) == .failed("Giriş reddedildi."))
        #expect(p("bozuk") == .failed("GitHub'dan beklenmeyen yanıt."))
    }

    @Test func buildsRequests() throws {
        let r = GitHubAPI.deviceCodeRequest(clientID: "cid", scope: "read:user repo")
        #expect(r.url?.absoluteString == "https://github.com/login/device/code" && r.httpMethod == "POST")
        #expect(r.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(String(decoding: try #require(r.httpBody), as: UTF8.self) == "client_id=cid&scope=read%3Auser%20repo")
        let s = GitHubAPI.searchRequest(token: "t", login: "ali", since: "2026-10-18", page: 2)
        #expect(s.url?.absoluteString == "https://api.github.com/search/commits?q=author:ali%20author-date:%3E%3D2026-10-18&per_page=100&page=2")
        #expect(s.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }
}

@Suite struct GitHubStatsTests {
    private func profileJSON(_ days: [(String, Int)]) -> Data {
        let cells = days.map { #"{"date":"\#($0.0)","contributionCount":\#($0.1)}"# }.joined(separator: ",")
        return Data(#"""
        {"data":{"viewer":{"login":"ali","name":"Ali Can","avatarUrl":"https://a/x.png","contributionsCollection":{
          "totalCommitContributions":234,"totalPullRequestContributions":63,"totalIssueContributions":1,
          "totalPullRequestReviewContributions":2,"restrictedContributionsCount":5291,
          "contributionCalendar":{"totalContributions":5597,"weeks":[{"contributionDays":[\#(cells)]}]}}}}}
        """#.utf8)
    }

    @Test func parsesProfile() throws {
        let p = try #require(GitHubProfile.parse(profileJSON([("2026-11-16", 3), ("2026-11-17", 0)])))
        #expect(p.login == "ali" && p.name == "Ali Can" && p.avatarURL?.absoluteString == "https://a/x.png")
        #expect(p.total == 5597 && p.commits == 234 && p.pullRequests == 63 && p.privateCount == 5291)
        #expect(p.days == [ContributionDay(date: "2026-11-16", count: 3), ContributionDay(date: "2026-11-17", count: 0)])
    }

    @Test func rejectsErrorResponse() {
        #expect(GitHubProfile.parse(Data(#"{"errors":[{"message":"Bad credentials"}]}"#.utf8)) == nil)
    }

    @Test func streaksAndRecentCounts() throws {
        let days = [("2026-11-08", 2), ("2026-11-09", 0), ("2026-11-10", 1), ("2026-11-11", 4), ("2026-11-12", 5),
                    ("2026-11-13", 0), ("2026-11-14", 1), ("2026-11-15", 2), ("2026-11-16", 6), ("2026-11-17", 0)]
            .map { ContributionDay(date: $0.0, count: $0.1) }
        let s = ContributionStats(days: days, today: "2026-11-17")
        #expect(s.today == 0)
        #expect(s.lastSevenDays == 18)       // 11–17
        #expect(s.currentStreak == 3)        // bugün henüz yok: 14, 15, 16
        #expect(s.longestStreak == 3)        // 10–12 ve 14–16
        let withToday = ContributionStats(days: days.dropLast() + [ContributionDay(date: "2026-11-17", count: 1)], today: "2026-11-17")
        #expect(withToday.currentStreak == 4 && withToday.longestStreak == 4)
        #expect(ContributionStats(days: [], today: "2026-11-17").currentStreak == 0)
    }

    @Test func countsReposFromSearchPages() {
        let p1 = Data(#"{"total_count":3,"items":[{"repository":{"full_name":"ali/a","private":true}},{"repository":{"full_name":"ali/b","private":false}}]}"#.utf8)
        let p2 = Data(#"{"total_count":3,"items":[{"repository":{"full_name":"ali/a","private":true}}]}"#.utf8)
        let r = RepoActivity.count(searchPages: [p1, p2])
        #expect(r == [RepoActivity(name: "ali/a", isPrivate: true, commits: 2), RepoActivity(name: "ali/b", isPrivate: false, commits: 1)])
        #expect(RepoActivity.totalCount(p1) == 3)
    }
}

@Suite struct ContributionGridTests {
    @Test func weeksStartOnSundayAndPadFirstWeek() {
        // 2026-11-17 salı; 15 pazar.
        let days = ["2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"]
            .map { ContributionDay(date: $0, count: 1) }
        let g = ContributionGrid.weeks(days)
        #expect(g.count == 2)
        #expect(g[0].map { $0?.date } == [nil, nil, "2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21"])
        #expect(g[1].first??.date == "2026-11-22" && g[1].count == 2)
    }

    @Test func levelsByQuartileOfActiveDays() {
        let days = [0, 1, 2, 3, 4, 5, 6, 7, 8].map { ContributionDay(date: "d\($0)", count: $0) }
        let levels = days.map { ContributionGrid.level($0.count, in: days) }
        #expect(levels == [0, 1, 1, 2, 2, 3, 3, 4, 4])
        #expect(ContributionGrid.level(0, in: []) == 0)
    }

    @Test func monthLabelsAtFirstWeekOfMonth() {
        let days = stride(from: 0, to: 40, by: 1).map { i in
            ContributionDay(date: UsageMeter.dayKey(Date(timeIntervalSince1970: 1_793_491_200 + Double(i) * 86_400),
                                                    calendar: ContributionGrid.calendar), count: 0)
        } // 2026-11-01'den 40 gün
        let labels = ContributionGrid.monthLabels(ContributionGrid.weeks(days))
        #expect(labels.map(\.week) == [0, 5] && labels.map(\.name) == ["Kas", "Ara"])
    }
}
