import Foundation
import Testing
@testable import AtolyeCore

/// Koddaki her `L("…")` ve sahnedeki her `t('…')` için İngilizce sözlükte karşılık olmalı.
@Suite struct TranslationCoverageTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var table: [String: String] { L10n.loadTable(root.appendingPathComponent("Sources/Atolye/Web/i18n/en.json")) }

    static func keys() throws -> [(file: String, key: String)] {
        var out: [(String, String)] = []
        let swiftKey = try Regex(#"\b(?:L|L10n\.translate)\("((?:[^"\\]|\\.)*)""#)
        let jsKey = try Regex(#"\bt\('((?:[^'\\]|\\.)*)'"#)
        let htmlKey = try Regex(#"data-i18n>([^<]+)<"#)
        let fm = FileManager.default
        let src = root.appendingPathComponent("Sources")
        for case let path as String in fm.enumerator(atPath: src.path)! {
            guard !path.contains("/vendor/") else { continue }
            let ext = (path as NSString).pathExtension
            guard ["swift", "html", "mjs"].contains(ext),
                  let all = try? String(contentsOf: src.appendingPathComponent(path), encoding: .utf8) else { continue }
            let text = all.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            let regexes = ext == "swift" ? [swiftKey] : [jsKey, htmlKey]
            for r in regexes {
                for m in text.matches(of: r) {
                    let raw = String(m.output[1].substring ?? "")
                    let key = raw.replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\'"#, with: "'")
                        .replacingOccurrences(of: #"\n"#, with: "\n")
                    out.append((path, key))
                }
            }
        }
        return out
    }

    @Test func everyKeyHasEnglish() throws {
        let t = Self.table
        let missing = try Self.keys().filter { t[$0.key] == nil }.map { "\($0.file): \($0.key)" }
        #expect(missing.isEmpty, "çevirisi eksik:\n\(Set(missing).sorted().joined(separator: "\n"))")
    }

    @Test func placeholdersMatch() {
        let ph = try! Regex(#"\{\d\}"#)
        for (k, v) in Self.table {
            let a = Set(k.matches(of: ph).map { String(k[$0.range]) }), b = Set(v.matches(of: ph).map { String(v[$0.range]) })
            #expect(a == b, "yer tutucular farklı: \(k) → \(v)")
        }
    }

    @Test func noUnusedEntries() throws {
        let used = Set(try Self.keys().map(\.key))
        let unused = Self.table.keys.filter { !used.contains($0) }.sorted()
        #expect(unused.isEmpty, "kullanılmayan çeviriler:\n\(unused.joined(separator: "\n"))")
    }
}
