import Foundation
import Testing
@testable import AjanTakipCore

private func sess(_ id: String, cwd: String?, _ state: SessionState = .working, profile: String = "") -> Session {
    var s = Session(id: id, projectName: "", state: state, activity: "", stateSince: Date(), lastEventAt: Date(),
                    workspace: nil, surface: nil, pid: 1, cwd: cwd, lastTool: nil)
    s.profileName = profile
    return s
}

private let gitRoots: Set<String> = ["/p/erp/.git", "/p/ajan/.git"]
private func exists(_ p: String) -> Bool { gitRoots.contains(p) }

@Suite struct WorkshopTests {
    @Test func projectRootIsGitRoot() {
        #expect(Workshop.projectRoot(cwd: "/p/erp/src/api", fileExists: exists) == "/p/erp")
        #expect(Workshop.projectRoot(cwd: "/p/erp", fileExists: exists) == "/p/erp")
    }

    @Test func projectRootFallsBackToCwd() {
        #expect(Workshop.projectRoot(cwd: "/q/loose/dir", fileExists: exists) == "/q/loose/dir")
        #expect(Workshop.projectRoot(cwd: "/", fileExists: exists) == "/")
    }

    @Test func colorIsStableAndHex() {
        let c = Workshop.color(for: "ERP")
        #expect(c == Workshop.color(for: "ERP"))
        #expect(c.range(of: "^#[0-9a-f]{6}$", options: .regularExpression) != nil)
        #expect(c != Workshop.color(for: "AjanTakip"))
    }

    @Test func groupsSessionsByProject() {
        let snap = Workshop.build(sessions: [sess("b", cwd: "/p/erp/api"), sess("c", cwd: "/p/ajan"), sess("a", cwd: "/p/erp")],
                                  details: [:], todos: [:], fileExists: exists)
        #expect(snap.zones.map(\.name) == ["ajan", "erp"])
        #expect(snap.zones.map(\.id) == ["/p/ajan", "/p/erp"])
        #expect(snap.zones[1].robots.map(\.id) == ["a", "b"])
        #expect(snap.zones[1].robots.map(\.label) == ["erp", "api"])
        #expect(snap.zones[1].color == Workshop.color(for: "erp"))
    }

    @Test func duplicateLabelsGetNumbers() {
        let snap = Workshop.build(sessions: [sess("a", cwd: "/p/erp"), sess("b", cwd: "/p/erp"), sess("c", cwd: "/p/erp")],
                                  details: [:], todos: [:], fileExists: exists)
        #expect(snap.zones[0].robots.map(\.label) == ["erp", "erp 2", "erp 3"])
    }

    @Test func mapsStatesAndDetails() {
        let tools = (1...7).map { ToolUse(name: "Edit", target: "F\($0).swift") }
        let details: [String: RobotDetails] = [
            "w": RobotDetails(tool: nil, history: [], helpers: [], waitingFor: "Bash"),
            "b": RobotDetails(tool: tools.last, history: tools,
                              helpers: [Helper(id: "h1", task: "testleri yaz", lastTool: ToolUse(name: "Bash", target: "swift test"))],
                              waitingFor: nil),
        ]
        let snap = Workshop.build(sessions: [sess("b", cwd: "/p/erp"), sess("w", cwd: "/p/erp", .waiting),
                                             sess("d", cwd: "/p/erp", .done), sess("i", cwd: "/p/erp", .idle, profile: "profil 2")],
                                  details: details, todos: [:], fileExists: exists)
        let r = Dictionary(uniqueKeysWithValues: snap.zones[0].robots.map { ($0.id, $0) })
        #expect(r["b"]?.state == "busy" && r["w"]?.state == "waiting" && r["d"]?.state == "done" && r["i"]?.state == "idle")
        #expect(r["w"]?.waitingFor == "Bash")
        #expect(r["b"]?.tool == "✏️ F7.swift")
        #expect(r["b"]?.history == ["✏️ F7.swift", "✏️ F6.swift", "✏️ F5.swift", "✏️ F4.swift", "✏️ F3.swift"])
        #expect(r["b"]?.helpers == [HelperInfo(id: "h1", task: "testleri yaz", tool: "⌘ swift test")])
        #expect(r["i"]?.profile == "profil 2" && r["d"]?.tool == nil)
    }

    @Test func toolTextIcons() {
        #expect(Workshop.toolText(ToolUse(name: "Read", target: "A.swift")) == "📖 A.swift")
        #expect(Workshop.toolText(ToolUse(name: "Grep", target: "x")) == "🔎 x")
        #expect(Workshop.toolText(ToolUse(name: "WebSearch", target: "q")) == "🌐 q")
        #expect(Workshop.toolText(ToolUse(name: "Agent", target: "d")) == "↳ d")
        #expect(Workshop.toolText(ToolUse(name: "TodoWrite", target: "")) == "🔧 TodoWrite")
    }

    @Test func todosAreOpenItemsOnly() {
        let items = TodoList.parse("- [ ] bir\n- [x] iki\n- [ ] üç\n")
        let snap = Workshop.build(sessions: [sess("a", cwd: "/p/erp")], details: [:], todos: ["/p/erp": items], fileExists: exists)
        #expect(snap.zones[0].todos == ["bir", "üç"])
    }

    @Test func sessionWithoutCwdIsSkipped() {
        let snap = Workshop.build(sessions: [sess("a", cwd: nil)], details: [:], todos: [:], fileExists: exists)
        #expect(snap.zones.isEmpty)
    }

    @Test func snapshotEncodesToJSON() throws {
        let snap = Workshop.build(sessions: [sess("a", cwd: "/p/erp")], details: [:], todos: [:], fileExists: exists)
        let json = String(decoding: try JSONEncoder().encode(snap), as: UTF8.self)
        #expect(json.contains(#""zones""#) && json.contains(#""robots""#))
    }
}
