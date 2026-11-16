import AjanTakipCore
import AppKit
import AtolyeHostKit
import Observation

/// Saniyede bir tüm profillerin oturumlarını tarar, atölye görüntüsünü üretir; odaları ve terminalleri yönetir.
@MainActor @Observable
final class WorkshopModel {
    /// Sahneye gönderilecek son anlık görüntü (JSON).
    private(set) var snapshotJSON = #"{"zones":[]}"#
    /// Açık oda (proje kökü); nil ise atölye görünür.
    var openRoom: String?
    private(set) var rooms = RoomStore()
    let host = HostConnection()

    @ObservationIgnored private var store = SessionStore()
    @ObservationIgnored private var scanner = RegistryScanner()
    @ObservationIgnored private var transcripts: [String: Transcript] = [:]
    @ObservationIgnored private var terminalOfPid: [Int32: String?] = [:]
    /// Son anlık görüntü (sol paneldeki oturum listesi için).
    private(set) var snapshot: WorkshopSnapshot?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pruned = false

    private struct Transcript {
        var path: String?
        var lastLookup = Date.distantPast
        var tail = TranscriptTail()
        var history: [ToolUse] = []
        var subagents = SubagentScanner()
    }

    static let historyKeep = 20
    static let lookupRetry: TimeInterval = 5
    static var roomsURL: URL { URL(fileURLWithPath: HostPaths.supportDir + "/rooms.json") }

    func start() {
        guard timer == nil else { return }
        rooms = RoomStore.load(from: Self.roomsURL)
        host.start()
        tick(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(initial: false) }
        }
        timer?.tolerance = 0.2
    }

    // MARK: Gezinme

    func openZone(_ root: String) {
        openRoom = root
        pruneRooms()
        if room(root).panes.isEmpty { saveRooms() }
    }

    /// Robota tıklanınca: Atölye terminalindeyse yan panelde o sekme; değilse projenin odası.
    func open(sessionID: String) {
        guard let s = store.sessions.first(where: { $0.id == sessionID }) else { return }
        let root = s.cwd.map { Workshop.projectRoot(cwd: $0, fileExists: FileManager.default.fileExists(atPath:)) }
        if let pid = s.pid, let tid = terminalID(pid: pid) {
            let owner = rooms.rooms.first { $0.value.panes.contains { $0.tabs.contains(.terminal(tid)) } }?.key
            guard let target = owner ?? root else { return }
            var r = room(target)
            if !r.focus(.terminal(tid)) { r.add(.terminal(tid)) }
            rooms.rooms[target] = r
            saveRooms()
            openRoom = target
            return
        }
        if let root { openZone(root) }
    }

    func openTerminal(_ id: String) {
        guard let t = host.terminals[id] else { return }
        let root = rooms.rooms.first { $0.value.panes.contains { $0.tabs.contains(.terminal(id)) } }?.key
            ?? Workshop.projectRoot(cwd: t.cwd, fileExists: FileManager.default.fileExists(atPath:))
        var r = room(root)
        if !r.focus(.terminal(id)) { r.add(.terminal(id)) }
        rooms.rooms[root] = r
        saveRooms()
        openRoom = root
    }

    func closeRoom() { openRoom = nil }

    // MARK: Oda işlemleri

    func room(_ root: String) -> Room { rooms.rooms[root] ?? Room() }

    func update(_ root: String, _ change: (inout Room) -> Void) {
        var r = room(root)
        change(&r)
        rooms.rooms[root] = r
        saveRooms()
    }

    func add(_ kind: TerminalKind, in root: String) {
        host.create(kind, cwd: root) { [weak self] info in
            self?.update(root) { $0.add(.terminal(info.id)) }
        }
    }

    func addMarkdown(in root: String) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: root)
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        update(root) { r in if !r.focus(.markdown(url.path)) { r.add(.markdown(url.path)) } }
    }

    /// Sekmeyi kapatır; çalışan terminalse önce sorar.
    func close(_ tab: RoomTab, in root: String) {
        if case let .terminal(id) = tab, host.terminals[id]?.running == true {
            let a = NSAlert()
            a.messageText = "\(host.title(id)) hâlâ çalışıyor"
            a.informativeText = "Sekmeyi kapatmak içinde çalışan programı da durdurur."
            a.addButton(withTitle: "Kapat")
            a.addButton(withTitle: "Vazgeç")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        if case let .terminal(id) = tab { host.kill(id) }
        update(root) { $0.remove(tab) }
    }

    func killAllTerminals() {
        let a = NSAlert()
        a.messageText = "Tüm terminaller kapatılsın mı?"
        a.informativeText = "Atölye'de açılmış bütün terminaller ve içlerinde çalışan Claude oturumları durdurulur."
        a.addButton(withTitle: "Hepsini kapat")
        a.addButton(withTitle: "Vazgeç")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        host.killAll()
        for k in rooms.rooms.keys { rooms.rooms[k]?.prune(liveTerminals: []) }
        saveRooms()
    }

    func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Atölyeye ekle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let root = Workshop.projectRoot(cwd: url.path, fileExists: FileManager.default.fileExists(atPath:))
        if !rooms.pinned.contains(root) { rooms.pinned.append(root) }
        saveRooms()
        tick(initial: false)
    }

    func unpin(_ root: String) {
        rooms.pinned.removeAll { $0 == root }
        saveRooms()
        tick(initial: false)
    }

    private func saveRooms() { try? rooms.save(to: Self.roomsURL) }

    /// Yardımcının listesi geldikten sonra bir kez: artık olmayan terminallerin sekmelerini sil.
    private func pruneRooms() {
        guard host.listed, !pruned else { return }
        pruned = true
        let live = Set(host.terminals.keys)
        for k in rooms.rooms.keys { rooms.rooms[k]?.prune(liveTerminals: live) }
        saveRooms()
    }

    private func terminalID(pid: Int32) -> String? {
        if let cached = terminalOfPid[pid] { return cached }
        let id = ProcessEnv.terminalID(pid: pid)
        terminalOfPid[pid] = id
        return id
    }

    // MARK: Tarama

    private func tick(initial: Bool) {
        let now = Date()
        host.refresh()
        pruneRooms()
        let profiles = Self.loadProfiles()
        let entries = scanner.scan(dirs: profiles.map { ($0.id, $0.configDir) }, isAlive: Self.isProcessAlive)
        let names = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.id == AccountStore.defaultID ? "" : $0.name) })
        let alerts = store.applyRegistry(entries, profileNames: names, now: now, initial: initial)
        for a in alerts { Self.play(a) }

        let configDirs = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.configDir) })
        let byID = Dictionary(entries.map { ($0.sessionID, $0) }, uniquingKeysWith: { a, _ in a })
        var details: [String: RobotDetails] = [:]
        var terminalOf: [String: String] = [:]
        for s in store.sessions {
            if let pid = s.pid, let tid = terminalID(pid: pid) { terminalOf[s.id] = tid }
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
        let livePids = Set(store.sessions.compactMap(\.pid))
        terminalOfPid = terminalOfPid.filter { livePids.contains($0.key) }

        let fm = FileManager.default
        var todos: [String: [TodoItem]] = [:]
        let roots = Set(store.sessions.compactMap(\.cwd).map { Workshop.projectRoot(cwd: $0, fileExists: fm.fileExists(atPath:)) })
            .union(rooms.pinned)
        for root in roots {
            if let text = try? String(contentsOfFile: root + "/" + TodoList.fileName, encoding: .utf8) {
                todos[root] = TodoList.parse(text)
            }
        }
        let snap = Workshop.build(sessions: store.sessions, details: details, todos: todos,
                                  terminals: Array(host.terminals.values).sorted { $0.id < $1.id },
                                  terminalOf: terminalOf, pinned: rooms.pinned, now: now, fileExists: fm.fileExists(atPath:))
        guard snap != snapshot, let data = try? JSONEncoder().encode(snap) else { return }
        snapshot = snap
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
