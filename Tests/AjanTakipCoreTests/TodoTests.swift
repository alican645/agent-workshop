import Foundation
import Testing
@testable import AjanTakipCore

@Suite struct TodoListTests {
    let text = """
        # Yapılacaklar
        - [ ] hesap testini yap
          - [x] alt madde
        * [X] CPU penceresi
        - normal madde
        + [ ] izin spike

        not
        """

    @Test func parsesCheckboxItemsOnly() {
        let items = TodoList.parse(text)
        #expect(items.map(\.text) == ["hesap testini yap", "alt madde", "CPU penceresi", "izin spike"])
        #expect(items.map(\.done) == [false, true, true, false])
        #expect(items.map(\.line) == [1, 2, 3, 5])
        #expect(items[1].indent == 1)
        #expect(items[0].indent == 0)
    }

    @Test func progress() {
        let p = TodoList.progress(TodoList.parse(text))
        #expect(p.done == 2 && p.total == 4)
    }

    @Test func toggleFlipsOnlyThatLine() throws {
        let items = TodoList.parse(text)
        let t1 = try #require(TodoList.toggle(text, item: items[0]))
        #expect(t1.split(separator: "\n", omittingEmptySubsequences: false)[1] == "- [x] hesap testini yap")
        #expect(t1.replacingOccurrences(of: "- [x] hesap", with: "- [ ] hesap") == text)
        let t2 = try #require(TodoList.toggle(text, item: items[2]))
        #expect(t2.contains("* [ ] CPU penceresi"))
    }

    @Test func toggleRefusesWhenFileChanged() {
        let item = TodoList.parse(text)[0]
        let changed = text.replacingOccurrences(of: "hesap testini yap", with: "başka")
        #expect(TodoList.toggle(changed, item: item) == nil)
    }

    @Test func toggleKeepsCRLFAndTrailingNewline() throws {
        let t = "- [ ] a\r\n- [ ] b\r\n"
        let r = try #require(TodoList.toggle(t, item: TodoList.parse(t)[1]))
        #expect(r == "- [ ] a\r\n- [x] b\r\n")
    }

    @Test func appendAfterLastTopLevelItem() {
        #expect(TodoList.append(text, item: "yeni iş").contains("+ [ ] izin spike\n- [ ] yeni iş\n\nnot"))
    }

    @Test func appendToEmptyOrNoItems() {
        #expect(TodoList.append("", item: "a") == "- [ ] a\n")
        #expect(TodoList.append("# Başlık", item: "a") == "# Başlık\n- [ ] a\n")
    }

    @Test func appendSanitizes() {
        #expect(TodoList.append("", item: "  çok\nsatır  ") == "- [ ] çok satır\n")
        #expect(TodoList.append("x\n", item: "   ") == "x\n")
    }
}

@Suite struct TodoPromptTests {
    let text = """
        - [ ] hesap ekranı
          - [ ] kota çubuğu
          - [x] bitti alt
            - [ ] derin
        - [ ] sonraki
        """

    @Test func includesOpenChildrenOnly() {
        let items = TodoList.parse(text)
        #expect(TodoList.prompt(for: items[0], in: items) == "hesap ekranı\n- kota çubuğu\n  - derin")
    }

    @Test func leafItemIsJustText() {
        let items = TodoList.parse(text)
        #expect(TodoList.prompt(for: items[4], in: items) == "sonraki")
        #expect(TodoList.prompt(for: items[1], in: items) == "kota çubuğu")
    }
}

@Suite struct ProjectRootTests {
    @Test func findsGitRootUpwards() {
        let existing: Set<String> = ["/p/app/.git"]
        #expect(ProjectRoot.find(cwd: "/p/app/Sources/x", exists: existing.contains) == "/p/app")
        #expect(ProjectRoot.find(cwd: "/p/app", exists: existing.contains) == "/p/app")
    }

    @Test func fallsBackToCwd() {
        #expect(ProjectRoot.find(cwd: "/tmp/x/", exists: { _ in false }) == "/tmp/x")
    }

    @Test func todoPath() {
        #expect(ProjectRoot.todoPath(root: "/p/app") == "/p/app/TODO.local.md")
    }
}
