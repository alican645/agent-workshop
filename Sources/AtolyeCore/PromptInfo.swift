import Foundation

/// Küçük JSON değeri: sohbet kaydındaki araç girdisini (`PendingTool.input`) taşır.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    public var string: String? { if case let .string(s) = self { s } else { nil } }
    public var bool: Bool? { if case let .bool(b) = self { b } else { nil } }
    public var array: [JSONValue]? { if case let .array(a) = self { a } else { nil } }
    public var object: [String: JSONValue]? { if case let .object(o) = self { o } else { nil } }

    /// `JSONSerialization` çıktısından.
    public init(any: Any) {
        switch any {
        case let s as String: self = .string(s)
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let a as [Any]: self = .array(a.map(JSONValue.init(any:)))
        case let o as [String: Any]: self = .object(o.mapValues(JSONValue.init(any:)))
        default: self = .null
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .string(s): try c.encode(s)
        case let .number(n): try c.encode(n)
        case let .bool(b): try c.encode(b)
        case .null: try c.encodeNil()
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }
}

/// Cevaplanmamış son araç çağrısı (tool_result'ı henüz gelmemiş).
public struct PendingTool: Equatable, Sendable {
    public var id: String
    public var name: String
    public var input: [String: JSONValue]

    public init(id: String, name: String, input: [String: JSONValue]) {
        self.id = id
        self.name = name
        self.input = input
    }
}

public struct PromptOptionInfo: Codable, Equatable, Sendable {
    public var label: String
    public var description: String?
    public var freeText: Bool
    public var checked: Bool?

    public init(label: String, description: String? = nil, freeText: Bool = false, checked: Bool? = nil) {
        self.label = label
        self.description = description
        self.freeText = freeText
        self.checked = checked
    }
}

/// Bekleyen robotun balonunda gösterilecek seçenek menüsü (sahneye snapshot'la gider; alan adları web'le sözleşme).
public struct PromptInfo: Codable, Equatable, Sendable {
    public var kind: PromptKind
    public var question: String
    public var detail: String?
    /// Etiketler ekrandakiyle birebir aynı (sıra ve sayı); web bunları geri yollar, `PromptKeys` karşılaştırır.
    public var options: [PromptOptionInfo]
    public var multi: Bool
    /// Çok sorulu AskUserQuestion'da açık sayfa (tahmin: ilk cevapsız sekme) ve sayfa sayısı.
    public var page: Int?
    public var pages: Int?
    /// Terminal Atölye'deyse cevap tuş olarak gönderilebilir.
    public var answerable: Bool
    /// Cevap gönderildi, ekranın değişmesi bekleniyor.
    public var sent: Bool
    /// Gönderildi ama menü yerinde duruyor ("gitmedi — terminali aç").
    public var failed: Bool
    /// Plan onayında Markdown okuyucuda açılacak dosya.
    public var planPath: String?
    /// Ham ekranın kimliği (`ScreenPrompt.menuId`; birleştirilmiş detaydan değil). Web cevapta geri yollar;
    /// tazelenen ekranınkiyle tutmazsa hiçbir şey gönderilmez. Cevaplanamaz balonda boş.
    public var menuId: String

    public init(kind: PromptKind, question: String, detail: String? = nil, options: [PromptOptionInfo], multi: Bool,
                page: Int? = nil, pages: Int? = nil, answerable: Bool, sent: Bool = false, failed: Bool = false,
                planPath: String? = nil, menuId: String = "") {
        self.kind = kind
        self.question = question
        self.detail = detail
        self.options = options
        self.multi = multi
        self.page = page
        self.pages = pages
        self.answerable = answerable
        self.sent = sent
        self.failed = failed
        self.planPath = planPath
        self.menuId = menuId
    }
}

/// Ekrandan okunan menüyü sohbet kaydındaki bekleyen çağrıyla birleştirir. Ekran esastır: kayıt yalnız
/// soru metnini ve seçenek açıklamalarını ekler; etiketlere, sıraya, sayıya dokunmaz.
public enum PromptMerge {
    /// `screenRead`: terminalin ekranı okundu (ama `screen` nil ise menü tanınmadı). Henüz okunmadıysa
    /// balon yok (ilk okuma gelene kadar titremesin); okundu ve tanınmadıysa cevaplanamaz balon
    /// ("terminalinden cevapla · terminali aç"). `failed` iken `sent` hiç true dönmez.
    public static func info(screen: ScreenPrompt?, pending: PendingTool?, hasTerminal: Bool,
                            screenRead: Bool = false, sent: Bool, failed: Bool) -> PromptInfo? {
        guard hasTerminal else { return outside(pending: pending) }
        guard let screen else { return screenRead ? unrecognised(pending: pending) : nil }
        var info = PromptInfo(
            kind: screen.kind, question: screen.title ?? "", detail: screen.detail,
            options: screen.options.map { PromptOptionInfo(label: $0.label, freeText: $0.freeText, checked: $0.checked) },
            multi: screen.multi, page: screen.page?.index, pages: screen.page?.count,
            answerable: true, sent: sent && !failed, failed: failed, menuId: screen.menuId)
        switch screen.kind {
        case .permission:
            // Alt ajanın izinleri ana kayıtta yoktur; kayıttaki komut ancak ekrandaki komutun kendisiyse kullanılır.
            if pending?.name == "Bash", let cmd = pending?.input["command"]?.string, let shown = screen.detail,
               sameCommand(cmd, onScreen: shown) {
                info.detail = cmd
            }
        case .question:
            guard pending?.name == "AskUserQuestion", let qs = questions(pending) else { break }
            let labels = screen.options.map(\.label)
            // Ekran uzun sorunun yalnız son satırını gösterir; kayıttaki soru (boşluklar sadeleştirilerek)
            // ekrandaki başlıkla bitmeli. Aynı etiketli başka bir soru ekrandakinin yerine geçmesin.
            let shown = flat(screen.title ?? "")
            guard !shown.isEmpty else { break }
            // Önce ayrıştırıcının sandığı sayfa, sonra diğerleri; etiketleri ekranın başıyla aynı olan ilk soru.
            var order = Array(qs.indices)
            if let p = screen.page?.index, qs.indices.contains(p) { order.removeAll { $0 == p }; order.insert(p, at: 0) }
            guard let q = order.map({ qs[$0] }).first(where: { q in
                !q.options.isEmpty && q.options.count <= labels.count
                    && Array(labels.prefix(q.options.count)) == q.options.map(\.label)
                    && flat(q.question).hasSuffix(shown)
            }) else { break }
            info.question = q.question
            for (i, o) in q.options.enumerated() { info.options[i].description = o.description }
        case .plan:
            break   // planPath'i model doldurur
        }
        return info
    }

    /// Ekranı okundu ama menüsü tanınmadı: kayıttan çizilebiliyorsa o, yoksa türü kayıttan tahmin edilen
    /// boş balon (web varsayılan başlığı koyar). Her durumda cevaplanamaz.
    private static func unrecognised(pending: PendingTool?) -> PromptInfo {
        if let info = outside(pending: pending) { return info }
        return PromptInfo(kind: .permission, question: "", options: [], multi: false, answerable: false)
    }

    /// Terminali Atölye'de olmayan (ya da ekranı okunamayan) oturum: yalnız kayıttan, cevaplanamaz.
    private static func outside(pending: PendingTool?) -> PromptInfo? {
        switch pending?.name {
        case "AskUserQuestion":
            guard let qs = questions(pending), let q = qs.first else { return nil }
            return PromptInfo(kind: .question, question: q.question,
                              options: q.options.map { PromptOptionInfo(label: $0.label, description: $0.description) },
                              multi: q.multi, pages: qs.count > 1 ? qs.count : nil, answerable: false)
        case "ExitPlanMode":
            return PromptInfo(kind: .plan, question: "", options: [], multi: false, answerable: false)
        default:
            return nil
        }
    }

    private struct Question {
        var question: String
        var multi: Bool
        var options: [(label: String, description: String?)]
    }

    /// AskUserQuestion girdisi: `questions: [{question, header, multiSelect, options: [{label, description}]}]`.
    private static func questions(_ p: PendingTool?) -> [Question]? {
        guard let arr = p?.input["questions"]?.array else { return nil }
        let qs = arr.compactMap { v -> Question? in
            guard let o = v.object else { return nil }
            let opts = (o["options"]?.array ?? []).compactMap { v -> (String, String?)? in
                guard let label = v.object?["label"]?.string else { return nil }
                let d = v.object?["description"]?.string
                return (label, d?.isEmpty == true ? nil : d)
            }
            return Question(question: o["question"]?.string ?? "", multi: o["multiSelect"]?.bool ?? false,
                            options: opts.map { (label: $0.0, description: $0.1) })
        }
        return qs.isEmpty ? nil : qs
    }

    /// Kayıttaki komut ekrandaki komutla (boşluklar sadeleştirilerek) birebir aynı mı. Ekranın komutu
    /// `╌╌╌` çizgileri arasındaki satırlardır (kırılmış komut tek satıra birleştirilir); çizgi yoksa tek tek
    /// satırlar. Alt dize ya da baş kısım eşleşmesi yetmez: başka bir komut (alt ajanın `… --force`'u) gizlenmesin.
    static func sameCommand(_ command: String, onScreen detail: String) -> Bool {
        let c = flat(command)
        guard !c.isEmpty else { return false }
        let lines = detail.components(separatedBy: "\n")
        let rules = lines.indices.filter { i in
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && t.allSatisfy { $0 == "╌" }
        }
        // Çizgiler varsa komut yalnız aralarındaki birleşik metindir: tek tek satırlar aday olsaydı kırılmış
        // `git push origin main` / `--force` komutunun ilk satırı kayıttaki zayıf komutla eşleşirdi.
        if rules.count >= 2 { return flat(lines[(rules[0] + 1)..<rules[1]].joined(separator: " ")) == c }
        return lines.map(flat).contains(c)
    }

    /// Boşlukları (satır sonları dahil) tek boşluğa indirir.
    static func flat(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}
