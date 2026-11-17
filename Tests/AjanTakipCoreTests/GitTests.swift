import Foundation
import Testing
@testable import AjanTakipCore

@Suite struct GitStatusTests {
    private func z(_ parts: [String]) -> String { parts.joined(separator: "\0") + "\0" }

    @Test func parsesBranchUpstreamAndCounts() {
        let out = z([
            "# branch.oid b61f62b0758ea2857dd949584873c6545691c25d",
            "# branch.head feat/todo",
            "# branch.upstream origin/feat/todo",
            "# branch.ab +3 -1",
            "1 M. N... 100644 100644 100644 aaa bbb Sources/A.swift",
            "1 .M N... 100644 100644 100644 aaa bbb Sources/B.swift",
            "1 MM N... 100644 100644 100644 aaa bbb README.md",
            "2 R. N... 100644 100644 100644 aaa bbb R100 docs/new name.md", "docs/old.md",
            "u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.txt",
            "? b c.txt",
        ])
        let s = GitStatus.parse(out)
        #expect(s.branch == "feat/todo" && s.upstream == "origin/feat/todo")
        #expect(s.ahead == 3 && s.behind == 1)
        #expect(s.staged.map(\.path) == ["Sources/A.swift", "README.md", "docs/new name.md"])
        #expect(s.staged.map(\.code) == ["M", "M", "R"])
        #expect(s.staged[2].origPath == "docs/old.md")
        #expect(s.unstaged.map(\.path) == ["Sources/B.swift", "README.md", "conflict.txt"])
        #expect(s.unstaged.last?.code == "U")
        #expect(s.untracked.map(\.path) == ["b c.txt"])
        #expect(s.changedCount == 6)
    }

    @Test func detachedHeadAndNoUpstream() {
        let s = GitStatus.parse(z(["# branch.oid abc", "# branch.head (detached)"]))
        #expect(s.branch == "(detached)" && s.upstream == nil && s.ahead == 0 && s.behind == 0)
        #expect(s.changedCount == 0)
    }
}

@Suite struct GitLogTests {
    @Test func parsesRecords() {
        let out = "5dba3c5\u{1f}5dba3c5ffff\u{1f}docs: tasarım\u{1f}Ali Can\u{1f}1794900000\u{1e}\n"
            + "7def023\u{1f}7def023eeee\u{1f}fix: sızıntı | a\u{1f}Ali Can\u{1f}1794800000\u{1e}\n"
        let log = GitLog.parse(out)
        #expect(log.map(\.short) == ["5dba3c5", "7def023"])
        #expect(log[1].subject == "fix: sızıntı | a" && log[1].hash == "7def023eeee")
        #expect(log[0].date == Date(timeIntervalSince1970: 1_794_900_000) && log[0].author == "Ali Can")
    }

    @Test func ignoresGarbage() {
        #expect(GitLog.parse("\n\nyarım\u{1f}kayıt\u{1e}").isEmpty)
    }
}

@Suite struct GitDiffTests {
    @Test func classifiesLines() {
        let out = """
        diff --git a/x.swift b/x.swift
        index 111..222 100644
        --- a/x.swift
        +++ b/x.swift
        @@ -1,3 +1,3 @@ func a()
         let a = 1
        --- eski yorum
        +++ yeni yorum
        \\ No newline at end of file
        """
        let lines = GitDiff.parse(out, limit: 100)
        #expect(lines.map(\.kind) == [.meta, .meta, .meta, .meta, .hunk, .context, .del, .add, .meta])
        #expect(lines[6].text == "--- eski yorum")
    }

    @Test func truncatesAtLimit() {
        let body = (0..<10).map { "+satır \($0)" }.joined(separator: "\n")
        let lines = GitDiff.parse("@@ -0,0 +1,10 @@\n" + body, limit: 5)
        #expect(lines.count == 6)
        #expect(lines.last?.kind == .meta && lines.last?.text.contains("kesildi") == true)
    }
}
