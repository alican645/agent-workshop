import Foundation

// MARK: Cihaz akışıyla giriş

public struct GitHubDeviceCode: Equatable, Sendable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURI: URL
    public var expiresIn: Int
    public var interval: Int

    public static func parse(_ data: Data) -> GitHubDeviceCode? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dc = o["device_code"] as? String, let uc = o["user_code"] as? String,
              let uri = (o["verification_uri"] as? String).flatMap(URL.init(string:)) else { return nil }
        return GitHubDeviceCode(deviceCode: dc, userCode: uc, verificationURI: uri,
                                expiresIn: (o["expires_in"] as? Int) ?? 900, interval: (o["interval"] as? Int) ?? 5)
    }
}

public enum GitHubTokenPoll: Equatable, Sendable {
    case token(String)
    case pending
    case slowDown(Int)
    case failed(String)

    public static func parse(_ data: Data) -> GitHubTokenPoll {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("GitHub'dan beklenmeyen yanıt.")
        }
        if let t = o["access_token"] as? String { return .token(t) }
        switch o["error"] as? String {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown((o["interval"] as? Int) ?? 10)
        case "expired_token": return .failed("Kodun süresi doldu, yeniden dene.")
        case "access_denied": return .failed("Giriş reddedildi.")
        case let e?: return .failed((o["error_description"] as? String) ?? e)
        case nil: return .failed("GitHub'dan beklenmeyen yanıt.")
        }
    }
}

public enum GitHubAPI {
    public static let scope = "read:user repo"

    private static func form(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(pairs.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }

    private static func post(_ url: String, _ body: Data) -> URLRequest {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        return r
    }

    public static func deviceCodeRequest(clientID: String, scope: String = scope) -> URLRequest {
        post("https://github.com/login/device/code", form([("client_id", clientID), ("scope", scope)]))
    }

    public static func tokenRequest(clientID: String, deviceCode: String) -> URLRequest {
        post("https://github.com/login/oauth/access_token",
             form([("client_id", clientID), ("device_code", deviceCode),
                   ("grant_type", "urn:ietf:params:oauth:grant-type:device_code")]))
    }

    static let profileQuery = """
        query { viewer { login name avatarUrl contributionsCollection {
          totalCommitContributions totalPullRequestContributions totalIssueContributions
          totalPullRequestReviewContributions restrictedContributionsCount
          contributionCalendar { totalContributions weeks { contributionDays { date contributionCount } } } } } }
        """

    public static func profileRequest(token: String) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["query": profileQuery])
        return r
    }

    /// `since`: "yyyy-MM-dd".
    public static func searchRequest(token: String, login: String, since: String, page: Int) -> URLRequest {
        var c = URLComponents(string: "https://api.github.com/search/commits")!
        c.percentEncodedQueryItems = [
            URLQueryItem(name: "q", value: "author:\(login)%20author-date:%3E%3D\(since)"),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "page", value: String(page)),
        ]
        var r = URLRequest(url: c.url!)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return r
    }
}

// MARK: Profil ve katkılar

public struct ContributionDay: Equatable, Sendable, Identifiable {
    public var date: String // yyyy-MM-dd
    public var count: Int
    public var id: String { date }
    public init(date: String, count: Int) { self.date = date; self.count = count }
}

public struct GitHubProfile: Equatable, Sendable {
    public var login: String
    public var name: String?
    public var avatarURL: URL?
    public var total: Int
    public var commits: Int
    public var pullRequests: Int
    public var issues: Int
    public var reviews: Int
    /// Ayrıntısı gösterilmeyen (gizli depolardaki) katkılar; toplamın içinde.
    public var privateCount: Int
    public var days: [ContributionDay]

    public static func parse(_ data: Data) -> GitHubProfile? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = (o["data"] as? [String: Any])?["viewer"] as? [String: Any],
              let login = v["login"] as? String,
              let c = v["contributionsCollection"] as? [String: Any],
              let cal = c["contributionCalendar"] as? [String: Any] else { return nil }
        let days = ((cal["weeks"] as? [[String: Any]]) ?? []).flatMap { w in
            ((w["contributionDays"] as? [[String: Any]]) ?? []).compactMap { d -> ContributionDay? in
                guard let date = d["date"] as? String else { return nil }
                return ContributionDay(date: date, count: (d["contributionCount"] as? Int) ?? 0)
            }
        }
        func n(_ k: String) -> Int { (c[k] as? Int) ?? 0 }
        return GitHubProfile(login: login, name: v["name"] as? String,
                             avatarURL: (v["avatarUrl"] as? String).flatMap(URL.init(string:)),
                             total: (cal["totalContributions"] as? Int) ?? 0, commits: n("totalCommitContributions"),
                             pullRequests: n("totalPullRequestContributions"), issues: n("totalIssueContributions"),
                             reviews: n("totalPullRequestReviewContributions"),
                             privateCount: n("restrictedContributionsCount"), days: days)
    }
}

public struct ContributionStats: Equatable, Sendable {
    public var today: Int
    public var lastSevenDays: Int
    /// Bugün henüz katkı yoksa dünden geriye sayılır (gün bitmeden seri kopmuş sayılmaz).
    public var currentStreak: Int
    public var longestStreak: Int

    /// `today`: yerel gün, "yyyy-MM-dd". Günler tarih sırasında.
    public init(days: [ContributionDay], today: String) {
        let upTo = days.filter { $0.date <= today }
        self.today = upTo.last { $0.date == today }?.count ?? 0
        lastSevenDays = upTo.suffix(7).reduce(0) { $0 + $1.count }
        var tail = upTo[...]
        if tail.last?.date == today, tail.last?.count == 0 { tail = tail.dropLast() }
        currentStreak = tail.reversed().prefix { $0.count > 0 }.count
        var best = 0, run = 0
        for d in upTo { run = d.count > 0 ? run + 1 : 0; best = max(best, run) }
        longestStreak = best
    }
}

public struct RepoActivity: Equatable, Sendable, Identifiable {
    public var name: String
    public var isPrivate: Bool
    public var commits: Int
    public var id: String { name }

    public static func count(searchPages: [Data]) -> [RepoActivity] {
        var counts: [String: RepoActivity] = [:]
        for page in searchPages {
            guard let o = try? JSONSerialization.jsonObject(with: page) as? [String: Any] else { continue }
            for item in (o["items"] as? [[String: Any]]) ?? [] {
                guard let r = item["repository"] as? [String: Any], let name = r["full_name"] as? String else { continue }
                counts[name, default: RepoActivity(name: name, isPrivate: (r["private"] as? Bool) ?? false, commits: 0)].commits += 1
            }
        }
        return counts.values.sorted { ($0.commits, $1.name) > ($1.commits, $0.name) }
    }

    public static func totalCount(_ page: Data) -> Int {
        ((try? JSONSerialization.jsonObject(with: page)) as? [String: Any])?["total_count"] as? Int ?? 0
    }
}

/// Isı haritası yerleşimi: pazar başlı hafta sütunları, renk seviyeleri, ay etiketleri.
public enum ContributionGrid {
    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func date(_ s: String) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// Her sütun bir hafta (pazar → cumartesi); ilk haftanın baştaki boş günleri `nil`.
    public static func weeks(_ days: [ContributionDay]) -> [[ContributionDay?]] {
        guard let first = days.first, let d = date(first.date) else { return [] }
        let pad = calendar.component(.weekday, from: d) - 1 // pazar = 1
        let cells: [ContributionDay?] = Array(repeating: nil, count: pad) + days.map { Optional($0) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    /// 0 = katkı yok; 1–4 = katkılı günlerin çeyreklerine göre.
    public static func level(_ count: Int, in days: [ContributionDay]) -> Int {
        guard count > 0 else { return 0 }
        let active = days.map(\.count).filter { $0 > 0 }.sorted()
        guard !active.isEmpty else { return 1 }
        let q = [1, 2, 3].map { active[min(active.count - 1, active.count * $0 / 4)] }
        return count < q[0] ? 1 : count < q[1] ? 2 : count < q[2] ? 3 : 4
    }

    static let months = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]

    /// Ayın ilk tam haftasının sütununa ay adı.
    public static func monthLabels(_ weeks: [[ContributionDay?]]) -> [(week: Int, name: String)] {
        var out: [(week: Int, name: String)] = []
        var last = -1
        for (i, w) in weeks.enumerated() {
            guard let day = w.compactMap({ $0 }).first, let d = date(day.date) else { continue }
            let m = calendar.component(.month, from: d)
            if m != last {
                // Hafta ayın ortasında başlıyorsa etiket bir sonraki haftaya kalır (GitHub gibi), ilk sütun hariç.
                if i == 0 || calendar.component(.day, from: d) <= 7 { out.append((i, months[m - 1])) }
                last = m
            }
        }
        return out
    }
}
