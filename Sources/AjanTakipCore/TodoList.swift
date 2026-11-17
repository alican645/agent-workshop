import Foundation

/// Markdown onay kutusu maddesi (`- [ ] metin`, `* [x] metin`, `+ [ ] metin`).
public struct TodoItem: Equatable, Sendable, Identifiable {
    /// 0 tabanlı satır numarası.
    public var line: Int
    public var done: Bool
    public var text: String
    /// Girinti düzeyi (2 boşluk veya 1 tab = 1).
    public var indent: Int
    /// Satırın özgün hali; dosya değiştiyse yazmayı reddetmek için.
    var raw: String
    public var id: Int { line }
}

public enum TodoList {
    public static let fileName = "TODO.local.md"

    /// Swift "\r\n"yi tek karakter saydığı için Foundation ile (UTF-16) bölünür; "\r" satırda kalır.
    private static func lines(_ text: String) -> [Substring] {
        text.components(separatedBy: "\n").map { Substring($0) }
    }

    private static func strippedCR(_ s: Substring) -> Substring {
        s.hasSuffix("\r") ? s.dropLast() : s
    }

    /// Satır bir onay kutusu maddesiyse (girinti, işaretli mi, metin, kutu içi karakterin konumu).
    private static func match(_ raw: Substring) -> (indent: Int, done: Bool, text: String, box: String.Index)? {
        let line = strippedCR(raw)
        var i = line.startIndex, spaces = 0
        while i < line.endIndex, line[i] == " " || line[i] == "\t" {
            spaces += line[i] == "\t" ? 2 : 1
            i = line.index(after: i)
        }
        let rest = line[i...]
        guard rest.count >= 5, let bullet = rest.first, "-*+".contains(bullet) else { return nil }
        let chars = Array(rest.prefix(5))
        guard chars[1] == " ", chars[2] == "[", chars[4] == "]", " xX".contains(chars[3]) else { return nil }
        let after = rest.dropFirst(5)
        guard after.isEmpty || after.first == " " else { return nil }
        let box = line.index(i, offsetBy: 3)
        return (spaces / 2, chars[3] != " ", after.trimmingCharacters(in: .whitespaces), box)
    }

    public static func parse(_ text: String) -> [TodoItem] {
        lines(text).enumerated().compactMap { n, raw in
            match(raw).map { TodoItem(line: n, done: $0.done, text: $0.text, indent: $0.indent, raw: String(raw)) }
        }
    }

    public static func progress(_ items: [TodoItem]) -> (done: Int, total: Int) {
        (items.filter(\.done).count, items.count)
    }

    /// Maddenin kutusunu çevirir; satır artık aynı değilse nil (dosya dışarıda değişmiş).
    public static func toggle(_ text: String, item: TodoItem) -> String? {
        var ls = lines(text)
        guard item.line < ls.count, ls[item.line] == item.raw, let m = match(ls[item.line]) else { return nil }
        var line = String(ls[item.line])
        let offset = ls[item.line].distance(from: ls[item.line].startIndex, to: m.box)
        let idx = line.index(line.startIndex, offsetBy: offset)
        line.replaceSubrange(idx...idx, with: m.done ? " " : "x")
        ls[item.line] = Substring(line)
        return ls.joined(separator: "\n")
    }

    /// Ajana gönderilecek metin: maddenin kendisi ve altındaki işaretlenmemiş alt maddeler.
    public static func prompt(for item: TodoItem, in items: [TodoItem]) -> String {
        var out = [item.text]
        if let start = items.firstIndex(where: { $0.line == item.line }) {
            for child in items[(start + 1)...] {
                guard child.indent > item.indent else { break }
                if child.done { continue }
                out.append(String(repeating: "  ", count: child.indent - item.indent - 1) + "- " + child.text)
            }
        }
        return out.joined(separator: "\n")
    }

    /// Yeni maddeyi son maddenin altına (yoksa dosya sonuna) ekler.
    public static func append(_ text: String, item: String) -> String {
        let clean = item.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !clean.isEmpty else { return text }
        let newLine = "- [ ] " + clean
        var ls = lines(text)
        if let last = parse(text).last {
            ls.insert(Substring(newLine), at: last.line + 1)
            return ls.joined(separator: "\n")
        }
        if text.isEmpty { return newLine + "\n" }
        return text + (text.hasSuffix("\n") ? "" : "\n") + newLine + "\n"
    }
}

public enum ProjectRoot {
    /// cwd'den yukarı doğru `.git` arar; bulamazsa cwd'nin kendisi.
    public static func find(cwd: String, exists: (String) -> Bool) -> String {
        var dir = cwd
        while dir.count > 1 && dir.hasSuffix("/") { dir.removeLast() }
        var cur = dir
        while true {
            if exists(cur + "/.git") { return cur }
            let parent = (cur as NSString).deletingLastPathComponent
            if parent == cur || parent.isEmpty { return dir }
            cur = parent
        }
    }

    public static func todoPath(root: String) -> String { root + "/" + TodoList.fileName }
}
