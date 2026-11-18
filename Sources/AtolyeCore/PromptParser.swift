import Foundation

public enum PromptKind: String, Codable, Sendable { case permission, question, plan }

public struct ScreenOption: Equatable, Sendable {
    public var label: String
    public var freeText: Bool
    public var checked: Bool?
    public init(label: String, freeText: Bool = false, checked: Bool? = nil) {
        self.label = label; self.freeText = freeText; self.checked = checked
    }
}

public struct ScreenPrompt: Equatable, Sendable {
    public var kind: PromptKind
    public var title: String?
    public var detail: String?
    public var options: [ScreenOption]
    public var selected: Int
    public var multi: Bool
    public var page: (index: Int, count: Int)?

    public init(kind: PromptKind, title: String?, detail: String?, options: [ScreenOption], selected: Int,
                multi: Bool, page: (index: Int, count: Int)?) {
        self.kind = kind; self.title = title; self.detail = detail; self.options = options
        self.selected = selected; self.multi = multi; self.page = page
    }

    public static func == (a: ScreenPrompt, b: ScreenPrompt) -> Bool {
        a.kind == b.kind && a.title == b.title && a.detail == b.detail && a.options == b.options
            && a.selected == b.selected && a.multi == b.multi
            && a.page?.index == b.page?.index && a.page?.count == b.page?.count
    }
}

/// Claude Code'un seçenek menüsünü (izin, AskUserQuestion, plan onayı) terminalin görünen satırlarından okur.
/// Kalıplar Claude Code 2.1.327 ekranlarından alındı (Tests/AtolyeCoreTests/Fixtures/prompts). Kural:
/// emin olunmayan her durumda `nil` — yanlış ayrıştırma yanlış cevap göndermek demektir.
///
/// Ekranın biçimi (alttan yukarı): boş satırlar; ipucu satırı ("Esc to cancel …"); boş satır(lar);
/// numaralı seçenek bloğu (`❯` imleçli satır, açıklama/kırılma satırları, `────` ayracı); başlık;
/// panelin geri kalanı (araç adı, komut, sekme şeridi); panelin üst `────` çizgisi.
public enum PromptParser {
    /// Menünün altındaki ipucu satırı. İzin: "Esc to cancel · Tab to amend";
    /// soru: "Enter to select · ↑/↓ to navigate · Esc to cancel"; plan: "ctrl+g to edit in Vim · <dosya>".
    static let footerMarks = ["Esc to cancel", "Enter to select", "ctrl+g to edit in Vim"]
    /// İzin başlığı: "Do you want to proceed?", "Do you want to make this edit to notes.txt?".
    static let permissionTitlePrefix = "Do you want to "
    /// Plan onayı başlığı: "Claude has written up a plan and is ready to execute. Would you like to proceed?".
    static let planTitleMarks = ["written up a plan", "Would you like to proceed?"]
    /// Seçilince yazı alan seçenekler. Soru: "Type something." (çoklu seçimde noktasız);
    /// plan: "Tell Claude what to change"; eski sürümlerin izni: "No, and tell Claude what to do differently".
    static let freeTextPrefixes = ["Type something", "Tell Claude what to change", "No, and tell Claude"]
    /// Çoklu seçim kutuları: "1. [ ] Apple", "1. [✔] Apple".
    static let checkboxes: [(String, Bool)] = [("[ ] ", false), ("[✔] ", true)]
    /// AskUserQuestion sekme şeridi: "←  ☐ Color  ☒ Size  ✔ Submit  →" (☐ cevapsız, ☒ cevaplı).
    static let tabOpen: Character = "☐", tabDone: Character = "☒"
    static let cursor: Character = "❯"

    /// `cursorRow` şimdilik kullanılmaz: Claude imleci gizleyip giriş kutusuna park eder, menüyle ilgisi yok.
    public static func parse(lines raw: [String], cursorRow: Int) -> ScreenPrompt? {
        let lines = raw.map(rtrim)
        // 1) İpucu satırı; altında yalnız boş satır olabilir (giriş kutusu ya da başka çizim → eski menü).
        guard let footer = lines.lastIndex(where: { l in footerMarks.contains { l.contains($0) } }),
              lines[(footer + 1)...].allSatisfy(\.isEmpty) else { return nil }
        var bottom = footer - 1
        while bottom >= 0 && lines[bottom].isEmpty { bottom -= 1 }
        guard bottom >= 0 else { return nil }
        var top = bottom
        while top > 0 && !lines[top - 1].isEmpty { top -= 1 }

        // 2) Bu kesintisiz bölgede menü, en alttaki "1." satırından başlar.
        guard let start = (top...bottom).last(where: { numbered(lines[$0])?.number == 1 }),
              let first = numbered(lines[start]) else { return nil }
        let width = lines.map(\.count).max() ?? 0

        var options: [ScreenOption] = []
        var beforeRule: Set<Int> = []
        var selected: Int?
        var lastLabelLine = ""
        for i in start...bottom {
            let line = lines[i]
            if let n = numbered(line) {
                guard n.column == first.column, n.number == options.count + 1 else { return nil }
                if n.cursor {
                    guard selected == nil else { return nil }
                    selected = options.count
                }
                var label = n.rest
                var checked: Bool?
                for (box, value) in checkboxes where label.hasPrefix(box) {
                    checked = value
                    label = String(label.dropFirst(box.count))
                }
                options.append(ScreenOption(label: label, checked: checked))
                lastLabelLine = line
            } else if isRule(line, "─") {
                beforeRule.insert(options.count - 1)
            } else {
                // Açıklama ya da kırılmış etiket: numaranın sağından başlamalı; imleç burada olamaz.
                let indent = line.prefix { $0 == " " }.count
                guard indent >= first.column + 2, !line.contains(cursor) else { return nil }
                let text = line.trimmingCharacters(in: .whitespaces)
                let firstWord = text.prefix { $0 != " " }
                if !lastLabelLine.isEmpty && lastLabelLine.count + 1 + firstWord.count > width {
                    // Satır sığmadığı için kırılmış (ör. uzun klasör yolu); "-" ya da "/" ile bittiyse boşluksuz.
                    let glue = (options[options.count - 1].label.last).map { "-/".contains($0) } == true ? "" : " "
                    options[options.count - 1].label += glue + text
                    lastLabelLine = line
                } else {
                    lastLabelLine = ""   // açıklama başladı; sonraki satırlar etikete eklenmez
                }
            }
        }
        guard options.count >= 2, let selected else { return nil }

        // 3) Başlık ve panel: menünün üstündeki ilk dolu satır; panel üst çizgiye kadar.
        guard let titleRow = (0..<start).last(where: { !lines[$0].isEmpty }),
              let panelTop = (0..<titleRow).last(where: { isRule(lines[$0], "─") }) else { return nil }
        let title = lines[titleRow].trimmingCharacters(in: .whitespaces)
        let panel = Array(lines[(panelTop + 1)..<titleRow])
        let strip = panel.first { $0.contains(tabOpen) || $0.contains(tabDone) }

        let kind: PromptKind
        if title.hasPrefix(permissionTitlePrefix) {
            kind = .permission
        } else if planTitleMarks.contains(where: { title.contains($0) }) {
            kind = .plan
        } else if strip != nil {
            kind = .question
        } else {
            return nil
        }
        let multi = options.contains { $0.checked != nil }
        guard !multi || kind == .question else { return nil }

        for i in options.indices {
            // Soruda serbest metin satırı "Chat about this" ayracının hemen üstündedir; yazı yazılınca
            // etiketi değişse de (ör. "hello") yerinden tanınır.
            options[i].freeText = freeTextPrefixes.contains { options[i].label.hasPrefix($0) }
                || (kind == .question && beforeRule.contains(i))
        }

        var page: (index: Int, count: Int)?
        if let strip {
            let marks = strip.filter { $0 == tabOpen || $0 == tabDone }
            if marks.count > 1 {
                // Açık sekme yalnız renkle belli; ilk cevapsız sekme sayılır. Hepsi cevaplıysa emin değiliz.
                guard let open = marks.firstIndex(of: tabOpen) else { return nil }
                page = (marks.distance(from: marks.startIndex, to: open), marks.count)
            }
        }

        var detail: String?
        if kind == .permission {
            // Panelin ilk satırı araç adı ("Bash command", "Edit file"); ipucu ve çizgiler atlanır.
            let body = panel.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("Tip:") && !isRule($0, "╌") && !isRule($0, "─") }
                .dropFirst()
            detail = body.isEmpty ? nil : body.joined(separator: "\n")
        }

        return ScreenPrompt(kind: kind, title: title, detail: detail, options: options, selected: selected,
                            multi: multi, page: page)
    }

    /// "  ❯ 3. Etiket" → (3, imleç var, rakamın sütunu, "Etiket").
    static func numbered(_ line: String) -> (number: Int, cursor: Bool, column: Int, rest: String)? {
        let chars = Array(line)
        var i = 0
        func skipSpaces() { while i < chars.count && chars[i].isWhitespace { i += 1 } }
        skipSpaces()
        var hasCursor = false
        if i < chars.count && chars[i] == cursor { hasCursor = true; i += 1; skipSpaces() }
        let column = i
        while i < chars.count && chars[i].isASCII && chars[i].isNumber { i += 1 }
        guard i > column, i - column <= 2, let number = Int(String(chars[column..<i])),
              i + 1 < chars.count, chars[i] == ".", chars[i + 1].isWhitespace else { return nil }
        i += 1
        skipSpaces()
        let rest = String(chars[i...])
        guard !rest.isEmpty else { return nil }
        return (number, hasCursor, column, rest)
    }

    /// Yalnız `ch` karakterinden oluşan (baştaki boşluklar hariç) en az 10 karakterlik çizgi.
    static func isRule(_ line: String, _ ch: Character) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.count >= 10 && t.allSatisfy { $0 == ch }
    }

    static func rtrim(_ s: String) -> String {
        var s = s
        while s.last?.isWhitespace == true { s.removeLast() }
        return s
    }
}
