import AtolyeCore
import Foundation

/// Günlük token geçmişi (Kullanım penceresi). Bütün oturum kayıtları arka planda, artımlı okunur; günlük
/// toplamlar `usage-days.json`'a yazılır, böylece Claude Code eski kayıtları silse de günler kalır.
@MainActor
@Observable
final class UsageHistoryModel {
    private(set) var days: [String: DailyUsage]
    private(set) var loading = false
    private(set) var lastUpdated: Date?

    @ObservationIgnored private let scanner = HistoryScanner()
    @ObservationIgnored private var lastScan = Date.distantPast
    static let interval: TimeInterval = 600
    nonisolated static let storeURL = URL(fileURLWithPath: Profiles.support + "/usage-days.json")

    init() { days = UsageHistory.load(from: Self.storeURL) }

    var summary: UsageSummary { UsageSummary(days: days, today: UsageMeter.dayKey(Date())) }

    /// Tarama zamanı geldiyse (ya da `force`) kayıtları yeniden say.
    func refresh(configDirs: [String], force: Bool = false) {
        let now = Date()
        guard !loading, force || now.timeIntervalSince(lastScan) >= Self.interval else { return }
        loading = true
        lastScan = now
        scanner.scan(configDirs: configDirs) { [weak self] computed in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let merged = UsageHistory.merge(stored: self.days, computed: computed)
                    if merged != self.days {
                        self.days = merged
                        try? UsageHistory.save(merged, to: Self.storeURL)
                    }
                    self.lastUpdated = Date()
                    self.loading = false
                }
            }
        }
    }
}

/// Kayıtları arka planda sayar. Sayaçlar dosya yoluna göre saklanır; ikinci taramadan itibaren yalnız
/// son taramadan sonra değişen kayıtların yeni satırları okunur.
private final class HistoryScanner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "atolye.usage-history", qos: .utility)
    // Yalnız `queue` üzerinde dokunulur.
    private var meters: [String: UsageMeter] = [:]
    private var perFile: [String: [String: DailyUsage]] = [:]
    private var since = Date.distantPast

    func scan(configDirs: [String], done: @escaping @Sendable ([String: DailyUsage]) -> Void) {
        queue.async { [self] in
            let start = Date()
            for path in TranscriptFiles.modified(since: since, in: configDirs) {
                var m = meters[path] ?? UsageMeter()
                perFile[path] = m.read(transcript: path).byDay()
                meters[path] = m
            }
            // Silinen kayıtları unut (saklanan günlük toplamlarda kalırlar).
            for path in perFile.keys where !FileManager.default.fileExists(atPath: path) {
                perFile[path] = nil; meters[path] = nil
            }
            since = start.addingTimeInterval(-60)
            var total: [String: DailyUsage] = [:]
            for days in perFile.values {
                for (k, v) in days { total[k] = (total[k] ?? DailyUsage(tokens: 0, cost: 0)) + v }
            }
            done(total)
        }
    }
}
