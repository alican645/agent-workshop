import Foundation
import Testing
@testable import AtolyeCore

@Suite struct TodoEditTests {
    let text = "# Liste\n- [ ] bir\n  - [x] bir alt\n- [ ] iki\n* [ ] üç\n"
    func item(_ t: String, in s: String) -> TodoItem { TodoList.parse(s).first { $0.text == t }! }

    @Test func deleteRemovesItemWithChildren() {
        #expect(TodoList.delete(text, item: item("bir", in: text)) == "# Liste\n- [ ] iki\n* [ ] üç\n")
        #expect(TodoList.delete(text, item: item("iki", in: text)) == "# Liste\n- [ ] bir\n  - [x] bir alt\n* [ ] üç\n")
    }

    @Test func editKeepsBulletBoxAndIndent() {
        #expect(TodoList.edit(text, item: item("bir alt", in: text), to: "  yeni ad ") == "# Liste\n- [ ] bir\n  - [x] yeni ad\n- [ ] iki\n* [ ] üç\n")
        #expect(TodoList.edit(text, item: item("iki", in: text), to: "   ") == nil)
    }

    @Test func indentAndOutdent() {
        let s = TodoList.indent(text, item: item("iki", in: text), by: 1)!
        #expect(s == "# Liste\n- [ ] bir\n  - [x] bir alt\n  - [ ] iki\n* [ ] üç\n")
        #expect(TodoList.indent(s, item: item("iki", in: s), by: -1) == text)
        #expect(TodoList.indent(text, item: item("bir", in: text), by: -1) == nil)
    }

    @Test func moveCarriesChildren() {
        // "bir" (ve alt maddesi) "üç"ün önüne
        #expect(TodoList.move(text, item: item("bir", in: text), before: item("üç", in: text))
                == "# Liste\n- [ ] iki\n- [ ] bir\n  - [x] bir alt\n* [ ] üç\n")
        // sona
        #expect(TodoList.move(text, item: item("iki", in: text), before: nil)
                == "# Liste\n- [ ] bir\n  - [x] bir alt\n* [ ] üç\n- [ ] iki\n")
        // en başa
        #expect(TodoList.move(text, item: item("üç", in: text), before: item("bir", in: text))
                == "# Liste\n* [ ] üç\n- [ ] bir\n  - [x] bir alt\n- [ ] iki\n")
    }

    @Test func moveIntoOwnChildrenIsRefused() {
        #expect(TodoList.move(text, item: item("bir", in: text), before: item("bir alt", in: text)) == nil)
    }

    @Test func staleItemIsRefused() {
        let old = item("iki", in: text)
        let changed = text.replacingOccurrences(of: "- [ ] iki", with: "- [ ] iki!")
        #expect(TodoList.delete(changed, item: old) == nil)
        #expect(TodoList.edit(changed, item: old, to: "x") == nil)
    }
}

@Suite struct GitExcludeTests {
    @Test func addsOnce() {
        #expect(GitExclude.adding("", GitExclude.todoEntry) == "/TODO.local.md\n")
        #expect(GitExclude.adding("# git ls-files\n*.log", GitExclude.todoEntry) == "# git ls-files\n*.log\n/TODO.local.md\n")
        #expect(GitExclude.adding("/TODO.local.md\n", GitExclude.todoEntry) == "/TODO.local.md\n")
    }

    @Test func removesOurEntryOnly() {
        #expect(GitExclude.removing("*.log\n/TODO.local.md\nx\n", GitExclude.todoEntry) == "*.log\nx\n")
        #expect(GitExclude.removing("*.log\n", GitExclude.todoEntry) == "*.log\n")
    }
}

@Suite(.serialized) struct TodoGitTests {
    func repo() -> String {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("todogit-\(UUID().uuidString)").path
        try! FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        _ = GitRunner.run(["init", "-q"], in: d)
        return d
    }
    func exclude(_ root: String) -> String { (try? String(contentsOfFile: root + "/.git/info/exclude", encoding: .utf8)) ?? "" }
    func tracked(_ root: String) -> Bool { GitRunner.run(["ls-files", "--error-unmatch", "TODO.local.md"], in: root) != nil }

    @Test func notRepo() {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("plain-\(UUID().uuidString)").path
        try! FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        #expect(TodoGit.state(root: d) == .notRepo)
    }

    @Test func keepLocalExcludesNewFile() throws {
        let root = repo()
        try TodoFile.add("bir", root: root)
        #expect(TodoGit.state(root: root) == .local)
        try TodoGit.keepLocal(root: root)
        #expect(exclude(root).contains("/TODO.local.md"))
        #expect(GitRunner.run(["status", "--porcelain"], in: root) == "")
    }

    @Test func keepLocalLeavesIgnoredFileAlone() throws {
        let root = repo()
        try "TODO.local.md\n".write(toFile: root + "/.gitignore", atomically: true, encoding: .utf8)
        try TodoFile.add("bir", root: root)
        try TodoGit.keepLocal(root: root)
        #expect(!exclude(root).contains("/TODO.local.md"))
    }

    @Test func shareThenUnshare() throws {
        let root = repo()
        try TodoFile.add("bir", root: root)
        try TodoGit.keepLocal(root: root)
        try TodoGit.share(root: root)
        #expect(TodoGit.state(root: root) == .shared)
        #expect(tracked(root))
        #expect(!exclude(root).contains("/TODO.local.md"))

        try TodoGit.unshare(root: root)
        #expect(TodoGit.state(root: root) == .local)
        #expect(!tracked(root))
        #expect(exclude(root).contains("/TODO.local.md"))
        #expect(FileManager.default.fileExists(atPath: ProjectRoot.todoPath(root: root)))
    }

    @Test func shareCreatesMissingFile() throws {
        let root = repo()
        try TodoGit.share(root: root)
        #expect(tracked(root))
    }
}
