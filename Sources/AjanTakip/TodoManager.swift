import AjanTakipCore
import AppKit
import Observation
import os

/// Oturumların proje kökündeki TODO.local.md dosyalarını izler, okur ve günceller.
@MainActor @Observable
final class TodoManager {
    struct FileState: Equatable {
        var items: [TodoItem]
        var modified: Date?
    }

    private static let log = Logger(subsystem: "com.ajantakip.app", category: "todo")
    /// Proje kökü → dosya durumu (yalnızca dosya varsa).
    private(set) var files: [String: FileState] = [:]
    /// Pencerede açık olan proje kökü.
    var openRoot: String?
    var lastError: String?
    /// TODO.local.md'si olan, hatırlanan proje kökleri; oturum kapansa da listede kalırlar.
    private(set) var knownRoots: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: TodoManager.knownRootsKey) ?? []) {
        didSet { UserDefaults.standard.set(Array(knownRoots).sorted(), forKey: Self.knownRootsKey) }
    }
    private static let knownRootsKey = "todoKnownRoots"
    @ObservationIgnored private var rootForCwd: [String: String] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var sessions: @MainActor () -> [Session] = { [] }

    func root(for session: Session) -> String? {
        guard let cwd = session.cwd else { return nil }
        if let r = rootForCwd[cwd] { return r }
        let r = ProjectRoot.find(cwd: cwd, exists: { FileManager.default.fileExists(atPath: $0) })
        rootForCwd[cwd] = r
        return r
    }

    func progress(for session: Session) -> (done: Int, total: Int)? {
        root(for: session).flatMap(progress(root:))
    }

    func progress(root: String) -> (done: Int, total: Int)? {
        files[root].map { TodoList.progress($0.items) }
    }

    /// TODO dosyası olan ama şu an açık oturumu olmayan projeler (ada göre sıralı).
    var rootsWithoutSession: [String] {
        let active = Set(sessions().compactMap { root(for: $0) })
        return knownRoots.filter { !active.contains($0) && files[$0] != nil }
            .sorted { ($0 as NSString).lastPathComponent.localizedStandardCompare(($1 as NSString).lastPathComponent) == .orderedAscending }
    }

    func toggleWindow(for session: Session) {
        guard let r = root(for: session) else { return }
        toggleWindow(root: r)
    }

    func toggleWindow(root r: String) {
        openRoot = openRoot == r ? nil : r
        lastError = nil
        if let r = openRoot { reload(r) }
    }

    func close() { openRoot = nil }

    /// İzlenen kökleri oturumlara göre günceller ve 2 sn'de bir değişiklik var mı bakar.
    func start(sessions: @escaping @MainActor () -> [Session]) {
        self.sessions = sessions
        tick()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.3
    }

    private func tick() {
        var roots = Set(sessions().compactMap { root(for: $0) })
        roots.formUnion(knownRoots)
        if let o = openRoot { roots.insert(o) }
        for r in roots { reload(r) }
        for r in files.keys where !roots.contains(r) { files[r] = nil }
    }

    /// Dosyanın değişiklik zamanı farklıysa yeniden okur.
    private func reload(_ root: String, force: Bool = false) {
        let path = ProjectRoot.todoPath(root: root)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            if files[root] != nil { files[root] = nil }
            if knownRoots.contains(root) { knownRoots.remove(root) }
            return
        }
        if !knownRoots.contains(root) { knownRoots.insert(root) }
        let modified = attrs[.modificationDate] as? Date
        if !force, let f = files[root], f.modified == modified { return }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        files[root] = FileState(items: TodoList.parse(text), modified: modified)
    }

    func toggle(_ item: TodoItem) {
        edit { TodoList.toggle($0, item: item) }
    }

    func add(_ text: String) {
        edit { TodoList.append($0, item: text) }
    }

    /// Dosyayı tazeden okuyup dönüştürür; madde bu arada değiştiyse yazmaz.
    private func edit(_ transform: (String) -> String?) {
        guard let root = openRoot else { return }
        let path = ProjectRoot.todoPath(root: root)
        let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard let new = transform(old) else {
            lastError = "Dosya bu arada değişmiş; liste yenilendi."
            reload(root, force: true)
            return
        }
        guard new != old else { return }
        do {
            try new.write(toFile: path, atomically: true, encoding: .utf8)
            lastError = nil
        } catch {
            Self.log.error("yazılamadı: \(error.localizedDescription)")
            lastError = "Yazılamadı: \(error.localizedDescription)"
        }
        reload(root, force: true)
    }

    /// Açık projede cmux içinde çalışan, madde gönderilebilecek oturumlar.
    var targets: [Session] {
        guard let root = openRoot else { return [] }
        return sessions().filter { $0.workspace != nil && $0.surface != nil && self.root(for: $0) == root }
    }

    /// Son başarılı gönderim bildirimi (birkaç saniye sonra silinir).
    var lastInfo: String?
    /// Gönderimi sürmekte olan madde satırı.
    var sending: Int?

    func send(_ item: TodoItem, to session: Session) {
        guard sending == nil, let root = openRoot, let items = files[root]?.items else { return }
        let text = TodoList.prompt(for: item, in: items)
        sending = item.line
        lastError = nil
        Task {
            let err = await CmuxNavigator.send(text, to: session)
            sending = nil
            if let err {
                lastError = "Gönderilemedi: \(err)"
            } else {
                let info = "→ \(session.projectName) oturumuna gönderildi"
                lastInfo = info
                try? await Task.sleep(for: .seconds(3))
                if lastInfo == info { lastInfo = nil }
            }
        }
    }

    func openInEditor() {
        guard let root = openRoot else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: ProjectRoot.todoPath(root: root)))
    }
}
