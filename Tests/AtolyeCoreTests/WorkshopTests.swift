import Foundation
import Testing
@testable import AtolyeCore

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

    @Test func todosKeepDoneItemsAndLines() {
        let items = TodoList.parse("# başlık\n- [ ] bir\n- [x] iki\n- [ ] üç\n")
        let snap = Workshop.build(sessions: [sess("a", cwd: "/p/erp")], details: [:], todos: ["/p/erp": items], fileExists: exists)
        #expect(snap.zones[0].todos == [ZoneTodo(line: 1, text: "bir", done: false),
                                        ZoneTodo(line: 2, text: "iki", done: true),
                                        ZoneTodo(line: 3, text: "üç", done: false)])
    }

    @Test func todosAreCapped() {
        let items = TodoList.parse((0..<60).map { "- [ ] m\($0)" }.joined(separator: "\n"))
        let snap = Workshop.build(sessions: [sess("a", cwd: "/p/erp")], details: [:], todos: ["/p/erp": items], fileExists: exists)
        #expect(snap.zones[0].todos.count == Workshop.todoLimit)
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

    private func term(_ id: String, cwd: String, kind: TerminalKind = .shell, running: Bool = true, out: Double? = nil) -> TerminalInfo {
        TerminalInfo(id: id, cwd: cwd, title: "zsh", kind: kind, pid: 1, running: running, exitCode: nil,
                     lastOutputAt: out.map { Date(timeIntervalSince1970: 1_000 + $0) })
    }

    @Test func zonesIncludeShellTerminalsAndPinned() {
        let snap = Workshop.build(sessions: [], details: [:], todos: [:], terminals: [term("t1", cwd: "/p/x")],
                                  terminalOf: [:], pinned: ["/p/y"], now: Date(timeIntervalSince1970: 1_000), fileExists: exists)
        #expect(snap.zones.map(\.id) == ["/p/x", "/p/y"])
        #expect(snap.zones[0].machines == [MachineInfo(id: "t1", title: "zsh", active: false)] && !snap.zones[0].pinned)
        #expect(snap.zones[1].pinned && snap.zones[1].robots.isEmpty && snap.zones[1].machines.isEmpty)
    }

    @Test func claudeTerminalIsNotAMachine() {
        let snap = Workshop.build(sessions: [], details: [:], todos: [:], terminals: [term("t1", cwd: "/p/x", kind: .claude)],
                                  terminalOf: [:], pinned: [], now: Date(), fileExists: exists)
        #expect(snap.zones.isEmpty)
    }

    @Test func machinesActiveByRecentOutput() {
        let now = Date(timeIntervalSince1970: 1_000 + 10)
        let snap = Workshop.build(sessions: [], details: [:], todos: [:],
                                  terminals: [term("a", cwd: "/p/erp", out: 9), term("b", cwd: "/p/erp", out: 0),
                                              term("c", cwd: "/p/erp", running: false, out: 10)],
                                  terminalOf: [:], pinned: [], now: now, fileExists: exists)
        #expect(snap.zones[0].machines.map(\.active) == [true, false, false])
    }

    @Test func robotCarriesTerminalID() {
        let snap = Workshop.build(sessions: [sess("s1", cwd: "/p/erp")], details: [:], todos: [:], terminals: [],
                                  terminalOf: ["s1": "t1"], pinned: [], now: Date(), fileExists: exists)
        #expect(snap.zones[0].robots[0].terminal == "t1")
    }

    @Test func zonesCarryGitBadge() {
        let badge = GitBadge(branch: "feat/todo", changed: 4, ahead: 3, behind: 1, head: "5dba3c5", headSubject: "docs: tasarım")
        let snap = Workshop.build(sessions: [], details: [:], todos: [:], pinned: ["/p/x", "/p/y"],
                                  git: ["/p/x": badge], fileExists: exists)
        #expect(snap.zones.map(\.git) == [badge, nil])
    }

    @Test func robotsCarryUsage() {
        var u = SessionUsage()
        u.tokens = TokenUsage(input: 10, output: 20, cacheRead: 300)
        u.cost = 1.25
        let snap = Workshop.build(sessions: [sess("a", cwd: "/p/x"), sess("b", cwd: "/p/x")], details: [:], todos: [:],
                                  usage: ["a": u], fileExists: exists)
        let robots = snap.zones[0].robots
        #expect(robots.map(\.tokens) == [330, nil] && robots.map(\.cost) == [1.25, nil])
    }

    @Test func snapshotEncodesRobots() throws {
        var snap = WorkshopSnapshot(zones: [])
        let bare = String(decoding: try JSONEncoder().encode(snap), as: UTF8.self)
        #expect(!bare.contains("\"robots\""))
        snap.robots = RobotPool.sceneRobots(RobotPoolConfig())
        let full = String(decoding: try JSONEncoder().encode(snap), as: UTF8.self)
        #expect(full.contains("\"robots\"") && full.contains("\"builtin\""))
    }
}
