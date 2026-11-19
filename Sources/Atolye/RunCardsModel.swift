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
        let new = root.map { RunCardFile.cards(root: $0) } ?? []
        if new != cards { cards = new }
    }

    @discardableResult
    func add() -> RunCard {
        let card = RunCard(name: L("Yeni kart"), command: "", confirm: true)
        change { $0.append(card) }
        return card
    }

    func update(_ card: RunCard) {
        change { list in
            if let i = list.firstIndex(where: { $0.id == card.id }) { list[i] = card }
        }
    }

    func delete(_ card: RunCard) { change { $0.removeAll { $0.id == card.id } } }

    func move(from: IndexSet, to: Int) { change { $0.move(fromOffsets: from, toOffset: to) } }

    /// Dosyanın son halini okuyup değiştirir (pencere açıkken elle düzenlenmiş olabilir).
    private func change(_ edit: (inout [RunCard]) -> Void) {
        guard let root else { return }
        let existed = FileManager.default.fileExists(atPath: RunCardFile.path(root: root))
        var list = RunCardFile.cards(root: root)
        edit(&list)
        do {
            try RunCardFile.write(list, root: root)
            error = nil
        } catch {
            self.error = L("RUN.local.json yazılamadı") + ": " + error.localizedDescription
        }
        // Yeni dosya: varsayılan olarak bu Mac'te kalsın (git yok saysın).
        if !existed { Task.detached { try? TodoGit.keepLocal(root: root, file: RunCardFile.fileName) } }
        reload()
        onChange?()
    }
}
