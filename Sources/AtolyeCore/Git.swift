import Foundation

/// Bir dosyanın git durumu. `code`: M (değişti), A (eklendi), D (silindi), R (yeniden adlandı), C, T, U (çakışma), ? (yeni).
public struct GitFileChange: Equatable, Sendable, Hashable {
    public var path: String
    public var code: String
    public var origPath: String?
}

/// `git status --porcelain=v2 --branch -z` çıktısı.
public struct GitStatus: Equatable, Sendable {
    public var branch: String?
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var staged: [GitFileChange] = []
    public var unstaged: [GitFileChange] = []
    public var untracked: [GitFileChange] = []

    /// Farklı dosya sayısı (hem hazırlanmış hem değişmiş olan bir kez sayılır).
    public var changedCount: Int { Set((staged + unstaged + untracked).map(\.path)).count }

    public static func parse(_ out: String) -> GitStatus {
        var s = GitStatus()
        var fields = out.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let f = fields.popFirst() {
            if f.hasPrefix("# branch.head ") {
                s.branch = String(f.dropFirst("# branch.head ".count))
            } else if f.hasPrefix("# branch.upstream ") {
                s.upstream = String(f.dropFirst("# branch.upstream ".count))
            } else if f.hasPrefix("# branch.ab ") {
                let p = f.split(separator: " ")
                if p.count >= 4 {
                    s.ahead = Int(p[2].dropFirst()) ?? 0
                    s.behind = Int(p[3].dropFirst()) ?? 0
                }
            } else if f.hasPrefix("? ") {
                s.untracked.append(GitFileChange(path: String(f.dropFirst(2)), code: "?"))
            } else if let kind = f.first, kind == "1" || kind == "2" || kind == "u" {
                // 1: 8 alan + yol; 2: 9 alan + yol, ardından eski yol ayrı alan; u: 10 alan + yol.
                let before = kind == "1" ? 8 : kind == "2" ? 9 : 10
                let parts = f.split(separator: " ", maxSplits: before, omittingEmptySubsequences: false)
                guard parts.count == before + 1 else { continue }
                let xy = Array(parts[1]), path = String(parts[before])
                let orig = kind == "2" ? fields.popFirst() : nil
                if kind == "u" {
                    s.unstaged.append(GitFileChange(path: path, code: "U"))
                    continue
                }
                if xy.count == 2, xy[0] != "." { s.staged.append(GitFileChange(path: path, code: String(xy[0]), origPath: orig)) }
                if xy.count == 2, xy[1] != "." { s.unstaged.append(GitFileChange(path: path, code: String(xy[1]), origPath: orig)) }
            }
        }
        return s
    }
}

public struct GitCommit: Equatable, Sendable, Hashable {
    public var short: String
    public var hash: String
    public var subject: String
    public var author: String
    public var date: Date

    /// `git log` için biçim; `parse` bunu okur.
    public static let format = "%h%x1f%H%x1f%s%x1f%an%x1f%at%x1e"
}

public enum GitLog {
    public static func parse(_ out: String) -> [GitCommit] {
        out.split(separator: "\u{1e}").compactMap { rec in
            let p = rec.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard p.count == 5, let t = TimeInterval(p[4]) else { return nil }
            return GitCommit(short: String(p[0]), hash: String(p[1]), subject: String(p[2]), author: String(p[3]),
                             date: Date(timeIntervalSince1970: t))
        }
    }
}

public struct DiffLine: Equatable, Sendable {
    public enum Kind: Sendable { case meta, hunk, add, del, context }
    public var kind: Kind
    public var text: String
}

public enum GitDiff {
    /// Birleşik diff satırlarını türlerine ayırır; `limit` satırdan sonrasını keser.
    public static func parse(_ out: String, limit: Int) -> [DiffLine] {
        var raw = out.split(separator: "\n", omittingEmptySubsequences: false)
        if raw.last == "" { raw.removeLast() }
        var lines: [DiffLine] = []
        var inHunk = false
        for (i, l) in raw.enumerated() {
            if lines.count == limit {
                lines.append(DiffLine(kind: .meta, text: L("… {0} satır daha (kesildi)", "\(raw.count - i)")))
                break
            }
            let s = String(l)
            let kind: DiffLine.Kind
            if s.hasPrefix("diff --git") || s.hasPrefix("commit ") && !inHunk {
                inHunk = false
                kind = .meta
            } else if s.hasPrefix("@@") {
                inHunk = true
                kind = .hunk
            } else if inHunk {
                kind = s.hasPrefix("+") ? .add : s.hasPrefix("-") ? .del : s.hasPrefix("\\") ? .meta : .context
            } else {
                kind = .meta
            }
            lines.append(DiffLine(kind: kind, text: s))
        }
        return lines
    }
}
