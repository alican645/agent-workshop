import AtolyeCore
import AppKit
import AtolyeHostKit
import Observation
import SwiftUI

/// Saniyede bir tüm profillerin oturumlarını tarar, atölye görüntüsünü üretir; odaları ve terminalleri yönetir.
@MainActor @Observable
final class WorkshopModel {
    /// Sahneye gönderilecek son anlık görüntü (JSON).
    private(set) var snapshotJSON = #"{"zones":[]}"#
    /// Atölyenin üstünde yüzen pencereler.
    private(set) var desk = Desk()
    let host = HostConnection()
    /// Seni bekleyen Claude'ların terminalleri (pencere başlığı yanıp söner).
    private(set) var waitingTerminals: Set<String> = []
    @ObservationIgnored let notifier = Notifier()
    /// Claude hesapları (profiller).
    let profiles = Profiles()
    /// GitHub girişi ve kişisel pano.
    let github = GitHubModel()
    let todos = Todos()
    let usageHistory = UsageHistoryModel()
    /// Kendi robotlarının klasörü (`<id>.glb` ve `robots.json`).
    nonisolated static let robotsDir = URL(fileURLWithPath: Profiles.support + "/robots")
    /// Robot havuzu: hazır robotların aç-kapası ve kendi `.glb` robotları.
    let robotPool: RobotPoolStore = { let s = RobotPoolStore(dir: WorkshopModel.robotsDir); s.load(); return s }()
    /// Robotlar penceresindeki robot resimleri.
    let robotPreviews = RobotPreviews(dir: WorkshopModel.robotsDir)
    /// Sahnenin yükleyemediği kendi robotları (id → hata).
    var robotFailures: [String: String] = [:]
    /// Robotlar penceresi her değişiklikte artırır; görünümler yeniden çizilsin.
    var robotsVersion = 0
    @ObservationIgnored private var lastProfilesRefresh = Date.distantPast
    static let profilesInterval: TimeInterval = 5

    @ObservationIgnored private var store = SessionStore()
    @ObservationIgnored private var scanner = RegistryScanner()
    @ObservationIgnored private var transcripts: [String: Transcript] = [:]
    @ObservationIgnored private var terminalOfPid: [Int32: String?] = [:]
    /// Son taramada oturum → profil ve oturum → Atölye terminali (profil değişince taşımak için).
    @ObservationIgnored private var sessionProfile: [String: String] = [:]
    @ObservationIgnored private var sessionTerminal: [String: String] = [:]
    /// Profil değişince taşınmayı bekleyen (o an çalışan) oturumlar ve hedef profil.
    @ObservationIgnored private var pendingMoves: Set<String> = []
    @ObservationIgnored private var moveTarget: String?
    @ObservationIgnored private var moving: Set<String> = []
    /// Son anlık görüntü (sol paneldeki oturum listesi için).
    private(set) var snapshot: WorkshopSnapshot?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pruned = false
    /// Proje kökü → git özeti; arka planda tazelenir.
    @ObservationIgnored private var gitBadges: [String: GitBadge] = [:]
    @ObservationIgnored private var gitRefreshing = false
    @ObservationIgnored private var lastGitRefresh = Date.distantPast
    static let gitInterval: TimeInterval = 3
    /// Token kullanımı ve API karşılığı maliyet (arka planda tazelenir).
    @ObservationIgnored private let usageWorker = UsageWorker()
    @ObservationIgnored private var sessionUsage: [String: SessionUsage] = [:]
    @ObservationIgnored private var usageRefreshing = false
    @ObservationIgnored private var lastUsageRefresh = Date.distantPast
    /// Bugünkü toplam (kapanmış oturumlar dahil).
    private(set) var todayCost = 0.0
    private(set) var todayTokens = 0
    static let usageInterval: TimeInterval = 4

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
    static var deskURL: URL { URL(fileURLWithPath: HostPaths.supportDir + "/windows.json") }

    func start() {
        guard timer == nil else { return }
        if let d = Desk.load(from: Self.deskURL) { desk = d } else {
            desk = Desk(migrating: RoomStore.load(from: Self.roomsURL))
            saveDesk()
        }
        host.start()
        todos.onChange = { [weak self] in self?.tick(initial: false) }
        notifier.onOpen = { [weak self] id in self?.open(sessionID: id) }
        notifier.start()
        let mainDir = profiles.main.configDir
        DispatchQueue.global(qos: .utility).async { Profiles.installIntegration(mainDir: mainDir) }
        profiles.onWarning = { [weak self] p, text in
            self?.notifier.postLimit(id: p.id, title: L("{0} limitine yaklaştı", p.displayName),
                                     body: L("{0}. Yeni oturumları başka bir profille açabilirsin.", text))
        }
        tick(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(initial: false) }
        }
        timer?.tolerance = 0.2
    }

    // MARK: Gezinme

    /// Projenin pencerelerini öne getirir; hiç yoksa yeni terminal açar.
    func openZone(_ root: String) {
        pruneDesk()
        guard desk.windows.contains(where: { $0.root == root }) else { return newWindow(.shell, in: root) }
        changeDesk { d in
            d.raiseAll(root: root)
            // Seni bekleyen bir Claude varsa en öne o gelsin.
            if let w = d.windows.last(where: { $0.root == root && isWaiting($0) }) { d.raise(w.id) }
        }
    }

    /// Penceredeki Claude izin ya da cevap bekliyor mu.
    func isWaiting(_ w: DeskWindow) -> Bool {
        if case let .terminal(id) = w.tab { return waitingTerminals.contains(id) }
        return false
    }

    /// Robota tıklanınca: Atölye terminalindeyse penceresi öne gelir; değilse projenin pencereleri.
    func open(sessionID: String) {
        guard let s = store.sessions.first(where: { $0.id == sessionID }) else { return }
        let root = s.cwd.map { Workshop.projectRoot(cwd: $0, fileExists: FileManager.default.fileExists(atPath:)) }
        if let pid = s.pid, let tid = terminalID(pid: pid), let target = desk.window(of: .terminal(tid))?.root ?? root {
            changeDesk { $0.open(.terminal(tid), root: target) }
        } else if let root {
            changeDesk { $0.raiseAll(root: root) }
        }
    }

    func openTerminal(_ id: String) {
        guard let t = host.terminals[id] else { return }
        let root = desk.window(of: .terminal(id))?.root
            ?? Workshop.projectRoot(cwd: t.cwd, fileExists: FileManager.default.fileExists(atPath:))
        changeDesk { $0.open(.terminal(id), root: root) }
    }

    // MARK: Pencereler

    /// Öndeki pencerenin projesi (yeni pencere kısayolları için).
    var frontRoot: String? { desk.front?.root }

    /// Sol paneldeki yerine çekilmekte olan pencereler. Animasyonu her pencere kendi yürütür (DeskView).
    var leaving: Set<String> = []
    /// Küçültülmüşken yeniden açılan pencereler: ilk çizimde panelden çıkarak gelir.
    @ObservationIgnored var arriving: Set<String> = []
    /// Sol paneldeki proje başlıklarının pencere koordinatlarındaki yeri (çekilme hedefi).
    @ObservationIgnored var sidebarTargets: [String: CGRect] = [:]
    @ObservationIgnored private var tuckGeneration = 0
    static let tuckDuration = 0.34

    func changeDesk(_ change: (inout Desk) -> Void) {
        // Süren bir çekilme varsa iptal: kullanıcı pencereleri geri istedi.
        if !leaving.isEmpty {
            tuckGeneration += 1
            leaving = []
        }
        let hidden = Set(desk.windows.filter(\.minimized).map(\.id))
        change(&desk)
        saveDesk()
        let shown = desk.windows.filter { !$0.minimized && hidden.contains($0.id) }.map(\.id)
        guard !shown.isEmpty else { return }
        arriving.formUnion(shown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.arriving.subtract(shown) }
    }

    /// Pencereleri sol paneldeki projelerinin yerine çekerek küçültür.
    func tuck(_ ids: [String]) {
        let ids = ids.filter { desk.window($0)?.minimized == false && !leaving.contains($0) }
        guard !ids.isEmpty else { return }
        tuckGeneration += 1
        let gen = tuckGeneration
        leaving.formUnion(ids)
        // Animasyon bittikten biraz sonra gerçekten küçült.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tuckDuration + 0.06) { [weak self] in
            guard let self, gen == self.tuckGeneration else { return }
            let gone = self.leaving
            for id in gone { self.desk.minimize(id) }
            self.saveDesk()
            self.leaving = []
        }
    }

    /// Atölyeye dönüş: görünen bütün pencereler panele çekilir.
    func tuckAll() { tuck(desk.windows.filter { !$0.minimized }.map(\.id)) }

    /// `profile` verilmezse etkin profil.
    func newWindow(_ kind: TerminalKind, in root: String, profile: String? = nil) {
        host.create(kind, cwd: root, env: profiles.environment(profile)) { [weak self] info in
            self?.changeDesk { $0.open(.terminal(info.id), root: root) }
        }
    }

    func addGit(in root: String) {
        changeDesk { $0.open(.git(root), root: root) }
    }

    func addMarkdown(in root: String) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: root)
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        changeDesk { $0.open(.markdown(url.path), root: root) }
    }

    /// Pencereyi kapatır; çalışan terminalse önce sorar.
    func closeWindow(_ id: String) {
        guard let w = desk.window(id) else { return }
        if case let .terminal(tid) = w.tab, host.terminals[tid]?.running == true {
            let a = NSAlert()
            a.messageText = L("{0} hâlâ çalışıyor", host.title(tid))
            a.informativeText = L("Pencereyi kapatmak içinde çalışan programı da durdurur.")
            a.addButton(withTitle: L("Kapat"))
            a.addButton(withTitle: L("Vazgeç"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        if case let .terminal(tid) = w.tab { host.kill(tid) }
        changeDesk { $0.close(id) }
    }

    func title(_ tab: RoomTab) -> String {
        switch tab {
        case let .terminal(id): host.title(id)
        case let .markdown(path): (path as NSString).lastPathComponent
        case .git: "Git"
        }
    }

    /// Projenin bölge rengi (anlık görüntüden), yoksa nil.
    func zoneColor(_ root: String) -> String? { snapshot?.zones.first { $0.id == root }?.color }

    func killAllTerminals() {
        let a = NSAlert()
        a.messageText = L("Tüm terminaller kapatılsın mı?")
        a.informativeText = L("Agent Workshop'ta açılmış bütün terminaller ve içlerinde çalışan Claude oturumları durdurulur.")
        a.addButton(withTitle: L("Hepsini kapat"))
        a.addButton(withTitle: L("Vazgeç"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        host.killAll()
        changeDesk { $0.prune(liveTerminals: []) }
    }

    func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = L("Atölyeye ekle")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let root = Workshop.projectRoot(cwd: url.path, fileExists: FileManager.default.fileExists(atPath:))
        if !desk.pinned.contains(root) { changeDesk { $0.pinned.append(root) } }
        tick(initial: false)
    }

    /// Havuz değişti: sahneye yeni havuzu hemen gönder.
    func robotsChanged() {
        robotsVersion += 1
        tick(initial: false)
    }

    func robotFailed(_ id: String, _ error: String) {
        robotFailures[id] = error
    }

    func unpin(_ root: String) {
        changeDesk { $0.pinned.removeAll { $0 == root } }
        tick(initial: false)
    }

    // MARK: Yapılacaklar

    /// Tahtaya ya da panele tıklanınca: pencerede o proje seçili açılsın.
    func showTodos(_ root: String) {
        todos.select(root)
    }

    /// Robota verilen işler: "kök\nmadde metni" → terminal kimliği (Yapılacaklar penceresi için).
    private(set) var todoTasks: [String: String] = [:]
    /// Terminal → madde metni (sahnede robot önce tahtaya gitsin diye).
    @ObservationIgnored private var taskOfTerminal: [String: String] = [:]

    static func taskKey(root: String, text: String) -> String { root + "\n" + text }

    /// Maddeyi bir robota ver: projede yeni Claude oturumu açılır, madde (alt maddeleriyle) ilk mesaj olur.
    func giveTask(_ item: TodoItem, items: [TodoItem], root: String) {
        let prompt = TodoList.taskPrompt(for: item, in: items, intro: L("TODO.local.md'deki şu maddeyi yap. Bitince ne yaptığını kısaca anlat; maddeyi işaretlemeyi bana bırak."))
        host.create(.claude, cwd: root, env: profiles.environment(), args: [prompt]) { [weak self] info in
            guard let self else { return }
            self.changeDesk { $0.open(.terminal(info.id), root: root) }
            if info.args == nil { Self.alertOutdatedHostForTask() }
            self.taskOfTerminal[info.id] = item.text
            self.todoTasks[Self.taskKey(root: root, text: item.text)] = info.id
            self.tick(initial: false)
        }
    }

    /// İşi alan robot (Claude oturumu henüz başlamadıysa nil).
    func robot(onTerminal id: String) -> RobotInfo? {
        snapshot?.zones.lazy.flatMap(\.robots).first { $0.terminal == id }
    }

    func terminalAlive(_ id: String) -> Bool { host.terminals[id] != nil }

    private static func alertOutdatedHostForTask() {
        let a = NSAlert()
        a.messageText = L("Madde Claude'a iletilemedi")
        a.informativeText = L("Terminalleri çalıştıran yardımcı eski sürüm; Claude oturumu açıldı ama madde gönderilmedi. Menüden Terminaller › Tüm terminalleri kapat'ı seçip Agent Workshop'u yeniden aç.")
        a.runModal()
    }

    private func saveDesk() { try? desk.save(to: Self.deskURL) }

    /// Yardımcının listesi geldikten sonra bir kez: artık olmayan terminallerin pencerelerini kaldır.
    private func pruneDesk() {
        guard host.listed, !pruned else { return }
        pruned = true
        changeDesk { $0.prune(liveTerminals: Set(host.terminals.keys)) }
    }

    private func terminalID(pid: Int32) -> String? {
        if let cached = terminalOfPid[pid] { return cached }
        let id = ProcessEnv.terminalID(pid: pid)
        terminalOfPid[pid] = id
        return id
    }

    // MARK: Profil değişimi

    /// Etkin profili değiştirir; Atölye'de açılmış Claude oturumları yeni profille kaldıkları yerden sürer.
    /// Çalışan oturumlar işleri bitince taşınır. cmux gibi dışarıda açılanlara dokunulmaz.
    func switchProfile(to id: String) {
        profiles.setActive(id)
        moveTarget = id
        pendingMoves = []
        moveSessions(onlyPending: false)
    }

    private func moveSessions(onlyPending: Bool) {
        guard let target = moveTarget else { return }
        let candidates = store.sessions.compactMap { s -> ProfileMove.Candidate? in
            guard !moving.contains(s.id), !onlyPending || pendingMoves.contains(s.id),
                  let profile = sessionProfile[s.id] else { return nil }
            let t = sessionTerminal[s.id]
            return ProfileMove.Candidate(sessionID: s.id, profileID: profile, terminal: t,
                                         terminalKind: t.flatMap { host.terminals[$0]?.kind },
                                         working: s.state == .working, cwd: s.cwd)
        }
        let plan = ProfileMove.plan(candidates, to: target)
        pendingMoves = onlyPending ? pendingMoves.intersection(plan.later) : Set(plan.later)
        // Eski yardımcı `--resume` bilmez: oturumu kapatıp boş bir Claude açmak yerine uyar, dokunma.
        if plan.now.contains(where: { host.terminals[$0.terminal]?.args == nil }) {
            pendingMoves = []
            moveTarget = nil
            Self.alertOutdatedHost()
            return
        }
        for m in plan.now { move(m, to: target) }
    }

    /// Eski terminali kapatır, aynı pencerede yeni profille `claude --resume <oturum>` açar.
    private func move(_ m: ProfileMove.Move, to profile: String) {
        moving.insert(m.sessionID)
        host.kill(m.terminal)
        // Eski Claude'un kapanıp kaydını bitirmesi için kısa bir an.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.host.create(.claude, cwd: m.cwd, env: self.profiles.environment(profile),
                             args: ProfileMove.resumeArgs(m.sessionID)) { [weak self] info in
                guard let self else { return }
                self.moving.remove(m.sessionID)
                self.changeDesk { d in
                    if !d.retarget(.terminal(m.terminal), to: .terminal(info.id)) { d.open(.terminal(info.id), root: m.cwd) }
                }
            }
        }
    }

    private static func alertOutdatedHost() {
        let a = NSAlert()
        a.messageText = L("Açık Claude oturumları yeni profile taşınamadı")
        a.informativeText = L("Terminalleri çalıştıran yardımcı eski sürüm. Menüden Terminaller › Tüm terminalleri kapat'ı seçip Agent Workshop'u yeniden aç; bundan sonra profil değiştirince oturumlar kaldıkları yerden sürer. Yeni profil yine de seçildi: yeni oturumlar onunla açılır.")
        a.runModal()
    }

    // MARK: Tarama

    private func tick(initial: Bool) {
        let now = Date()
        host.refresh()
        pruneDesk()
        if now.timeIntervalSince(lastProfilesRefresh) >= Self.profilesInterval {
            lastProfilesRefresh = now
            self.profiles.refresh()
        }
        let profiles = self.profiles.profiles
        let entries = scanner.scan(dirs: profiles.map { ($0.id, $0.configDir) }, isAlive: Self.isProcessAlive)
        // Birden çok profil varsa her robotun profili görünsün.
        let names = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, profiles.count > 1 ? $0.displayName : "") })
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
        sessionProfile = byID.mapValues(\.profileID)
        sessionTerminal = terminalOf
        if !pendingMoves.isEmpty { pendingMoves.formIntersection(live); moveSessions(onlyPending: true) }
        let livePids = Set(store.sessions.compactMap(\.pid))
        terminalOfPid = terminalOfPid.filter { livePids.contains($0.key) }

        let fm = FileManager.default
        var todos: [String: [TodoItem]] = [:]
        let roots = Set(store.sessions.compactMap(\.cwd).map { Workshop.projectRoot(cwd: $0, fileExists: fm.fileExists(atPath:)) })
            .union(desk.pinned)
        for root in roots {
            if let text = try? String(contentsOfFile: root + "/" + TodoList.fileName, encoding: .utf8) {
                todos[root] = TodoList.parse(text)
            }
        }
        var snap = Workshop.build(sessions: store.sessions, details: details, todos: todos,
                                  terminals: Array(host.terminals.values).sorted { $0.id < $1.id },
                                  terminalOf: terminalOf, tasks: taskOfTerminal, pinned: desk.pinned, git: gitBadges, usage: sessionUsage,
                                  now: now, fileExists: fm.fileExists(atPath:))
        snap.robots = RobotPool.sceneRobots(robotPool.config)
        refreshGit(roots: snap.zones.map(\.id), now: now)
        refreshUsage(configDirs: profiles.map(\.configDir), now: now)
        usageHistory.refresh(configDirs: profiles.map(\.configDir))
        guard snap != snapshot, let data = try? JSONEncoder().encode(snap) else { return }
        notify(old: snapshot, new: snap)
        snapshot = snap
        snapshotJSON = String(decoding: data, as: UTF8.self)
    }

    /// Bekleyenler: pencere vurgusu, Dock rozeti ve (Atölye arka plandayken) bildirim.
    private func notify(old: WorkshopSnapshot?, new: WorkshopSnapshot) {
        let waiting = Workshop.waitingTerminals(new)
        if waiting != waitingTerminals { waitingTerminals = waiting }
        let count = Workshop.waitingCount(new)
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        let alerts = Workshop.alerts(from: old, to: new)
        if !NSApp.isActive { for a in alerts { notifier.post(a) } }
        // Artık beklemeyenlerin eski bildirimleri kalksın.
        let stillWaiting = Set(new.zones.flatMap { $0.robots.filter { $0.state == "waiting" }.map(\.id) })
        let doneIDs = Set(alerts.filter { $0.kind == .done }.map(\.robotID))
        let before = old?.zones.flatMap { $0.robots.filter { $0.state == "waiting" }.map(\.id) } ?? []
        notifier.clear(sessions: before.filter { !stillWaiting.contains($0) && !doneIDs.contains($0) })
    }

    private func refreshUsage(configDirs: [String], now: Date) {
        guard !usageRefreshing, now.timeIntervalSince(lastUsageRefresh) >= Self.usageInterval else { return }
        usageRefreshing = true
        lastUsageRefresh = now
        let paths = transcripts.compactMapValues(\.path)
        usageWorker.refresh(sessions: paths, configDirs: configDirs) { [weak self] r in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sessionUsage = r.sessions
                    if self.todayCost != r.todayCost { self.todayCost = r.todayCost }
                    if self.todayTokens != r.todayTokens { self.todayTokens = r.todayTokens }
                    self.usageRefreshing = false
                }
            }
        }
    }

    /// Bölgelerin git durumunu arka planda okur; sonuç bir sonraki taramada anlık görüntüye girer.
    private func refreshGit(roots: [String], now: Date) {
        guard !gitRefreshing, now.timeIntervalSince(lastGitRefresh) >= Self.gitInterval else { return }
        gitRefreshing = true
        lastGitRefresh = now
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var result: [String: GitBadge] = [:]
            for r in roots { if let b = GitRunner.badge(r) { result[r] = b } }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.gitBadges = result
                    self?.gitRefreshing = false
                }
            }
        }
    }


    /// Profilde Claude'u açar (giriş yapmak için içinde /login yazılır).
    /// Profilde `claude auth login`'i çalıştıran bir terminal açar; giriş sayfası tarayıcıda beklenen
    /// e-posta dolu açılır. (Claude'u açıp /login yazmak, zaten girişli profilde giriş ekranı göstermiyor.)
    func login(profile id: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let email = profiles.profiles.first { $0.id == id }?.email
        host.create(.shell, cwd: home, env: profiles.environment(id)) { [weak self] info in
            guard let self else { return }
            self.host.type(info.id, AtolyeIntegration.loginCommand(email: email) + "\r")
            self.changeDesk { $0.open(.terminal(info.id), root: home) }
            self.lastProfilesRefresh = .distantPast
        }
    }

    nonisolated static func isProcessAlive(_ pid: Int32) -> Bool {
        ProcessEnv.isAlive(pid: pid)
    }

    static func play(_ kind: AlertKind) {
        let name: NSSound.Name = switch kind {
        case .attention: "Funk"
        case .finished: "Glass"
        }
        NSSound(named: name)?.play()
    }
}
