import Foundation

/// Projede tek tıkla çalıştırılan bir komut (ör. `./deploy.sh`). Proje kökündeki `RUN.local.json`'da durur.
public struct RunCard: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Proje kökünde `zsh -il -c` ile çalıştırılan kabuk satırı.
    public var command: String
    /// Çalıştırmadan önce sorulsun mu (geri alınamayan işler için).
    public var confirm: Bool

    public init(id: String = UUID().uuidString, name: String, command: String, confirm: Bool = true) {
        self.id = id
        self.name = name
        self.command = command
        self.confirm = confirm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        // Elle yazılmış kartta kimlik yoksa addan ve komuttan sabit bir kimlik: her okumada aynı kalır.
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Self.stableID(name: name, command: command)
        // Elle yazılmış dosyada eksikse güvenli taraf: sor.
        confirm = try c.decodeIfPresent(Bool.self, forKey: .confirm) ?? true
    }
}

extension RunCard {
    static func stableID(name: String, command: String) -> String {
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in (name + "\u{1}" + command).utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        return "auto-" + String(h, radix: 16)
    }
}

/// `RUN.local.json` okuma/yazma. Sahne için bozuk ya da eksik dosya boş liste sayılır;
/// yazarken bozuk dosyanın üstüne yazılmaz (`update`).
public enum RunCardFile {
    public static let fileName = "RUN.local.json"

    /// Dosya var ama çözülemiyor: elle düzeltilmeli.
    public struct Unreadable: LocalizedError {
        public var errorDescription: String? { "RUN.local.json okunamadı (JSON bozuk)" }
    }

    private struct Body: Codable { var cards: [RunCard] }

    public static func path(root: String) -> String { root + "/" + fileName }

    public static func parse(_ data: Data) -> [RunCard] {
        (try? JSONDecoder().decode(Body.self, from: data))?.cards ?? []
    }

    public static func encode(_ cards: [RunCard]) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(Body(cards: cards))) ?? Data()
    }

    public static func cards(root: String) -> [RunCard] { load(root: root) ?? [] }

    /// Dosya yoksa boş liste; var ama çözülemiyorsa nil.
    public static func load(root: String) -> [RunCard]? {
        guard let data = FileManager.default.contents(atPath: path(root: root)) else { return [] }
        return try? JSONDecoder().decode(Body.self, from: data).cards
    }

    /// Dosyanın son haline `edit`'i uygular ve yazar. Dosya bozuksa yazmaz, `Unreadable` atar.
    public static func update(root: String, _ edit: (inout [RunCard]) -> Void) throws {
        guard var list = load(root: root) else { throw Unreadable() }
        let old = list
        edit(&list)
        guard list != old else { return }
        try write(list, root: root)
    }

    public static func write(_ cards: [RunCard], root: String) throws {
        try encode(cards).write(to: URL(fileURLWithPath: path(root: root)), options: .atomic)
    }
}

/// Kartın sahnedeki durumu (çarkın dönmesi ve rengi).
public enum RunState: String, Codable, Sendable {
    case idle, running, ok, failed
}

public enum RunCards {
    /// Karta ait (aynı kökte açılmış) en yeni terminal; liste host'un açılış sırasındadır.
    public static func latestTerminal(card: String, root: String, in terminals: [TerminalInfo]) -> TerminalInfo? {
        terminals.last { $0.run?.cardID == card && $0.cwd == root }
    }

    /// Karta ait en yeni terminalden durum: yok → boşta; çalışıyor; 0 ile bitti → başarılı; başka → hatalı.
    public static func state(of t: TerminalInfo?) -> RunState {
        guard let t else { return .idle }
        if t.running { return .running }
        return t.exitCode == 0 ? .ok : .failed
    }
}

/// Karta tıklanınca ne olacağı.
public enum RunLaunch: Equatable, Sendable {
    /// Zaten çalışıyor: ikinci kez başlatma, terminalini öne getir.
    case focus(terminal: String)
    /// Önce sor.
    case ask
    case start
    /// Komut boş: çalıştırılamaz.
    case invalid
    /// Az önce başlatıldı, terminali henüz açılmadı: ikinci kez başlatma.
    case pending

    /// `pending`: başlatıldı, host'un cevabı henüz gelmedi.
    public static func decide(card: RunCard, latest: TerminalInfo?, pending: Bool = false) -> RunLaunch {
        if card.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .invalid }
        if pending { return .pending }
        if let latest, latest.running { return .focus(terminal: latest.id) }
        return card.confirm ? .ask : .start
    }
}
