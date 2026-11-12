import Foundation
import Testing
@testable import AjanTakipCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

private func ev(_ name: HookEventName, _ sid: String = "s1", cwd: String? = "/x/erp-api",
                tool: String? = nil, target: String? = nil, notif: NotificationKind? = nil,
                ws: String? = nil, surface: String? = nil, pid: Int32? = nil) -> HookEvent {
    HookEvent(sessionID: sid, name: name, cwd: cwd, toolName: tool, toolTarget: target,
              notificationKind: notif, workspace: ws, surface: surface, pid: pid)
}

@Suite struct SessionStoreTests {
    @Test func sessionStartCreatesIdle() {
        var s = SessionStore()
        #expect(s.apply(ev(.sessionStart), now: t0) == nil)
        #expect(s.sessions.count == 1)
        let x = s.sessions[0]
        #expect(x.id == "s1")
        #expect(x.state == .idle)
        #expect(x.activity == "boşta")
        #expect(x.projectName == "erp-api")
        var s2 = SessionStore()
        _ = s2.apply(ev(.sessionStart, cwd: nil), now: t0)
        #expect(s2.sessions[0].projectName == "?")
    }

    @Test func unseenSessionCreatedByAnyEvent() {
        var s = SessionStore()
        _ = s.apply(ev(.preToolUse, tool: "Edit", target: "Order.cs"), now: t0)
        #expect(s.sessions.count == 1)
        #expect(s.sessions[0].state == .working)
        #expect(s.sessions[0].activity == "Edit Order.cs")
    }

    @Test func promptSubmitIsThinking() {
        var s = SessionStore()
        _ = s.apply(ev(.userPromptSubmit), now: t0)
        #expect(s.sessions[0].state == .working)
        #expect(s.sessions[0].activity == "düşünüyor")
    }

    @Test func permissionNotificationAlertsOnce() {
        var s = SessionStore()
        _ = s.apply(ev(.preToolUse, tool: "Bash", target: "ls"), now: t0)
        #expect(s.apply(ev(.notification, notif: .permission), now: at(1)) == .attention)
        #expect(s.sessions[0].state == .waiting)
        #expect(s.sessions[0].activity == "izin: Bash")
        #expect(s.apply(ev(.notification, notif: .permission), now: at(2)) == nil)
    }

    @Test func idleNotificationIgnored() {
        var s = SessionStore()
        _ = s.apply(ev(.stop), now: t0)
        #expect(s.apply(ev(.notification, notif: .idle), now: at(60)) == nil)
        #expect(s.sessions[0].state == .done)
        #expect(s.sessions[0].activity == "bitti")
    }

    @Test func idleNotificationResetsStuckWorkingToIdle() {
        var s = SessionStore()
        _ = s.apply(ev(.preToolUse, tool: "Bash", target: "ls"), now: t0)
        #expect(s.apply(ev(.notification, notif: .idle), now: at(60)) == nil)
        #expect(s.sessions[0].state == .idle)
        #expect(s.sessions[0].activity == "boşta")
        #expect(s.sessions[0].stateSince == at(60))
    }

    @Test func idleNotificationResetsStuckWaitingToIdle() {
        var s = SessionStore()
        _ = s.apply(ev(.preToolUse, tool: "Bash"), now: t0)
        _ = s.apply(ev(.notification, notif: .permission), now: at(1))
        #expect(s.apply(ev(.notification, notif: .idle), now: at(61)) == nil)
        #expect(s.sessions[0].state == .idle)
    }

    @Test func postToolUseClearsWaiting() {
        var s = SessionStore()
        _ = s.apply(ev(.preToolUse, tool: "Bash"), now: t0)
        _ = s.apply(ev(.notification, notif: .permission), now: at(1))
        #expect(s.apply(ev(.postToolUse, tool: "Bash"), now: at(2)) == nil)
        #expect(s.sessions[0].state == .working)
    }

    @Test func stopFinishes() {
        var s = SessionStore()
        _ = s.apply(ev(.userPromptSubmit), now: t0)
        #expect(s.apply(ev(.stop), now: at(5)) == .finished)
        #expect(s.sessions[0].state == .done)
        #expect(s.sessions[0].activity == "bitti")
    }

    @Test func sessionEndRemoves() {
        var s = SessionStore()
        _ = s.apply(ev(.sessionStart), now: t0)
        _ = s.apply(ev(.sessionEnd), now: at(1))
        #expect(s.sessions.isEmpty)
    }

    @Test func stateSinceOnlyChangesOnTransition() {
        var s = SessionStore()
        _ = s.apply(ev(.preToolUse, tool: "Read"), now: t0)
        _ = s.apply(ev(.preToolUse, tool: "Edit"), now: at(10))
        #expect(s.sessions[0].stateSince == t0)
        #expect(s.sessions[0].lastEventAt == at(10))
    }

    @Test func workspaceSurfacePidUpdatedWhenPresent() {
        var s = SessionStore()
        _ = s.apply(ev(.sessionStart, ws: "W", surface: "S", pid: 9), now: t0)
        _ = s.apply(ev(.userPromptSubmit), now: at(1))
        #expect(s.sessions[0].workspace == "W")
        #expect(s.sessions[0].surface == "S")
        #expect(s.sessions[0].pid == 9)
        _ = s.apply(ev(.userPromptSubmit, ws: "W2"), now: at(2))
        #expect(s.sessions[0].workspace == "W2")
    }

    @Test func twoSessionsSameCwdAreSeparate() {
        var s = SessionStore()
        _ = s.apply(ev(.sessionStart, "a"), now: t0)
        _ = s.apply(ev(.sessionStart, "b"), now: t0)
        #expect(s.sessions.count == 2)
        #expect(Set(s.sessions.map(\.id)) == ["a", "b"])
    }

    @Test func sortingOrder() {
        var s = SessionStore()
        _ = s.apply(ev(.stop, "done1"), now: t0)
        _ = s.apply(ev(.userPromptSubmit, "work2"), now: at(5))
        _ = s.apply(ev(.userPromptSubmit, "work1"), now: at(1))
        _ = s.apply(ev(.sessionStart, "idle1"), now: at(2))
        _ = s.apply(ev(.notification, "wait1", notif: .permission), now: at(9))
        #expect(s.sessions.map(\.id) == ["wait1", "work1", "work2", "done1", "idle1"])
    }

    @Test func countsMergeDoneAndIdle() {
        var s = SessionStore()
        _ = s.apply(ev(.stop, "a"), now: t0)
        _ = s.apply(ev(.sessionStart, "b"), now: t0)
        _ = s.apply(ev(.userPromptSubmit, "c"), now: t0)
        _ = s.apply(ev(.notification, "d", notif: .permission), now: t0)
        #expect(s.counts == Counts(working: 1, waiting: 1, done: 2))
    }

    @Test func pruneDeadPidAfter5Min() {
        func store() -> SessionStore {
            var s = SessionStore()
            _ = s.apply(ev(.sessionStart, pid: 7), now: t0)
            return s
        }
        var a = store(); a.pruneStale(now: at(301), isAlive: { _ in false }); #expect(a.sessions.isEmpty)
        var b = store(); b.pruneStale(now: at(299), isAlive: { _ in false }); #expect(b.sessions.count == 1)
        var c = store(); c.pruneStale(now: at(301), isAlive: { _ in true }); #expect(c.sessions.count == 1)
    }

    @Test func pruneNoPidAfter30Min() {
        func store() -> SessionStore {
            var s = SessionStore()
            _ = s.apply(ev(.sessionStart), now: t0)
            return s
        }
        var a = store(); a.pruneStale(now: at(1801), isAlive: { _ in false }); #expect(a.sessions.isEmpty)
        var b = store(); b.pruneStale(now: at(1799), isAlive: { _ in false }); #expect(b.sessions.count == 1)
    }

    @Test func unknownEventOnlyTouchesLastEventAt() {
        var s = SessionStore()
        _ = s.apply(ev(.stop), now: t0)
        #expect(s.apply(ev(.unknown("PreCompact")), now: at(3)) == nil)
        #expect(s.sessions[0].state == .done)
        #expect(s.sessions[0].lastEventAt == at(3))
    }
}
