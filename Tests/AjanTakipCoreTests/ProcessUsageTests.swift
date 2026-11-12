import Testing
@testable import AjanTakipCore

private let chrome = AppBundle(path: "/Applications/Google Chrome.app", name: "Google Chrome")
private let xcode = AppBundle(path: "/Applications/Xcode.app", name: "Xcode")
private let simulator = AppBundle(path: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app", name: "Simulator")

private func p(_ pid: Int32, _ name: String, _ path: String?, cpu: UInt64 = 0, mem: UInt64 = 0) -> ProcessSample {
    ProcessSample(pid: pid, name: name, path: path, cpuTimeNs: cpu, memoryBytes: mem)
}

@Suite struct ProcessUsageTests {
    @Test func helpersGroupUnderOwningApp() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(ProcessUsage.groupName(path: path, fallback: "Google Chrome Helper", apps: [chrome]) == "Google Chrome")
    }

    @Test func nestedAppUsesInnermostKnownApp() {
        let path = simulator.path + "/Contents/MacOS/Simulator"
        #expect(ProcessUsage.groupName(path: path, fallback: "Simulator", apps: [xcode, simulator]) == "Simulator")
    }

    @Test func cliToolKeepsOwnName() {
        #expect(ProcessUsage.groupName(path: "/Users/u/.local/bin/claude", fallback: "claude", apps: [chrome]) == "claude")
        #expect(ProcessUsage.groupName(path: nil, fallback: "node", apps: [chrome]) == "node")
    }

    @Test func prefixMustEndAtBundleBoundary() {
        // "/Applications/Xcode.app-beta/..." Xcode.app'e ait değildir
        #expect(ProcessUsage.groupName(path: "/Applications/Xcode.app-beta/x", fallback: "x", apps: [xcode]) == "x")
    }

    @Test func aggregateSumsCPUDeltaAndMemoryPerGroup() {
        let cp = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        let hp = "/Applications/Google Chrome.app/Contents/Frameworks/H.app/Contents/MacOS/H"
        let prev = [p(1, "Google Chrome", cp, cpu: 1_000_000_000), p(2, "H", hp, cpu: 0), p(3, "claude", "/bin/claude", cpu: 500)]
        let cur = [p(1, "Google Chrome", cp, cpu: 1_400_000_000, mem: 100),
                   p(2, "H", hp, cpu: 200_000_000, mem: 50),
                   p(3, "claude", "/bin/claude", cpu: 500 + 100_000_000, mem: 7)]
        let usage = ProcessUsage.aggregate(previous: prev, current: cur, interval: 2, apps: [chrome])
        let byName = Dictionary(uniqueKeysWithValues: usage.map { ($0.name, $0) })
        #expect(byName["Google Chrome"]?.cpu == 0.3)          // (0.4 + 0.2) s / 2 s
        #expect(byName["Google Chrome"]?.memoryBytes == 150)
        #expect(byName["claude"]?.cpu == 0.05)
        #expect(usage.count == 2)
    }

    @Test func newOrResetProcessContributesNoCPU() {
        let prev = [p(5, "a", nil, cpu: 900)]
        let cur = [p(5, "a", nil, cpu: 100, mem: 1), p(6, "b", nil, cpu: 999_999, mem: 2)]
        let usage = ProcessUsage.aggregate(previous: prev, current: cur, interval: 2, apps: [])
        #expect(usage.allSatisfy { $0.cpu == 0 })
        #expect(usage.count == 2)
    }

    @Test func topSortsDescendingAndLimits() {
        let u = (1...7).map { AppUsage(name: "a\($0)", cpu: Double($0) / 10, memoryBytes: UInt64(8 - $0)) }
        #expect(ProcessUsage.top(u, by: .cpu).map(\.name) == ["a7", "a6", "a5", "a4", "a3"])
        #expect(ProcessUsage.top(u, by: .memory, limit: 2).map(\.name) == ["a1", "a2"])
    }

    @Test func formatting() {
        #expect(ProcessUsage.cpuText(0.182) == "18,2%")
        #expect(ProcessUsage.cpuText(1.5) == "150,0%")
        #expect(ProcessUsage.memoryText(340 * 1_048_576) == "340 MB")
        #expect(ProcessUsage.memoryText(UInt64(1.25 * 1_073_741_824)) == "1,3 GB")
    }
}

@Suite struct ProcessDisplayNameTests {
    @Test func versionedBinaryUsesToolName() {
        #expect(ProcessUsage.displayName(name: "2.1.322", path: "/Users/u/.local/share/claude/versions/2.1.322") == "claude")
    }

    @Test func normalNameUnchanged() {
        #expect(ProcessUsage.displayName(name: "node", path: "/opt/homebrew/bin/node") == "node")
        #expect(ProcessUsage.displayName(name: "2.1.322", path: nil) == "2.1.322")
    }

    @Test func aggregateUsesDisplayName() {
        let s = ProcessSample(pid: 1, name: "2.1.322", path: "/u/.local/share/claude/versions/2.1.322", cpuTimeNs: 0, memoryBytes: 5)
        #expect(ProcessUsage.aggregate(previous: [], current: [s], interval: 2, apps: []).map(\.name) == ["claude"])
    }
}
