import AjanTakipCore
import AppKit

enum AlertPlayer {
    @MainActor
    static func play(_ kind: AlertKind) {
        let name: NSSound.Name = switch kind {
        case .attention: "Funk"
        case .finished: "Glass"
        }
        NSSound(named: name)?.play()
    }
}
