import Foundation
import Testing
@testable import AtolyeCore

@Suite struct HookInboxTests {
    private let now = Date(timeIntervalSince1970: 1000)

    private func event(_ json: String) throws -> HookEvent {
        try #require(HookEvent.parse(Data(json.utf8)))
    }

    private func decision(_ json: String) throws -> [String: Any] {
        let o = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let h = try #require(o["hookSpecificOutput"] as? [String: Any])
        #expect(h["hookEventName"] as? String == "PermissionRequest")
        return try #require(h["decision"] as? [String: Any])
    }

    private let bash = """
    {"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"Bash",
     "tool_input":{"command":"touch x","description":"Make x"},
     "permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"touch x"}],"behavior":"allow","destination":"localSettings"}]}
    """

    private let ask = """
    {"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion",
     "tool_input":{"questions":[{"question":"Color?","header":"C","multiSelect":false,
       "options":[{"label":"Red","description":"warm"},{"label":"Blue","description":""}]}]}}
    """

    @Test func parsesHookInput() throws {
        let e = try event(bash)
        #expect(e.event == "PermissionRequest" && e.session == "s1" && e.tool == "Bash")
        #expect(e.input["command"]?.string == "touch x")
        #expect(e.suggestions != nil)
        #expect(HookEvent.parse(Data("{\"hook_event_name\":\"X\"}".utf8)) == nil)
        #expect(HookEvent.parse(Data("not json".utf8)) == nil)
    }

    @Test func onlyPermissionRequestsAreHeld() throws {
        var box = HookInbox()
        #expect(!box.receive(try event(#"{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{}}"#), id: "a", now: now))
        #expect(box.receive(try event(bash), id: "r1", now: now))
        #expect(box.current(session: "s1")?.id == "r1")
        #expect(box.current(session: "s2") == nil)
    }

    @Test func permissionMenu() throws {
        var box = HookInbox()
        _ = box.receive(try event(bash), id: "r1", now: now)
        let info = HookInbox.info(try #require(box.current(session: "s1")))
        #expect(info.kind == .permission && info.answerable)
        #expect(info.options.map(\.label) == ["Yes", "Yes, and don't ask again", "No"])
        #expect(info.detail == "Bash: touch x")
        #expect(info.menuId == "hook:r1:0")
    }

    @Test func permissionAnswers() throws {
        for (option, behavior, rules) in [(0, "allow", false), (1, "allow", true), (2, "deny", false)] {
            var box = HookInbox()
            _ = box.receive(try event(bash), id: "r1", now: now)
            let labels = HookInbox.info(try #require(box.current(session: "s1"))).options.map(\.label)
            let r = box.answer(PromptAnswer(option: option, labels: labels, menuId: "hook:r1:0"), session: "s1")
            guard case let .reply(id, json)? = r else { Issue.record("cevap yok"); continue }
            #expect(id == "r1")
            let d = try decision(json)
            #expect(d["behavior"] as? String == behavior)
            #expect((d["updatedPermissions"] != nil) == rules)
            #expect((d["message"] != nil) == (behavior == "deny"))
            #expect(box.current(session: "s1") == nil)
        }
    }

    @Test func staleOrForeignAnswerIsRejected() throws {
        var box = HookInbox()
        _ = box.receive(try event(bash), id: "r1", now: now)
        let labels = ["Yes", "Yes, and don't ask again", "No"]
        #expect(box.answer(PromptAnswer(option: 0, labels: labels, menuId: "hook:r0:0"), session: "s1") == nil)
        #expect(box.answer(PromptAnswer(option: 0, labels: ["Yes", "No"], menuId: "hook:r1:0"), session: "s1") == nil)
        #expect(box.answer(PromptAnswer(option: 9, labels: labels, menuId: "hook:r1:0"), session: "s1") == nil)
        #expect(box.answer(PromptAnswer(option: 0, labels: labels, menuId: "hook:r1:0"), session: "s2") == nil)
        #expect(box.current(session: "s1")?.id == "r1")
    }

    @Test func questionMenuAndAnswer() throws {
        var box = HookInbox()
        _ = box.receive(try event(ask), id: "q", now: now)
        let info = HookInbox.info(try #require(box.current(session: "s1")))
        #expect(info.kind == .question && info.question == "Color?")
        #expect(info.options.map(\.label) == ["Red", "Blue", "Type something."])
        #expect(info.options[0].description == "warm" && info.options[1].description == nil)
        #expect(info.options[2].freeText && info.page == nil)
        let r = box.answer(PromptAnswer(option: 1, labels: info.options.map(\.label), menuId: info.menuId), session: "s1")
        guard case let .reply(_, json)? = r else { Issue.record("cevap yok"); return }
        let d = try decision(json)
        #expect(d["behavior"] as? String == "allow")
        let input = try #require(d["updatedInput"] as? [String: Any])
        #expect(input["answers"] as? [String: String] == ["Color?": "Blue"])
        #expect((input["questions"] as? [Any])?.count == 1)
    }

    @Test func freeTextNeedsText() throws {
        var box = HookInbox()
        _ = box.receive(try event(ask), id: "q", now: now)
        let labels = ["Red", "Blue", "Type something."]
        #expect(box.answer(PromptAnswer(option: 2, text: "  ", labels: labels, menuId: "hook:q:0"), session: "s1") == nil)
        let r = box.answer(PromptAnswer(option: 2, text: "Green", labels: labels, menuId: "hook:q:0"), session: "s1")
        guard case let .reply(_, json)? = r else { Issue.record("cevap yok"); return }
        #expect((try decision(json)["updatedInput"] as? [String: Any])?["answers"] as? [String: String] == ["Color?": "Green"])
    }

    @Test func multiQuestionPagesAndMultiSelect() throws {
        var box = HookInbox()
        _ = box.receive(try event("""
        {"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[
          {"question":"Food?","options":[{"label":"A"},{"label":"B"}]},
          {"question":"Fun?","multiSelect":true,"options":[{"label":"X"},{"label":"Y"},{"label":"Z"}]}]}}
        """), id: "m", now: now)
        let p0 = HookInbox.info(try #require(box.current(session: "s1")))
        #expect(p0.page == 0 && p0.pages == 2 && p0.menuId == "hook:m:0")
        #expect(box.answer(PromptAnswer(option: 0, labels: p0.options.map(\.label), menuId: p0.menuId), session: "s1") == .next)
        let p1 = HookInbox.info(try #require(box.current(session: "s1")))
        #expect(p1.page == 1 && p1.multi && p1.options.map(\.label) == ["X", "Y", "Z"])
        #expect(p1.options.allSatisfy { $0.checked == false })
        #expect(box.answer(PromptAnswer(checks: [], labels: p1.options.map(\.label), menuId: p1.menuId), session: "s1") == nil)
        let r = box.answer(PromptAnswer(checks: [0, 2], labels: p1.options.map(\.label), menuId: p1.menuId), session: "s1")
        guard case let .reply(_, json)? = r else { Issue.record("cevap yok"); return }
        let answers = (try decision(json)["updatedInput"] as? [String: Any])?["answers"] as? [String: String]
        #expect(answers == ["Food?": "A", "Fun?": "X, Z"])
    }

    @Test func planApproval() throws {
        var box = HookInbox()
        _ = box.receive(try event(##"{"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode","tool_input":{"plan":"# P","planFilePath":"/tmp/p.md"}}"##), id: "p", now: now)
        let info = HookInbox.info(try #require(box.current(session: "s1")))
        #expect(info.kind == .plan && info.options.map(\.label) == ["Yes", "No"])
        let r = box.answer(PromptAnswer(option: 1, labels: ["Yes", "No"], menuId: "hook:p:0"), session: "s1")
        guard case let .reply(_, json)? = r else { Issue.record("cevap yok"); return }
        let d = try decision(json)
        #expect(d["behavior"] as? String == "deny" && (d["message"] as? String)?.contains("plan") == true)
    }

    @Test func answeredInTerminalIsReleased() throws {
        var box = HookInbox()
        _ = box.receive(try event(ask), id: "q", now: now)
        _ = box.receive(try event(bash), id: "b", now: now)
        // PostToolUse girdisinde cevaplar da var; yine aynı istek sayılır.
        let post = try event("""
        {"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Color?","header":"C","multiSelect":false,
          "options":[{"label":"Red","description":"warm"},{"label":"Blue","description":""}]}],"answers":{"Color?":"Red"}}}
        """)
        #expect(box.toolFinished(post) == ["q"])
        #expect(box.toolFinished(post) == [])
        #expect(box.current(session: "s1")?.id == "b")
    }

    @Test func dropsWhenSessionStopsWaiting() throws {
        var box = HookInbox()
        _ = box.receive(try event(bash), id: "b", now: now)
        // Kayıt henüz "bekliyor" demediyse yeni istek hemen atılmaz.
        #expect(box.drop(waiting: [], live: ["s1"], now: now.addingTimeInterval(1)) == [])
        #expect(box.drop(waiting: ["s1"], live: ["s1"], now: now.addingTimeInterval(60)) == [])
        #expect(box.drop(waiting: [], live: ["s1"], now: now.addingTimeInterval(60)) == ["b"])
    }
}
