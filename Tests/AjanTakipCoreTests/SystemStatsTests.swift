import Testing
@testable import AjanTakipCore

@Suite struct SystemStatsTests {
    @Test func cpuUsageFromTickDeltas() {
        let a = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let b = CPUTicks(user: 130, system: 60, idle: 860, nice: 50)  // busy 40, idle 60
        #expect(SystemStats.cpuUsage(previous: a, current: b) == 0.4)
    }

    @Test func cpuUsageZeroDeltaIsZero() {
        let a = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        #expect(SystemStats.cpuUsage(previous: a, current: a) == 0)
    }

    @Test func cpuUsageCounterWrapIsZero() {
        let a = CPUTicks(user: 100, system: 0, idle: 100, nice: 0)
        let b = CPUTicks(user: 10, system: 0, idle: 10, nice: 0)
        #expect(SystemStats.cpuUsage(previous: a, current: b) == 0)
    }

    @Test func memoryUsedMatchesActivityMonitor() {
        // app = internal - purgeable = 300 sayfa, wired 100, compressed 100 → 500 sayfa × 4096 / (1000 × 4096)
        let m = MemorySample(totalBytes: 1000 * 4096, pageSize: 4096,
                             internalPages: 350, purgeablePages: 50, wiredPages: 100, compressedPages: 100)
        #expect(m.usedFraction == 0.5)
    }

    @Test func memoryUsedClampedToOne() {
        let m = MemorySample(totalBytes: 100, pageSize: 1, internalPages: 500, purgeablePages: 0,
                             wiredPages: 0, compressedPages: 0)
        #expect(m.usedFraction == 1)
    }

    @Test(arguments: [(0.0, LoadLevel.normal), (0.599, .normal), (0.60, .high), (0.85, .high), (0.851, .critical), (1.0, .critical)])
    func loadLevelThresholds(_ f: Double, _ expected: LoadLevel) {
        #expect(LoadLevel(fraction: f) == expected)
    }

    @Test func percentText() {
        #expect(SystemStats.percentText(0.344) == "34%")
        #expect(SystemStats.percentText(0.345) == "35%")
        #expect(SystemStats.percentText(-0.1) == "0%")
        #expect(SystemStats.percentText(1.2) == "100%")
    }
}
