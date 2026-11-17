import Foundation
import Testing
@testable import AtolyeCore

@Suite struct RobotAlertTests {
    private func robot(_ id: String, _ state: String, terminal: String? = nil, waitingFor: String? = nil) -> RobotInfo {
        RobotInfo(id: id, label: "Claude \(id)", profile: "", state: state, tool: nil, waitingFor: waitingFor,
                  helpers: [], history: [], terminal: terminal)
    }

    private func snap(_ robots: [RobotInfo]) -> WorkshopSnapshot {
        WorkshopSnapshot(zones: [ZoneInfo(id: "/p/x", name: "x", color: "#ffffff", robots: robots, todos: [],
                                          machines: [], pinned: false, git: nil)])
    }

    @Test func reportsNewWaitingAndDone() {
        let old = snap([robot("a", "busy"), robot("b", "busy"), robot("c", "waiting")])
        let new = snap([robot("a", "waiting", waitingFor: "Bash izni"), robot("b", "done"), robot("c", "waiting")])
        let alerts = Workshop.alerts(from: old, to: new)
        #expect(alerts.map(\.robotID) == ["a", "b"])
        #expect(alerts.map(\.kind) == [.waiting, .done])
        #expect(alerts[0].zoneName == "x" && alerts[0].label == "Claude a" && alerts[0].detail == "Bash izni")
    }

    @Test func ignoresFirstSnapshotAndNewcomers() {
        let new = snap([robot("a", "waiting")])
        #expect(Workshop.alerts(from: nil, to: new).isEmpty)
        #expect(Workshop.alerts(from: snap([]), to: new).isEmpty)
    }

    @Test func waitingTerminals() {
        let s = snap([robot("a", "waiting", terminal: "t1"), robot("b", "waiting"), robot("c", "busy", terminal: "t3")])
        #expect(Workshop.waitingTerminals(s) == ["t1"])
        #expect(Workshop.waitingCount(s) == 2)
    }
}
