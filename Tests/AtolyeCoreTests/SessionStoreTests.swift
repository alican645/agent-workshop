import Foundation
import Testing
@testable import AtolyeCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

private func reg(_ sid: String, _ st: RegistryStatus, since s: Double = 0) -> RegistryEntry {
    RegistryEntry(pid: Int32(abs(sid.hashValue % 30000) + 100), sessionID: sid, cwd: "/x/erp-api", status: st,
                  waitingFor: nil, statusSince: at(s), profileID: "default")
}

/// Kayıtlardan kurulan listenin sırası ve sayaçları.
@Suite struct SessionStoreTests {
    /// Önce seni bekleyenler, sonra çalışanlar (eskisi önde), sonra bitenler ve boştakiler.
    @Test func sortingOrder() {
        var s = SessionStore()
        _ = s.applyRegistry([reg("done1", .busy)], profileNames: [:], now: t0, initial: true)
        _ = s.applyRegistry([reg("done1", .idle, since: 3), reg("work2", .busy, since: 5), reg("work1", .busy, since: 1),
                             reg("wait1", .waiting, since: 9)], profileNames: [:], now: at(10), initial: false)
        #expect(s.sessions.map(\.id) == ["wait1", "work1", "work2", "done1"])
    }

    @Test func countsMergeDoneAndIdle() {
        var s = SessionStore()
        _ = s.applyRegistry([reg("a", .busy)], profileNames: [:], now: t0, initial: true)
        _ = s.applyRegistry([reg("a", .idle), reg("b", .idle), reg("c", .busy), reg("d", .waiting)],
                            profileNames: [:], now: at(1), initial: false)
        #expect(s.counts == Counts(working: 1, waiting: 1, done: 2))
    }
}
