import Foundation

public struct SessionStore: Sendable {
    public private(set) var sessions: [Session] = []

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

    /// Bir taramada okunan kayıtları uygular: kayıttaki oturumların varlığı ve durumu buradan gelir.
    /// Yalnız geçişlerde uyarı döner; `initial` (açılıştaki ilk tarama) hiç uyarı üretmez.
    public mutating func applyRegistry(_ entries: [RegistryEntry], profileNames: [String: String], now: Date,
                                       initial: Bool) -> [AlertKind] {
        let live = Set(entries.map(\.sessionID))
        // Sıkıştırmada aynı süreç yeni sessionId ile devam eder: cmux bilgisi pid üzerinden devralınır.
        var cmuxByPid: [Int32: (String?, String?)] = [:]
        for s in sessions where !live.contains(s.id) {
            if let pid = s.pid, s.workspace != nil { cmuxByPid[pid] = (s.workspace, s.surface) }
        }
        sessions.removeAll { $0.fromRegistry && !live.contains($0.id) }

        var alerts: [AlertKind] = []
        for e in entries {
            let index: Int
            if let i = sessions.firstIndex(where: { $0.id == e.sessionID }) {
                index = i
            } else {
                var n = Session(id: e.sessionID, projectName: Self.projectName(e.cwd), state: .idle, activity: "boşta",
                                stateSince: e.statusSince, lastEventAt: now)
                if let carried = cmuxByPid[e.pid] { (n.workspace, n.surface) = carried }
                sessions.append(n)
                index = sessions.count - 1
            }
            var s = sessions[index]
            s.fromRegistry = true
            s.pid = e.pid
            s.profileName = profileNames[e.profileID] ?? ""
            if let cwd = e.cwd { s.cwd = cwd; s.projectName = Self.projectName(cwd) }

            let newState: SessionState
            switch e.status {
            case .busy: newState = .working
            case .waiting: newState = .waiting
            case .idle: newState = [.working, .waiting, .done].contains(s.state) ? .done : .idle
            }
            if newState != s.state {
                s.state = newState
                s.stateSince = e.statusSince
                switch newState {
                case .working: s.activity = "çalışıyor"
                case .done: s.activity = "bitti"
                case .idle: s.activity = "boşta"
                case .waiting: break
                }
                if !initial, let kind: AlertKind = newState == .waiting ? .attention : newState == .done ? .finished : nil {
                    alerts.append(kind)
                }
            }
            if newState == .waiting {
                s.activity = e.waitingFor.map { "izin: \($0)" } ?? s.lastTool.map { "izin: \($0)" } ?? "izin bekliyor"
            }
            sessions[index] = s
        }
        sort()
        return alerts
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
