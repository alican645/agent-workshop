import Foundation
import Testing
@testable import AjanTakipCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

private func reg(_ sid: String, pid: Int32 = 42, _ st: RegistryStatus, wait: String? = nil,
                 at s: Double = 0, profile: String = "default") -> RegistryEntry {
    RegistryEntry(pid: pid, sessionID: sid, cwd: "/x/erp", status: st, waitingFor: wait,
                  statusSince: at(s), profileID: profile)
}

private func reg(_ st: RegistryStatus, wait: String? = nil, at s: Double = 0, profile: String = "default") -> RegistryEntry {
    reg("s1", st, wait: wait, at: s, profile: profile)
}

private func ev(_ name: HookEventName, _ sid: String = "s1", tool: String? = nil, target: String? = nil,
                notif: NotificationKind? = nil, ws: String? = nil, surface: String? = nil,
                pid: Int32? = nil) -> HookEvent {
    HookEvent(sessionID: sid, name: name, cwd: "/x/erp", toolName: tool, toolTarget: target,
              notificationKind: notif, workspace: ws, surface: surface, pid: pid)
}

@Suite struct SessionRegistryTests {
    @Test func registryCreatesSessionWithState() {
        var s = SessionStore()
        #expect(s.applyRegistry([reg(.busy)], profileNames: ["default": ""], now: t0, initial: false) == [])
        #expect(s.sessions.map(\.state) == [.working])
        #expect(s.sessions[0].activity == "çalışıyor" && s.sessions[0].projectName == "erp")
    }

    @Test func waitingAlertsOnceAndShowsWaitingFor() {
        var s = SessionStore()
        _ = s.applyRegistry([reg(.busy)], profileNames: [:], now: t0, initial: false)
        #expect(s.applyRegistry([reg(.waiting, wait: "Bash")], profileNames: [:], now: at(1), initial: false) == [.attention])
        #expect(s.sessions[0].activity == "izin: Bash")
        #expect(s.applyRegistry([reg(.waiting, wait: "Bash")], profileNames: [:], now: at(2), initial: false) == [])
    }

    @Test func waitingWithoutWaitingForUsesLastTool() {
        var s = SessionStore()
        _ = s.applyRegistry([reg(.busy)], profileNames: [:], now: t0, initial: false)
        _ = s.apply(ev(.preToolUse, tool: "Edit", target: "A.swift"), now: at(1))
        _ = s.applyRegistry([reg(.waiting)], profileNames: [:], now: at(2), initial: false)
        #expect(s.sessions[0].activity == "izin: Edit")
        var s2 = SessionStore()
        _ = s2.applyRegistry([reg(.waiting)], profileNames: [:], now: t0, initial: false)
        #expect(s2.sessions[0].activity == "izin bekliyor")
    }

    @Test func busyToIdleIsDoneWithFinishedAlert() {
        var s = SessionStore()
        _ = s.applyRegistry([reg(.busy)], profileNames: [:], now: t0, initial: false)
        #expect(s.applyRegistry([reg(.idle, at: 1)], profileNames: [:], now: at(1), initial: false) == [.finished])
        #expect(s.sessions[0].state == .done && s.sessions[0].activity == "bitti")
        #expect(s.sessions[0].stateSince == at(1))
    }

    @Test func initialScanIsSilent() {
        var s = SessionStore()
        #expect(s.applyRegistry([reg(.waiting, wait: "Bash"), reg("s2", pid: 43, .idle)], profileNames: [:], now: t0, initial: true) == [])
        #expect(Set(s.sessions.map(\.state)) == [.waiting, .idle])
    }

    @Test func hookCannotChangeRegistryState() {
        var s = SessionStore()
        _ = s.applyRegistry([reg(.busy)], profileNames: [:], now: t0, initial: false)
        #expect(s.apply(ev(.stop), now: at(1)) == nil)
        #expect(s.apply(ev(.notification, notif: .permission), now: at(1)) == nil)
        #expect(s.sessions[0].state == .working)
        _ = s.apply(ev(.preToolUse, tool: "Edit", target: "Foo.swift", ws: "W", surface: "S"), now: at(2))
        #expect(s.sessions[0].activity == "Edit Foo.swift" && s.sessions[0].workspace == "W")
        _ = s.applyRegistry([reg(.busy)], profileNames: [:], now: at(3), initial: false)
        #expect(s.sessions[0].activity == "Edit Foo.swift")
    }

    @Test func vanishedSessionIsRemoved() {
        var s = SessionStore()
        _ = s.applyRegistry([reg(.busy), reg("s2", pid: 43, .idle)], profileNames: [:], now: t0, initial: false)
        _ = s.applyRegistry([reg("s2", pid: 43, .idle)], profileNames: [:], now: at(1), initial: false)
        #expect(s.sessions.map(\.id) == ["s2"])
    }

    @Test func lateHookDoesNotResurrectEndedSession() {
        var s = SessionStore()
        _ = s.applyRegistry([reg(.busy)], profileNames: [:], now: t0, initial: false)
        _ = s.applyRegistry([], profileNames: [:], now: at(1), initial: false)
        _ = s.apply(ev(.stop), now: at(2))
        #expect(s.sessions.isEmpty)
    }

    @Test func hookFirstThenRegistryTakesOver() {
        var s = SessionStore()
        _ = s.apply(ev(.userPromptSubmit, ws: "W", surface: "S", pid: 42), now: t0)
        #expect(s.sessions.count == 1)
        _ = s.applyRegistry([reg(.waiting, wait: "Bash")], profileNames: [:], now: at(1), initial: false)
        #expect(s.sessions.count == 1 && s.sessions[0].state == .waiting && s.sessions[0].workspace == "W")
    }

    @Test func hookOnlySessionKeepsOldBehavior() {
        var s = SessionStore()
        _ = s.apply(ev(.userPromptSubmit, "h1"), now: t0)
        _ = s.applyRegistry([reg(.busy)], profileNames: [:], now: at(1), initial: false)
        #expect(s.apply(ev(.stop, "h1"), now: at(2)) == .finished)
        #expect(s.sessions.count == 2)
    }

    @Test func compactionCarriesCmuxInfo() {
        var s = SessionStore()
        _ = s.applyRegistry([reg(.busy)], profileNames: [:], now: t0, initial: false)
        _ = s.apply(ev(.preToolUse, ws: "W", surface: "S"), now: at(1))
        _ = s.applyRegistry([reg("s9", pid: 42, .busy)], profileNames: [:], now: at(2), initial: false)
        #expect(s.sessions.map(\.id) == ["s9"])
        #expect(s.sessions[0].workspace == "W" && s.sessions[0].surface == "S")
    }

    @Test func profileNameFromEntry() {
        var s = SessionStore()
        _ = s.applyRegistry([reg(.busy, profile: "p2")], profileNames: ["p2": "profil 2"], now: t0, initial: false)
        #expect(s.sessions[0].profileName == "profil 2")
    }
}
