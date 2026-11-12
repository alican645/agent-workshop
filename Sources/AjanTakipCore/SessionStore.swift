import Foundation

public struct SessionStore: Sendable {
    public private(set) var sessions: [Session] = []

    /// pid biliniyorsa bu kadar olaysızlıktan sonra süreç kontrol edilir.
    public static let deadPidAfter: TimeInterval = 5 * 60
    /// pid bilinmiyorsa bu kadar olaysızlıktan sonra silinir.
    public static let noPidAfter: TimeInterval = 30 * 60

    public init() {}

    public var counts: Counts {
        var c = Counts(working: 0, waiting: 0, done: 0)
        for s in sessions {
            switch s.state {
            case .working: c.working += 1
            case .waiting: c.waiting += 1
            case .done, .idle: c.done += 1
            }
        }
        return c
    }

    /// Olayı uygular; yalnızca waiting/done durumuna *geçişte* uyarı döner.
    @discardableResult
    public mutating func apply(_ e: HookEvent, now: Date) -> AlertKind? {
        if e.name == .sessionEnd {
            sessions.removeAll { $0.id == e.sessionID }
            return nil
        }

        let index: Int
        if let i = sessions.firstIndex(where: { $0.id == e.sessionID }) {
            index = i
        } else {
            sessions.append(Session(
                id: e.sessionID, projectName: Self.projectName(e.cwd), state: .idle, activity: "boşta",
                stateSince: now, lastEventAt: now))
            index = sessions.count - 1
        }

        var s = sessions[index]
        s.lastEventAt = now
        if let cwd = e.cwd { s.projectName = Self.projectName(cwd) }
        if let w = e.workspace { s.workspace = w }
        if let x = e.surface { s.surface = x }
        if let p = e.pid { s.pid = p }

        var newState: SessionState? = nil
        switch e.name {
        case .userPromptSubmit:
            newState = .working
            s.activity = "düşünüyor"
        case .preToolUse:
            newState = .working
            s.lastTool = e.toolName
            s.activity = [e.toolName, e.toolTarget].compactMap { $0 }.joined(separator: " ")
            if s.activity.isEmpty { s.activity = "çalışıyor" }
        case .postToolUse:
            newState = .working
            if s.state == .waiting { s.activity = "düşünüyor" }
        case .notification:
            if e.notificationKind == .permission {
                newState = .waiting
                s.activity = s.lastTool.map { "izin: \($0)" } ?? "izin bekliyor"
            }
        case .stop:
            newState = .done
            s.activity = "bitti"
        case .sessionStart, .sessionEnd, .unknown:
            break
        }

        var alert: AlertKind? = nil
        if let newState, newState != s.state {
            s.state = newState
            s.stateSince = now
            switch newState {
            case .waiting: alert = .attention
            case .done: alert = .finished
            default: break
            }
        }
        sessions[index] = s
        sort()
        return alert
    }

    public mutating func pruneStale(now: Date, isAlive: (Int32) -> Bool) {
        sessions.removeAll { s in
            let quiet = now.timeIntervalSince(s.lastEventAt)
            if let pid = s.pid {
                return quiet > Self.deadPidAfter && !isAlive(pid)
            }
            return quiet > Self.noPidAfter
        }
    }

    private mutating func sort() {
        sessions.sort { a, b in
            if a.state.sortGroup != b.state.sortGroup { return a.state.sortGroup < b.state.sortGroup }
            if a.stateSince != b.stateSince { return a.stateSince < b.stateSince }
            return a.id < b.id
        }
    }

    private static func projectName(_ cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "?" }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "?" : name
    }
}
