import AtolyeCore
import Foundation

/// Yapılacaklar penceresinin durumu: seçili projenin `TODO.local.md` maddeleri ve git ayarı.
/// Dosya işlemleri küçük olduğu için ana iş parçacığında, git komutları arka planda.
@MainActor
@Observable
final class Todos {
    /// Seçili proje kökü.
    private(set) var root: String?
    private(set) var items: [TodoItem] = []
    /// nil: henüz bakılmadı.
    private(set) var git: TodoGitState?
    private(set) var gitBusy = false
    /// Son hata (pencerede gösterilir).
    var error: String?

    /// Dosya değişince (sahne ve tahta tazelensin diye).
    @ObservationIgnored var onChange: (() -> Void)?

    func select(_ root: String?) {
        guard root != self.root else { reload(); return }
        self.root = root
        git = nil
        error = nil
        reload()
        refreshGit()
    }

    /// Dosyayı yeniden oku (dışarıda değişmiş olabilir).
    func reload() {
        let new = root.map { TodoFile.items(root: $0) } ?? []
        if new != items { items = new }
    }

    func refreshGit() {
        guard let root else { return }
        Task {
            let state = await Task.detached { TodoGit.state(root: root) }.value
            if self.root == root, self.git != state { self.git = state }
        }
    }

    // MARK: Maddeler

    func add(_ text: String) {
        guard let root else { return }
        let existed = FileManager.default.fileExists(atPath: ProjectRoot.todoPath(root: root))
        write { try TodoFile.add(text, root: root) }
        // Yeni dosya: varsayılan olarak bu Mac'te kalsın (git yok saysın).
        if !existed { Task.detached { try? TodoGit.keepLocal(root: root) } }
    }

    func toggle(_ item: TodoItem) { change(item) { TodoList.toggle($0, item: $1) } }
    func delete(_ item: TodoItem) { change(item) { TodoList.delete($0, item: $1) } }
    func edit(_ item: TodoItem, to text: String) { change(item) { TodoList.edit($0, item: $1, to: text) } }
    func indent(_ item: TodoItem, by n: Int) { change(item) { TodoList.indent($0, item: $1, by: n) } }

    /// Listede `from` sırasındaki maddeyi `to` sırasının önüne taşı (SwiftUI onMove sırası).
    func move(from: Int, to: Int) {
        guard items.indices.contains(from) else { return }
        let before = to < items.count ? items[to] : nil
        guard before?.line != items[from].line else { return }
        change(items[from]) { text, item in
            let target = before.flatMap { b in TodoList.parse(text).first { $0.line == b.line && $0.text == b.text } }
            return TodoList.move(text, item: item, before: target)
        }
    }

    private func change(_ item: TodoItem, _ edit: @escaping (String, TodoItem) -> String?) {
        guard let root else { return }
        write {
            if try !TodoFile.change(line: item.line, text: item.text, root: root, edit) {
                // Dosya o arada değişmiş olabilir: yeni haliyle göster.
                reload()
            }
        }
    }

    private func write(_ body: () throws -> Void) {
        do { try body(); error = nil } catch { self.error = L("TODO.local.md yazılamadı") + ": " + error.localizedDescription }
        reload()
        onChange?()
    }

    // MARK: Git

    /// Dosyayı git'e ekle (paylaş) ya da git'ten çıkar. Onayı pencere alır.
    func setShared(_ on: Bool) {
        guard let root, !gitBusy else { return }
        gitBusy = true
        Task {
            let failure: String? = await Task.detached {
                do { try on ? TodoGit.share(root: root) : TodoGit.unshare(root: root); return nil }
                catch { return error.localizedDescription }
            }.value
            gitBusy = false
            if let failure { error = failure }
            refreshGit()
            reload()
            onChange?()
        }
    }
}
