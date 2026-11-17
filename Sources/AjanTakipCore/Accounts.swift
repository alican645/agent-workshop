import Foundation

/// Bir hesabın statusline'dan bildirilen son kullanım oranları (0…1).
public struct AccountUsage: Equatable, Codable, Sendable {
    public var fiveHour: Double?
    public var fiveHourResetsAt: Date?
    public var sevenDay: Double?
    public var sevenDayResetsAt: Date?
    public var reportedAt: Date

    public init(fiveHour: Double?, fiveHourResetsAt: Date?, sevenDay: Double?, sevenDayResetsAt: Date?, reportedAt: Date) {
        self.fiveHour = fiveHour; self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDay = sevenDay; self.sevenDayResetsAt = sevenDayResetsAt
        self.reportedAt = reportedAt
    }

    private static func effective(_ v: Double?, _ reset: Date?, _ now: Date) -> Double? {
        if let reset, reset <= now { return 0 }
        return v
    }
    public func effectiveFiveHour(now: Date) -> Double? { Self.effective(fiveHour, fiveHourResetsAt, now) }
    public func effectiveSevenDay(now: Date) -> Double? { Self.effective(sevenDay, sevenDayResetsAt, now) }
}

/// `POST /usage` gövdesi: statusline JSON'undaki `rate_limits` nesnesi + X-Claude-Config-Dir başlığı.
public struct UsageReport: Equatable, Sendable {
    public var configDir: String?
    public var usage: AccountUsage

    public static func parse(body: Data, headers: [String: String], now: Date) -> UsageReport? {
        guard let obj = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) as? [String: Any]
        else { return nil }
        func window(_ key: String) -> (Double?, Date?) {
            guard let w = obj[key] as? [String: Any] else { return (nil, nil) }
            let pct = (w["used_percentage"] as? NSNumber).map { $0.doubleValue / 100 }
            let reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return (pct, reset)
        }
        let (f, fr) = window("five_hour"), (s, sr) = window("seven_day")
        guard f != nil || s != nil else { return nil }
        let dir = headers["x-claude-config-dir"].flatMap { $0.isEmpty ? nil : $0 }
        return UsageReport(configDir: dir, usage: AccountUsage(fiveHour: f, fiveHourResetsAt: fr, sevenDay: s,
                                                               sevenDayResetsAt: sr, reportedAt: now))
    }
}

public enum AccountError: Error, Equatable { case emptyName, duplicateName }

public struct AccountProfile: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var configDir: String
    /// Bu profilde girişli olması beklenen hesap (yalnız uyarı için).
    public var email: String?

    public init(id: String, name: String, configDir: String, email: String? = nil) {
        self.id = id; self.name = name; self.configDir = configDir; self.email = email
    }
}

/// Claude profilleri: varsayılan `~/.claude` + `~/.claude-profiles/<id>`.
public struct AccountStore: Equatable, Codable, Sendable {
    public static let defaultID = "default"
    public static let warningThreshold = 0.9
    public var home: String
    public var profiles: [AccountProfile]
    public var activeID: String

    public init(home: String) {
        self.home = home
        profiles = [AccountProfile(id: Self.defaultID, name: "Varsayılan", configDir: home + "/.claude")]
        activeID = Self.defaultID
    }

    static func slug(_ name: String) -> String {
        let mapped = name.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        var out = "", dash = false
        for ch in mapped {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { out.append(ch); dash = false }
            else if !dash && !out.isEmpty { out.append("-"); dash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    @discardableResult
    public mutating func addProfile(name: String) throws -> AccountProfile {
        let id = Self.slug(name)
        guard !id.isEmpty else { throw AccountError.emptyName }
        guard id != Self.defaultID, !profiles.contains(where: { $0.id == id }) else { throw AccountError.duplicateName }
        let p = AccountProfile(id: id, name: name.trimmingCharacters(in: .whitespaces),
                               configDir: home + "/.claude-profiles/" + id)
        profiles.append(p)
        return p
    }

    /// `profil-N` (boş ilk numara) olarak yeni profil.
    @discardableResult
    public mutating func addProfile(email: String?) -> AccountProfile {
        var n = 2
        while profiles.contains(where: { $0.id == "profil-\(n)" }) { n += 1 }
        let p = AccountProfile(id: "profil-\(n)", name: "Profil \(n)", configDir: home + "/.claude-profiles/profil-\(n)",
                               email: email.flatMap { $0.isEmpty ? nil : $0 })
        profiles.append(p)
        return p
    }

    /// Claude'un genel ayar dosyası: varsayılanda `~/.claude.json`, diğerlerinde `<klasör>/.claude.json`.
    public func globalConfigPath(_ id: String) -> String? {
        if id == Self.defaultID { return home + "/.claude.json" }
        return profiles.first { $0.id == id }.map { $0.configDir + "/.claude.json" }
    }

    /// Bu profille açılan terminalin ortamı. Varsayılanda CLAUDE_CONFIG_DIR verilmez (verilirse Claude
    /// `~/.claude/.claude.json`'u ve başka bir anahtar zinciri kaydını kullanır).
    public func environment(_ id: String) -> [String: String] {
        guard id != Self.defaultID, let p = profiles.first(where: { $0.id == id }) else { return [:] }
        return ["CLAUDE_CONFIG_DIR": p.configDir]
    }

    public mutating func removeProfile(id: String) {
        guard id != Self.defaultID else { return }
        profiles.removeAll { $0.id == id }
        if activeID == id { activeID = Self.defaultID }
    }

    public func profileID(forConfigDir dir: String?) -> String? {
        guard var dir else { return Self.defaultID }
        while dir.count > 1 && dir.hasSuffix("/") { dir.removeLast() }
        return profiles.first { $0.configDir == dir }?.id
    }

    /// `.zshrc` fonksiyonunun okuduğu değer: varsayılan için boş.
    public var activeConfigDirForShell: String {
        activeID == Self.defaultID ? "" : profiles.first { $0.id == activeID }?.configDir ?? ""
    }

    /// `~/.config/ajantakip/profiles`: `claude mcp` eşitlemesi için her profilin config dizini, satır başına bir.
    public var profilesFileContents: String {
        profiles.map { $0.configDir + "\n" }.joined()
    }

    public static func needsWarning(_ u: AccountUsage, now: Date) -> Bool {
        (u.effectiveFiveHour(now: now) ?? 0) >= warningThreshold || (u.effectiveSevenDay(now: now) ?? 0) >= warningThreshold
    }
}

/// Kabuk dosyalarına işaretli blok ekleme/çıkarma.
public enum ShellSnippet {
    public static let begin = "# >>> ajantakip >>>"
    public static let end = "# <<< ajantakip <<<"

    private static func blockRange(in text: String) -> Range<String.Index>? {
        guard let b = text.range(of: begin), let e = text.range(of: end, range: b.upperBound..<text.endIndex)
        else { return nil }
        var upper = e.upperBound
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        return b.lowerBound..<upper
    }

    public static func contains(in text: String) -> Bool { blockRange(in: text) != nil }

    public static func insert(_ block: String, into text: String) -> String {
        if let r = blockRange(in: text) { return text.replacingCharacters(in: r, with: block) }
        var t = text
        if !t.isEmpty && !t.hasSuffix("\n") { t += "\n" }
        return t + (t.isEmpty ? "" : "\n") + block
    }

    public static func remove(from text: String) -> String {
        guard let r = blockRange(in: text) else { return text }
        var t = text.replacingCharacters(in: r, with: "")
        if t.hasSuffix("\n\n") { t.removeLast() }
        return t
    }
}
