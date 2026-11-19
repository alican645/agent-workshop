import AtolyeCore
import Foundation

/// Çalıştırma kartları penceresinin durumu: seçili projenin `RUN.local.json` kartları.
@MainActor
@Observable
final class RunCardsModel {
    private(set) var root: String?
    private(set) var cards: [RunCard] = []
    var error: String?

    /// Dosya değişince (sahne tazelensin diye).
    @ObservationIgnored var onChange: (() -> Void)?

    func select(_ root: String?) {
        guard root != self.root else { reload(); return }
        self.root = root
        error = nil
        reload()
    }

    /// Dosyayı yeniden oku (elle düzenlenmiş olabilir).
    func reload() {
        guard let root else { if !cards.isEmpty { cards = [] }; return }
        guard let new = RunCardFile.load(root: root) else {
            error = Self.unreadableText
            return
        }
        if error == Self.unreadableText { error = nil } // dosya düzeltildi
        if new != cards { cards = new }
    }

    private static var unreadableText: String { L("RUN.local.json okunamadı; dosyayı düzeltince kartlar yeniden görünür. Bozuk dosyanın üstüne yazılmadı.") }

    @discardableResult
    func add() -> RunCard {
        let card = RunCard(name: L("Yeni kart"), command: "", confirm: true)
        change { $0.append(card) }
        return card
    }

    /// Yalnız verilen alanları değiştirir; kartın geri kalanı dosyadaki son halinden gelir
    /// (ör. az önce işaretlenen "Önce sor" bir ad kaydıyla geri dönmesin).
    func edit(_ id: String, _ apply: @escaping (inout RunCard) -> Void) {
        change { list in
            if let i = list.firstIndex(where: { $0.id == id }) { apply(&list[i]) }
        }
    }

    func delete(_ id: String) { change { $0.removeAll { $0.id == id } } }

    /// Görünen listedeki sırayla taşır; kartlar kimlikle bulunur (dosya o arada değişmiş olabilir).
    func move(from: IndexSet, to: Int) {
        var ids = cards.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        change { list in
            let rank = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            list = list.enumerated().sorted { (rank[$0.element.id] ?? ids.count + $0.offset, $0.offset) < (rank[$1.element.id] ?? ids.count + $1.offset, $1.offset) }.map(\.element)
        }
    }

    /// Dosyanın son halini okuyup değiştirir. Bozuk dosyanın üstüne yazmaz.
    private func change(_ edit: @escaping (inout [RunCard]) -> Void) {
        guard let root else { return }
        let existed = FileManager.default.fileExists(atPath: RunCardFile.path(root: root))
        do {
            try RunCardFile.update(root: root, edit)
            error = nil
        } catch is RunCardFile.Unreadable {
            error = Self.unreadableText
        } catch {
            self.error = L("RUN.local.json yazılamadı") + ": " + error.localizedDescription
        }
        // Yeni dosya: varsayılan olarak bu Mac'te kalsın (git yok saysın).
        if !existed { Task.detached { try? TodoGit.keepLocal(root: root, file: RunCardFile.fileName) } }
        reload()
        onChange?()
    }
}
