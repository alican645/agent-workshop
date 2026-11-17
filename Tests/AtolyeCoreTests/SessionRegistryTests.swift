import Foundation
import Testing
@testable import AtolyeCore

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

    @Test func vanishedSessionIsRemoved() {
        var s = SessionStore()
        _ = s.applyRegistry([reg(.busy), reg("s2", pid: 43, .idle)], profileNames: [:], now: t0, initial: false)
        _ = s.applyRegistry([reg("s2", pid: 43, .idle)], profileNames: [:], now: at(1), initial: false)
        #expect(s.sessions.map(\.id) == ["s2"])
    }

    @Test func profileNameFromEntry() {
        var s = SessionStore()
        _ = s.applyRegistry([reg(.busy, profile: "p2")], profileNames: ["p2": "profil 2"], now: t0, initial: false)
        #expect(s.sessions[0].profileName == "profil 2")
    }
}
