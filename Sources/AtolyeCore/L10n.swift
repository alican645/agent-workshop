import Foundation

/// Uygulamanın dil desteği. Kaynak dil Türkçe: koddaki Türkçe metin anahtardır, İngilizce karşılığı
/// `Web/i18n/en.json` sözlüğündedir (sahne de aynı dosyayı kullanır). `{0}`, `{1}`… yer tutucuları
/// argümanlarla doldurulur; çevirisi olmayan metin Türkçe kalır.
public enum L10n {
    public enum Preference: String, CaseIterable, Sendable { case system, en, tr }

    nonisolated(unsafe) public private(set) static var table: [String: String] = [:]
    /// "tr" ya da "en". Uygulama açılırken bir kez ayarlanır.
    nonisolated(unsafe) public private(set) static var language = "tr"
    public static var isEnglish: Bool { language == "en" }
    public static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "tr_TR") }

    /// Sistem dili Türkçe ise Türkçe, başka her dilde İngilizce.
    public static func resolve(_ p: Preference, preferred: [String] = Locale.preferredLanguages) -> String {
        switch p {
        case .en: return "en"
        case .tr: return "tr"
        case .system: return preferred.first?.lowercased().hasPrefix("tr") == true ? "tr" : "en"
        }
    }

    /// Arayüz kurulmadan önce bir kez çağrılır.
    public static func use(language: String, table: [String: String]) {
        self.language = language
        self.table = table
    }

    public static func loadTable(_ url: URL) -> [String: String] {
        guard let d = try? Data(contentsOf: url), let t = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return t
    }

    public static func translate(_ key: String, _ args: [String], language: String, table: [String: String]) -> String {
        var s = language == "en" ? table[key] ?? key : key
        for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: a) }
        return s
    }
}

/// Çevrilecek metin: `L("Robotlar")`, `L("{0} gün", "\(n)")`.
public func L(_ key: String, _ args: String...) -> String {
    L10n.translate(key, args, language: L10n.language, table: L10n.table)
}


extension AccountProfile {
    /// Ekranda görünen ad: kendiliğinden verilen "Profil N" ve "Varsayılan" seçili dile çevrilir.
    public var displayName: String { Self.displayName(name, language: L10n.language, table: L10n.table) }

    public static func displayName(_ name: String, language: String, table: [String: String]) -> String {
        if name == "Varsayılan" { return L10n.translate("Varsayılan", [], language: language, table: table) }
        let parts = name.split(separator: " ")
        if parts.count == 2, parts[0] == "Profil", Int(parts[1]) != nil {
            return L10n.translate("Profil {0}", [String(parts[1])], language: language, table: table)
        }
        return name
    }
}
