import AtolyeCore
import Foundation

/// Oturum kayıtlarındaki token kullanımını arka planda sayar. Sayaçlar dosya yoluna göre tutulur ve artımlı okur;
/// ilk okuma büyük kayıtlarda (onlarca MB) zaman alabildiği için ana iş parçacığında çalışmaz.
final class UsageWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "atolye.usage", qos: .utility)
    // Yalnız `queue` üzerinde dokunulur.
    private var meters: [String: UsageMeter] = [:]
    private var todayFiles: [String] = []
    private var listedAt = Date.distantPast

    static let listInterval: TimeInterval = 60

    struct Result: Sendable {
        /// Oturum kimliği → kullanım.
        var sessions: [String: SessionUsage]
        /// Bugün (yerel gün) kapanmış oturumlar dahil toplam maliyet.
        var todayCost: Double
        var todayTokens: Int
    }

    /// `sessions`: oturum kimliği → kayıt yolu. `configDirs`: bugünkü bütün kayıtları bulmak için profil klasörleri.
    func refresh(sessions: [String: String], configDirs: [String], done: @escaping @Sendable (Result) -> Void) {
        queue.async { [self] in
            let now = Date()
            if now.timeIntervalSince(listedAt) > Self.listInterval {
                todayFiles = TranscriptFiles.modified(since: Calendar.current.startOfDay(for: now), in: configDirs)
                listedAt = now
            }
            // Aynı dosya profil klasöründen (symlink) de gelebilir: gerçek yola göre say.
            let sessions = sessions.mapValues(TranscriptFiles.canonical)
            var usage: [String: SessionUsage] = [:]
            for path in Set(sessions.values).union(todayFiles) {
                var m = meters[path] ?? UsageMeter()
                usage[path] = m.read(transcript: path)
                meters[path] = m
            }
            meters = meters.filter { usage[$0.key] != nil }
            let today = UsageMeter.dayKey(now)
            var cost = 0.0
            for u in usage.values { cost += u.costByDay()[today] ?? 0 }
            let tokens = usage.values.reduce(0) { $0 + $1.tokensByDay()[today, default: 0] }
            done(Result(sessions: sessions.compactMapValues { usage[$0] }, todayCost: cost, todayTokens: tokens))
        }
    }
}
