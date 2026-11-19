import Foundation

/// Kullanıcının balonda verdiği cevap. Tek seçimde `option`, çoklu seçimde `checks` (istenen işaretli küme).
/// `text` yalnız serbest metin seçeneği içindir. `labels`: balonun gösterdiği etiketler;
/// `menuId`: balonun gösterdiği menünün kimliği (`ScreenPrompt.menuId`).
public struct PromptAnswer: Equatable, Sendable {
    public var option: Int?
    public var checks: [Int]
    public var text: String?
    public var labels: [String]
    public var menuId: String
    public init(option: Int? = nil, checks: [Int] = [], text: String? = nil, labels: [String], menuId: String) {
        self.option = option; self.checks = checks; self.text = text; self.labels = labels; self.menuId = menuId
    }
}

/// Cevabı terminale gidecek tuşlara çevirir (Claude Code 2.1.327, bkz. Fixtures/prompts/README.md).
/// Gezinme indekse değil ok tuşu duraklarına (`stop`) göre; en üst/alt sınırda sarma denenmediği için
/// sınır dışına hiç basılmaz. Emin olunmayan her durumda nil.
public enum PromptKeys {
    static let up = "\u{1b}[A", down = "\u{1b}[B", enter = "\r", space = " "

    public static func keys(for answer: PromptAnswer, on screen: ScreenPrompt?) -> Data? {
        guard let screen, answer.menuId == screen.menuId, answer.labels == screen.options.map(\.label),
              screen.options.indices.contains(screen.selected) else { return nil }
        let opts = screen.options
        var out = ""
        var cursor = opts[screen.selected].stop
        func move(to stop: Int) {
            out += String(repeating: stop > cursor ? down : up, count: abs(stop - cursor))
            cursor = stop
        }
        // text verilmişse yalnız serbest metin seçeneğinde, temizlenince boş kalmayan metin geçerli.
        func typed(for i: Int) -> String?? {
            guard let raw = answer.text else { return .some(nil) }
            // Metin yalnız AskUserQuestion'da doğrulandı. Plan onayının "Tell Claude what to change"i ve
            // eski izinlerin "No, and tell Claude …"u sıradan seçenektir: harfler o menünün kısayollarına gidebilir.
            guard screen.kind == .question else { return nil }
            // Satırda önceden yazılmış metin varsa (etiket artık yer tutucu değil) terminal üstüne ekler
            // ("hello"+"world"); silme tuşu doğrulanmadığı için cevap verilmez.
            guard opts[i].freeText,
                  PromptParser.freeTextPrefixes.contains(where: { opts[i].label.hasPrefix($0) }) else { return nil }
            let t = sanitize(raw)
            return t.isEmpty ? nil : .some(t)
        }

        if !screen.multi {
            guard answer.checks.isEmpty, let i = answer.option, opts.indices.contains(i),
                  let text = typed(for: i) else { return nil }
            move(to: opts[i].stop)
            if let text { out += text }
            out += enter
        } else {
            // Yalnız kutulu satırlar işaretlenebilir: kutusuz "Chat about this" satırında Boşluk/Enter menüden çıkar.
            // Ara sayfada (başka cevapsız sekme var) Submit'in ne yaptığı doğrulanmadı: hiçbir şey gönderilmez.
            guard screen.finalPage, answer.option == nil, let submit = screen.submitStop,
                  answer.checks.allSatisfy({ opts.indices.contains($0) && opts[$0].checked != nil }) else { return nil }
            var want = Set(answer.checks)
            var freeIndex: Int?
            var freeText: String?
            if answer.text != nil {
                guard let i = opts.indices.first(where: { opts[$0].freeText && opts[$0].checked != nil }),
                      let t = typed(for: i) else { return nil }
                freeIndex = i; freeText = t
                want.remove(i)   // yazmak satırı kendiliğinden işaretler; ayrıca Boşluk basılmaz
            }
            // Metinsiz işaretlenmek istenen boş serbest satır ("Type something"): Boşluk'un orada ne yaptığı
            // doğrulanmadı (yazı moduna geçebilir); gönderilmez.
            for i in want where opts[i].freeText && opts[i].checked != true
                && PromptParser.freeTextPrefixes.contains(where: { opts[i].label.hasPrefix($0) }) {
                return nil
            }
            // Yalnız işareti istenenden farklı satırlara dokun; durak sırasıyla.
            var visits: [Int] = opts.indices.filter { (opts[$0].checked ?? false) != want.contains($0) && $0 != freeIndex }
            if let freeIndex { visits.append(freeIndex) }
            for i in visits.sorted(by: { opts[$0].stop < opts[$1].stop }) {
                move(to: opts[i].stop)
                out += (i == freeIndex) ? (freeText ?? "") : space
            }
            move(to: submit)
            out += enter + enter   // Submit, sonra "Review your answers" sayfasında Enter (yalnız son sayfada)
        }
        return out.data(using: .utf8)
    }

    /// Terminale yazılacak metinden kontrol dizilerini temizler: ESC [ … son bayt ve ESC + tek karakter
    /// atılır (boşluk bırakmaz); kalan kontrol karakterleri (\n \r \t, DEL, C0/C1) boşluğa döner.
    public static func sanitize(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var it = text.unicodeScalars.makeIterator()
        while let s = it.next() {
            if s.value == 0x1b {
                guard let n = it.next() else { break }
                if n == "[" {
                    while let c = it.next(), !(0x40...0x7e).contains(c.value) {}
                }
            } else if s.value < 0x20 || s.value == 0x7f || (0x80...0x9f).contains(s.value) {
                out.append(" ")
            } else {
                out.append(s)
            }
        }
        return String(out)
    }
}
