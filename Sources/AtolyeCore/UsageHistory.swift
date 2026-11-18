import Foundation

/// Bir günün toplam kullanımı.
public struct DailyUsage: Codable, Equatable, Sendable {
    public var tokens: Int
    /// Dolar, API liste fiyatıyla.
    public var cost: Double

    public init(tokens: Int, cost: Double) {
        self.tokens = tokens
        self.cost = cost
    }

    public static func + (a: DailyUsage, b: DailyUsage) -> DailyUsage {
        DailyUsage(tokens: a.tokens + b.tokens, cost: a.cost + b.cost)
    }
}

extension SessionUsage {
    /// Yerel güne göre ("yyyy-MM-dd") token ve maliyet.
    public func byDay(calendar: Calendar = .current) -> [String: DailyUsage] {
        var out: [String: DailyUsage] = [:]
        for d in dated {
            let key = UsageMeter.dayKey(d.at, calendar: calendar)
            out[key] = (out[key] ?? DailyUsage(tokens: 0, cost: 0)) + DailyUsage(tokens: d.tokens, cost: d.cost)
        }
        return out
    }
}

/// Günlük kullanım geçmişi. Claude Code eski kayıtları siler (varsayılan 30 gün); günlük toplamlar
/// uygulamanın kendi dosyasında saklanır ve grafik zamanla bir yıla tamamlanır.
public enum UsageHistory {
    /// Kayıtlardan hesaplanan günler saklananlarla birleşir; her günün büyüğü kalır (silinen kayıtlar
    /// günü küçültür, saklanan değer korunur).
    public static func merge(stored: [String: DailyUsage], computed: [String: DailyUsage]) -> [String: DailyUsage] {
        stored.merging(computed) { a, b in b.tokens >= a.tokens ? b : a }
    }

    /// Bugünle biten 365 gün (boş günler 0), grafik için.
    public static func year(_ days: [String: DailyUsage], today: String) -> [ContributionDay] {
        let cal = ContributionGrid.calendar
        guard let end = ContributionGrid.date(today) else { return [] }
        return (0..<365).reversed().compactMap { back -> ContributionDay? in
            guard let d = cal.date(byAdding: .day, value: -back, to: end) else { return nil }
            let key = UsageMeter.dayKey(d, calendar: cal)
            return ContributionDay(date: key, count: days[key]?.tokens ?? 0)
        }
    }

    public static func load(from url: URL) -> [String: DailyUsage] {
        guard let d = try? Data(contentsOf: url), let v = try? JSONDecoder().decode([String: DailyUsage].self, from: d) else { return [:] }
        return v
    }

    public static func save(_ days: [String: DailyUsage], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(days).write(to: url, options: .atomic)
    }
}

/// Kullanım penceresinin kartları.
public struct UsageSummary: Equatable, Sendable {
    public var today: DailyUsage
    public var lastSevenDays: DailyUsage
    public var thisMonth: DailyUsage
    public var busiest: (date: String, usage: DailyUsage)?
    /// Üst üste kullanılan günler (bugün henüz kullanılmadıysa dünden geriye).
    public var currentStreak: Int
    public var longestStreak: Int
    /// Kaydı olan ilk gün.
    public var firstDay: String?
    /// Son 365 günün toplam tokeni.
    public var yearTokens: Int

    public init(days: [String: DailyUsage], today: String) {
        let zero = DailyUsage(tokens: 0, cost: 0)
        let year = UsageHistory.year(days, today: today)
        let stats = ContributionStats(days: year, today: today)
        self.today = days[today] ?? zero
        lastSevenDays = year.suffix(7).reduce(zero) { $0 + (days[$1.date] ?? zero) }
        let month = String(today.prefix(7))
        thisMonth = days.filter { $0.key.hasPrefix(month) && $0.key <= today }.values.reduce(zero, +)
        busiest = days.filter { $0.key <= today && $0.value.tokens > 0 }
            .max { ($0.value.tokens, $1.key) < ($1.value.tokens, $0.key) }
            .map { ($0.key, $0.value) }
        currentStreak = stats.currentStreak
        longestStreak = stats.longestStreak
        firstDay = days.filter { $0.value.tokens > 0 }.keys.min()
        yearTokens = year.reduce(0) { $0 + $1.count }
    }

    public static func == (a: UsageSummary, b: UsageSummary) -> Bool {
        a.today == b.today && a.lastSevenDays == b.lastSevenDays && a.thisMonth == b.thisMonth
            && a.busiest?.date == b.busiest?.date && a.busiest?.usage == b.busiest?.usage
            && a.currentStreak == b.currentStreak && a.longestStreak == b.longestStreak
            && a.firstDay == b.firstDay && a.yearTokens == b.yearTokens
    }
}
