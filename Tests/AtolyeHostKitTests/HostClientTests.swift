import AtolyeCore
import Foundation
import Testing
@testable import AtolyeHostKit

/// Olayları biriktiren, beklenebilen kutu.
final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [HostEvent] = []
    func add(_ e: HostEvent) { lock.withLock { events.append(e) } }
    func waitFor(_ timeout: TimeInterval = 5, _ match: (HostEvent) -> Bool) -> HostEvent? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let e = lock.withLock({ events.first(where: match) }) { return e }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }
}

private func tmpSocket() -> String { "/tmp/ac-\(UUID().uuidString.prefix(8)).sock" }

/// `swift build` çıktısındaki yardımcı ikili dosyası.
private func builtHost() -> String? {
    var dir = URL(fileURLWithPath: #filePath)
    while dir.path != "/" {
        dir.deleteLastPathComponent()
        let p = dir.appendingPathComponent(".build/debug/atolye-host").path
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return nil
}

@Suite(.serialized) struct HostClientTests {
    @Test func connectsToRunningServerAndLists() throws {
        let path = tmpSocket()
        let s = HostServer(socketPath: path, idleExit: nil, onIdle: {})
        try s.start()
        defer { s.stop() }
        let box = EventBox()
        let c = HostClient(socketPath: path, hostExecutable: nil, onEvent: box.add)
        try c.connect()
        defer { c.close() }
        c.send(.list)
        #expect(box.waitFor { $0 == .terminals([]) } != nil)
    }

    @Test func failsWithoutServerOrExecutable() {
        let c = HostClient(socketPath: tmpSocket(), hostExecutable: nil, onEvent: { _ in })
        #expect(throws: (any Error).self) { try c.connect() }
    }

    @Test func removesStaleSocketAndSpawnsHost() throws {
        let host = try #require(builtHost(), "önce `swift build --product atolye-host`")
        let path = tmpSocket()
        try "bayat".write(toFile: path, atomically: true, encoding: .utf8)
        let box = EventBox()
        let c = HostClient(socketPath: path, hostExecutable: host, onEvent: box.add)
        try c.connect()
        c.send(.list)
        #expect(box.waitFor { $0 == .terminals([]) } != nil)
        let pid = try #require(c.spawnedPID)
        c.close()
        kill(pid, SIGTERM)
    }

    @Test func disconnectReportsError() throws {
        let path = tmpSocket()
        let s = HostServer(socketPath: path, idleExit: nil, onIdle: {})
        try s.start()
        let box = EventBox()
        let c = HostClient(socketPath: path, hostExecutable: nil, onEvent: box.add)
        try c.connect()
        defer { c.close() }
        s.stop()
        #expect(box.waitFor { if case .error = $0 { true } else { false } } != nil)
    }
}
