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
        guard let r = root(for: session), let f = files[r] else { return nil }
        return TodoList.progress(f.items)
    }

    func toggleWindow(for session: Session) {
        guard let r = root(for: session) else { return }
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
        if let o = openRoot { roots.insert(o) }
        for r in roots { reload(r) }
        for r in files.keys where !roots.contains(r) { files[r] = nil }
    }

    /// Dosyanın değişiklik zamanı farklıysa yeniden okur.
    private func reload(_ root: String, force: Bool = false) {
        let path = ProjectRoot.todoPath(root: root)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            if files[root] != nil { files[root] = nil }
            return
        }
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

    func openInEditor() {
        guard let root = openRoot else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: ProjectRoot.todoPath(root: root)))
    }
}
