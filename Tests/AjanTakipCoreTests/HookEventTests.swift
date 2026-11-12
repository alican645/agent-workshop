import Foundation
import Testing
@testable import AjanTakipCore

private func body(_ s: String) -> Data { Data(s.utf8) }

@Suite struct HookEventTests {
    @Test func parsesPreToolUseWithFilePath() throws {
        let e = try HookEvent.parse(
            body: body(#"{"session_id":"s1","hook_event_name":"PreToolUse","cwd":"/x/erp-api","tool_name":"Edit","tool_input":{"file_path":"/x/erp-api/Order.cs"}}"#),
            headers: ["x-cmux-workspace": "W1", "x-cmux-surface": "S1", "x-claude-pid": "123"])
        #expect(e.sessionID == "s1")
        #expect(e.name == .preToolUse)
        #expect(e.cwd == "/x/erp-api")
        #expect(e.toolName == "Edit")
        #expect(e.toolTarget == "Order.cs")
        #expect(e.workspace == "W1")
        #expect(e.surface == "S1")
        #expect(e.pid == 123)
    }

    @Test func bashTargetIsSingleLineTruncated() throws {
        let cmd = "echo a\n" + String(repeating: "x", count: 100)
        let json = try JSONSerialization.data(withJSONObject: [
            "session_id": "s", "hook_event_name": "PreToolUse", "tool_name": "Bash",
            "tool_input": ["command": cmd],
        ])
        let e = try HookEvent.parse(body: json, headers: [:])
        #expect(e.toolTarget == "echo a " + String(repeating: "x", count: 33) + "…")
    }

    @Test func notificationPermissionByType() throws {
        let p = try HookEvent.parse(body: body(#"{"session_id":"s","hook_event_name":"Notification","notification_type":"permission_prompt"}"#), headers: [:])
        #expect(p.notificationKind == .permission)
        let i = try HookEvent.parse(body: body(#"{"session_id":"s","hook_event_name":"Notification","notification_type":"idle_prompt"}"#), headers: [:])
        #expect(i.notificationKind == .idle)
    }

    @Test func notificationPermissionByMessageFallback() throws {
        func kind(_ msg: String) throws -> NotificationKind? {
            try HookEvent.parse(body: body(#"{"session_id":"s","hook_event_name":"Notification","message":"\#(msg)"}"#), headers: [:]).notificationKind
        }
        #expect(try kind("Claude needs your permission to use Bash") == .permission)
        #expect(try kind("Claude is waiting for your input") == .idle)
        #expect(try kind("Something else") == .other)
    }

    @Test func emptyHeadersBecomeNil() throws {
        let e = try HookEvent.parse(body: body(#"{"session_id":"s","hook_event_name":"Stop"}"#),
                                    headers: ["x-cmux-workspace": "", "x-cmux-surface": "", "x-claude-pid": ""])
        #expect(e.workspace == nil)
        #expect(e.surface == nil)
        #expect(e.pid == nil)
    }

    @Test func unknownEventName() throws {
        let e = try HookEvent.parse(body: body(#"{"session_id":"s","hook_event_name":"PreCompact"}"#), headers: [:])
        #expect(e.name == .unknown("PreCompact"))
    }

    @Test func missingSessionIDThrows() {
        #expect(throws: HookEventError.missingSessionID) {
            try HookEvent.parse(body: body(#"{"hook_event_name":"Stop"}"#), headers: [:])
        }
    }

    @Test func invalidJSONThrows() {
        #expect(throws: HookEventError.invalidJSON) {
            try HookEvent.parse(body: body("not json"), headers: [:])
        }
    }
}
