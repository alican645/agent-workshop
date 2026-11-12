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
        didSet {
            if isExpanded { pulsing = nil } else { expandedMetric = nil }
        }
    }

    /// Hangi kullanım satırının (CPU/RAM) program listesi açık.
    var expandedMetric: ProcessUsage.Metric?
    /// Açık metriğe göre en çok tüketen programlar.
    var topProcesses: [AppUsage] = []
    /// CPU için ilk iki örnek alınana kadar false.
    var processesReady = false
    private var lastProcesses: [ProcessSample]?
    private var lastProcessSampleAt: Date?
    var serverError: String?
    var hooksInstalled = false

    var soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    var pillVisible = UserDefaults.standard.object(forKey: "pillVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pillVisible, forKey: "pillVisible") }
    }

    /// Sistem kullanımı (0…1); ilk iki örnekten önce nil.
    var cpuUsage: Double?
    var ramUsage: Double?
    var showSystemStats = UserDefaults.standard.object(forKey: "showSystemStats") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showSystemStats, forKey: "showSystemStats") }
    }

    private var pruneTimer: Timer?
    private var statsTimer: Timer?
    private var lastTicks: CPUTicks?

    /// Her 2 sn'de CPU/RAM örnekler.
    func startStatsTimer() {
        sampleStats()
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleStats() }
        }
        statsTimer?.tolerance = 0.2
    }

    func toggleMetric(_ metric: ProcessUsage.Metric) {
        expandedMetric = expandedMetric == metric ? nil : metric
        lastProcesses = nil
        processesReady = false
        topProcesses = []
        guard expandedMetric != nil else { return }
        sampleProcesses()
        // CPU için ikinci örneği beklemeden kısa sürede göster.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.sampleProcesses() }
    }

    /// Yalnızca bir program listesi açıkken süreçleri tarar (arka planda).
    private func sampleProcesses() {
        guard expandedMetric != nil, isExpanded else { return }
        let apps = ProcessSampler.runningApps()
        Task.detached(priority: .utility) { [weak self] in
            let samples = ProcessSampler.sample()
            await self?.ingest(samples, apps: apps, at: Date())
        }
    }

    private func ingest(_ samples: [ProcessSample], apps: [AppBundle], at now: Date) {
        guard let metric = expandedMetric else { return }
        let interval = lastProcessSampleAt.map { now.timeIntervalSince($0) } ?? 0
        let usage = ProcessUsage.aggregate(previous: lastProcesses ?? [], current: samples,
                                           interval: interval, apps: apps)
        processesReady = lastProcesses != nil || metric == .memory
        topProcesses = ProcessUsage.top(usage, by: metric)
        lastProcesses = samples
        lastProcessSampleAt = now
    }

    private func sampleStats() {
        sampleProcesses()
        guard showSystemStats else {
            lastTicks = nil
            return
        }
        if let ticks = SystemMonitor.cpuTicks() {
            if let lastTicks { cpuUsage = SystemStats.cpuUsage(previous: lastTicks, current: ticks) }
            lastTicks = ticks
        }
        ramUsage = SystemMonitor.memory()?.usedFraction
    }

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
