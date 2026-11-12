import AjanTakipCore
import Foundation
import Observation

struct AlertEvent: Equatable {
    var kind: AlertKind
    var at: Date
}

@MainActor @Observable
final class AppModel {
    var store = SessionStore()
    var lastAlert: AlertEvent?
    /// Kenarlık nabzı; liste açılınca temizlenir.
    var pulsing: AlertKind?
    /// Her `.attention` uyarısında artar; titreme animasyonunu tetikler.
    var shakeCount = 0
    var isExpanded = false {
        didSet { if isExpanded { pulsing = nil } }
    }
    var serverError: String?
    var hooksInstalled = false

    var soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    var pillVisible = UserDefaults.standard.object(forKey: "pillVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pillVisible, forKey: "pillVisible") }
    }

    private var pruneTimer: Timer?

    func handle(_ e: HookEvent) {
        let kind = store.apply(e, now: .now)
        pulsing = Pulse.next(current: pulsing, alert: kind, waitingCount: store.counts.waiting, expanded: isExpanded)
        guard let kind else { return }
        lastAlert = AlertEvent(kind: kind, at: .now)
        if kind == .attention { shakeCount += 1 }
        if soundEnabled { AlertPlayer.play(kind) }
    }

    func startPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.pruneStale(now: .now, isAlive: AppModel.isProcessAlive)
            }
        }
    }

    nonisolated static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Öncelik: AJANTAKIP_PORT env → ~/.config/ajantakip/config (`port=`) → 47823
    nonisolated static func configuredPort() -> UInt16 {
        if let env = ProcessInfo.processInfo.environment["AJANTAKIP_PORT"], let p = UInt16(env) { return p }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ajantakip/config")
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") where line.hasPrefix("port=") {
                if let p = UInt16(line.dropFirst(5).trimmingCharacters(in: .whitespaces)) { return p }
            }
        }
        return 47823
    }
}
