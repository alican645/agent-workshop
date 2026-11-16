import AjanTakipCore
import AppKit
import Observation

/// Saniyede bir tüm profillerin oturumlarını tarar ve sahneye gidecek anlık görüntüyü üretir.
@MainActor @Observable
final class WorkshopModel {
    /// Sahneye gönderilecek son anlık görüntü (JSON).
    private(set) var snapshotJSON = #"{"zones":[]}"#

    @ObservationIgnored private var store = SessionStore()
    @ObservationIgnored private var scanner = RegistryScanner()
    @ObservationIgnored private var transcripts: [String: Transcript] = [:]
    @ObservationIgnored private var lastSnapshot: WorkshopSnapshot?
    @ObservationIgnored private var timer: Timer?

    private struct Transcript {
        var path: String?
        var lastLookup = Date.distantPast
        var tail = TranscriptTail()
        var history: [ToolUse] = []
        var subagents = SubagentScanner()
    }

    static let historyKeep = 20
    static let lookupRetry: TimeInterval = 5

    func start() {
        guard timer == nil else { return }
        tick(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(initial: false) }
        }
        timer?.tolerance = 0.2
    }

    /// Robota tıklanınca: oturumun cmux sekmesini öne getirir.
    func focus(sessionID: String) {
        guard let pid = store.sessions.first(where: { $0.id == sessionID })?.pid else { return }
        CmuxLink.focus(pid: pid)
    }

    private func tick(initial: Bool) {
        let now = Date()
        let profiles = Self.loadProfiles()
        let entries = scanner.scan(dirs: profiles.map { ($0.id, $0.configDir) }, isAlive: Self.isProcessAlive)
        let names = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.id == AccountStore.defaultID ? "" : $0.name) })
        let alerts = store.applyRegistry(entries, profileNames: names, now: now, initial: initial)
        for a in alerts { Self.play(a) }

        let configDirs = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.configDir) })
        let byID = Dictionary(entries.map { ($0.sessionID, $0) }, uniquingKeysWith: { a, _ in a })
        var details: [String: RobotDetails] = [:]
        for s in store.sessions {
            guard let e = byID[s.id], let configDir = configDirs[e.profileID] else { continue }
            var t = transcripts[s.id] ?? Transcript()
            if t.path == nil, now.timeIntervalSince(t.lastLookup) > Self.lookupRetry {
                t.lastLookup = now
                t.path = TranscriptTail.findTranscript(configDir: configDir, sessionID: s.id)
            }
            var helpers: [Helper] = []
            if let path = t.path {
                t.history.append(contentsOf: t.tail.read(path: path))
                if t.history.count > Self.historyKeep { t.history.removeFirst(t.history.count - Self.historyKeep) }
                helpers = s.state == .working ? t.subagents.scan(transcriptPath: path, now: now) : []
            }
            transcripts[s.id] = t
            details[s.id] = RobotDetails(tool: s.state == .working ? t.history.last : nil, history: t.history,
                                         helpers: helpers, waitingFor: e.waitingFor)
        }
        let live = Set(store.sessions.map(\.id))
        transcripts = transcripts.filter { live.contains($0.key) }

        let fm = FileManager.default
        var todos: [String: [TodoItem]] = [:]
        let roots = Set(store.sessions.compactMap(\.cwd).map { Workshop.projectRoot(cwd: $0, fileExists: fm.fileExists(atPath:)) })
        for root in roots {
            if let text = try? String(contentsOfFile: root + "/" + TodoList.fileName, encoding: .utf8) {
                todos[root] = TodoList.parse(text)
            }
        }
        let snap = Workshop.build(sessions: store.sessions, details: details, todos: todos, fileExists: fm.fileExists(atPath:))
        guard snap != lastSnapshot, let data = try? JSONEncoder().encode(snap) else { return }
        lastSnapshot = snap
        snapshotJSON = String(decoding: data, as: UTF8.self)
    }

    private struct SavedAccounts: Decodable { var store: AccountStore }

    /// AjanTakip'in hesap dosyasından profiller (salt okunur); dosya yoksa yalnız varsayılan profil.
    static func loadProfiles() -> [AccountProfile] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let url = URL(fileURLWithPath: home + "/.config/ajantakip/accounts.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(SavedAccounts.self, from: data) {
            return saved.store.profiles
        }
        return AccountStore(home: home).profiles
    }

    nonisolated static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func play(_ kind: AlertKind) {
        let name: NSSound.Name = switch kind {
        case .attention: "Funk"
        case .finished: "Glass"
        }
        NSSound(named: name)?.play()
    }
}
