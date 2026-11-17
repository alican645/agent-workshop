import Foundation

public struct SessionStore: Sendable {
    public private(set) var sessions: [Session] = []
    /// Kayıttan düşmüş oturumlar: geç gelen hook olayı onları yeniden yaratmaz.
    private var endedIDs: Set<String> = []

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
        if endedIDs.contains(e.sessionID) { return nil }
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
        if let cwd = e.cwd {
            s.projectName = Self.projectName(cwd)
            s.cwd = cwd
        }
        if let w = e.workspace { s.workspace = w }
        if let x = e.surface { s.surface = x }
        if let p = e.pid { s.pid = p }

        if s.fromRegistry {
            applyDetails(e, to: &s)
            sessions[index] = s
            return nil
        }

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
            // Kesme (Esc) veya izin reddinde Stop gelmez; "girdini bekliyorum" hatırlatması
            // takılı kalan çalışıyor/bekliyor durumunu boşta'ya çeker. done olduğu gibi kalır.
            if e.notificationKind == .idle, s.state == .working || s.state == .waiting {
                newState = .idle
                s.activity = "boşta"
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
            if s.fromRegistry { return false }
            let quiet = now.timeIntervalSince(s.lastEventAt)
            if let pid = s.pid {
                return quiet > Self.deadPidAfter && !isAlive(pid)
            }
            return quiet > Self.noPidAfter
        }
    }

    /// Kayıttaki oturumlarda hook yalnız etkinlik metnini ve araç bilgisini günceller (izin beklerken metin kalır).
    private func applyDetails(_ e: HookEvent, to s: inout Session) {
        switch e.name {
        case .userPromptSubmit where s.state != .waiting:
            s.activity = "düşünüyor"
        case .preToolUse:
            s.lastTool = e.toolName
            guard s.state != .waiting else { return }
            s.activity = [e.toolName, e.toolTarget].compactMap { $0 }.joined(separator: " ")
            if s.activity.isEmpty { s.activity = "çalışıyor" }
        default:
            break
        }
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
        for s in sessions where s.fromRegistry && !live.contains(s.id) { endedIDs.insert(s.id) }
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
