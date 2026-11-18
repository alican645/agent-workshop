import Foundation

/// Kullanıcının balonda verdiği cevap. Tek seçimde `option`, çoklu seçimde `checks` (istenen işaretli küme).
/// `text` yalnız serbest metin seçeneği içindir. `labels`: balonun gösterdiği etiketler.
public struct PromptAnswer: Equatable, Sendable {
    public var option: Int?
    public var checks: [Int]
    public var text: String?
    public var labels: [String]
    public init(option: Int? = nil, checks: [Int] = [], text: String? = nil, labels: [String]) {
        self.option = option; self.checks = checks; self.text = text; self.labels = labels
    }
}

/// Cevabı terminale gidecek tuşlara çevirir (Claude Code 2.1.327, bkz. Fixtures/prompts/README.md).
/// Gezinme indekse değil ok tuşu duraklarına (`stop`) göre; en üst/alt sınırda sarma denenmediği için
/// sınır dışına hiç basılmaz. Emin olunmayan her durumda nil.
public enum PromptKeys {
    static let up = "\u{1b}[A", down = "\u{1b}[B", enter = "\r", space = " "

    public static func keys(for answer: PromptAnswer, on screen: ScreenPrompt?) -> Data? {
        guard let screen, answer.labels == screen.options.map(\.label),
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
            guard opts[i].freeText else { return nil }
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
            guard answer.option == nil, let submit = screen.submitStop,
                  answer.checks.allSatisfy(opts.indices.contains) else { return nil }
            var want = Set(answer.checks)
            var freeIndex: Int?
            var freeText: String?
            if answer.text != nil {
                guard let i = opts.indices.first(where: { opts[$0].freeText }),
                      let t = typed(for: i) else { return nil }
                freeIndex = i; freeText = t
                want.remove(i)   // yazmak satırı kendiliğinden işaretler; ayrıca Boşluk basılmaz
            }
            // Yalnız işareti istenenden farklı satırlara dokun; durak sırasıyla.
            var visits: [Int] = opts.indices.filter { (opts[$0].checked ?? false) != want.contains($0) && $0 != freeIndex }
            if let freeIndex { visits.append(freeIndex) }
            for i in visits.sorted(by: { opts[$0].stop < opts[$1].stop }) {
                move(to: opts[i].stop)
                out += (i == freeIndex) ? (freeText ?? "") : space
            }
            move(to: submit)
            out += enter + enter   // Submit, sonra "Review your answers" sayfasında Enter
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
