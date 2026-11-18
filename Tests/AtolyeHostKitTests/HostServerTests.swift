import AtolyeCore
import Darwin
import Foundation
import Testing
@testable import AtolyeHostKit

/// Ham soket üzerinden konuşan test istemcisi.
final class RawClient {
    let fd: Int32
    private var reader = Frame.Reader()
    private var events: [HostEvent] = []

    init(_ path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = try HostServer.address(path)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { throw POSIXError(.ECONNREFUSED) }
        var tv = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    func send(_ r: HostRequest) { sendRaw(Frame.encode(r)) }

    func sendRaw(_ d: Data) { _ = d.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } }

    /// Koşulu sağlayan ilk olayı bekler (en çok `timeout` sn).
    func next(timeout: TimeInterval = 5, _ match: (HostEvent) -> Bool) -> HostEvent? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let i = events.firstIndex(where: match) { return events.remove(at: i) }
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                for body in reader.push(Data(buf[0..<n])) {
                    if let e = try? JSONDecoder().decode(HostEvent.self, from: body) { events.append(e) }
                }
            } else if n == 0 { return nil }
        }
        return nil
    }

    /// `id` terminalinden gelen çıktı `text`'i içerene kadar bekler.
    func waitOutput(_ id: String, contains text: String, timeout: TimeInterval = 5) -> Bool {
        var acc = Data()
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if case let .output(_, d)? = next(timeout: 0.2, { if case let .output(i, _) = $0 { i == id } else { false } }) {
                acc.append(d)
                if String(decoding: acc, as: UTF8.self).contains(text) { return true }
            }
        }
        return false
    }

    /// Sunucu bağlantıyı kapattı mı (EOF)?
    func closedByServer(timeout: TimeInterval = 2) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        var buf = [UInt8](repeating: 0, count: 4096)
        while Date() < end {
            let n = read(fd, &buf, buf.count)
            if n == 0 { return true }
            if n < 0 && errno != EAGAIN && errno != EINTR { return true }
        }
        return false
    }

    func created() -> TerminalInfo? {
        if case let .created(info)? = next({ if case .created = $0 { true } else { false } }) { return info }
        return nil
    }

    deinit { close(fd) }
}

private func makeServer(_ cmd: [String], idle: TimeInterval? = nil, onIdle: @escaping @Sendable () -> Void = {}) throws -> (HostServer, String) {
    let path = "/tmp/ah-\(UUID().uuidString.prefix(8)).sock"
    let s = HostServer(socketPath: path, idleExit: idle, onIdle: onIdle)
    s.commandOverride = { _ in cmd }
    try s.start()
    return (s, path)
}

@Suite(.serialized) struct HostServerTests {
    @Test func createAttachReadsOutput() throws {
        let (s, path) = try makeServer(["/bin/sh", "-c", "echo merhaba; sleep 5"])
        defer { s.stop() }
        let c = try RawClient(path)
        c.send(.create(kind: .shell, cwd: "/tmp", cols: 80, rows: 24))
        let t = try #require(c.created())
        #expect(t.running && t.pid > 0 && t.cwd == "/tmp")
        c.send(.attach(id: t.id))
        #expect(c.waitOutput(t.id, contains: "merhaba"))
    }

    /// Dock'tan açılan uygulamada PATH kısadır; `claude` yolu ~/.zprofile'dan gelir, bu yüzden giriş kabuğu şart.
    @Test func claudeRunsInLoginShell() {
        let cmd = HostServer.command(for: .claude)
        #expect(cmd.contains("-il") && cmd.last?.contains("exec zsh -il") == true)
    }

    /// Profil değişince oturum `claude --resume <id>` ile sürer; argümanlar kabuğa tırnaklı gider.
    @Test func claudeArgsAreQuoted() {
        let cmd = HostServer.command(for: .claude, args: ["--resume", "abc-1", "it's"])
        #expect(cmd.last == "claude '--resume' 'abc-1' 'it'\\''s'; exec zsh -il")
        #expect(HostServer.command(for: .claude, args: []) == HostServer.command(for: .claude))
    }

    /// Yeni yardımcı argümanları geri bildirir: eski yardımcı (bildirmeyen) uygulamada tanınır.
    @Test func createEchoesArgs() throws {
        let (s, path) = try makeServer(["/bin/sh", "-c", "sleep 5"])
        defer { s.stop() }
        let c = try RawClient(path)
        c.send(.create(kind: .claude, cwd: "/tmp", cols: 80, rows: 24, args: ["--resume", "x"]))
        let t = try #require(c.created())
        #expect(t.args == ["--resume", "x"])
    }

    @Test func createPassesEnvironment() throws {
        let (s, path) = try makeServer(["/bin/sh", "-c", "echo profil=$CLAUDE_CONFIG_DIR; sleep 5"])
        defer { s.stop() }
        let c = try RawClient(path)
        c.send(.create(kind: .shell, cwd: "/tmp", cols: 80, rows: 24, env: ["CLAUDE_CONFIG_DIR": "/p/x"]))
        let t = try #require(c.created())
        c.send(.attach(id: t.id))
        #expect(c.waitOutput(t.id, contains: "profil=/p/x"))
    }

    @Test func inputReachesProcess() throws {
        let (s, path) = try makeServer(["/bin/cat"])
        defer { s.stop() }
        let c = try RawClient(path)
        c.send(.create(kind: .shell, cwd: "/tmp", cols: 80, rows: 24))
        let t = try #require(c.created())
        c.send(.attach(id: t.id))
        c.send(.input(id: t.id, data: Data("selam\n".utf8)))
        #expect(c.waitOutput(t.id, contains: "selam"))
    }

    @Test func reattachReplaysBuffer() throws {
        let (s, path) = try makeServer(["/bin/sh", "-c", "echo merhaba; sleep 5"])
        defer { s.stop() }
        var c: RawClient? = try RawClient(path)
        c!.send(.create(kind: .shell, cwd: "/tmp", cols: 80, rows: 24))
        let t = try #require(c!.created())
        c!.send(.attach(id: t.id))
        #expect(c!.waitOutput(t.id, contains: "merhaba"))
        c = nil
        let c2 = try RawClient(path)
        c2.send(.attach(id: t.id))
        #expect(c2.waitOutput(t.id, contains: "merhaba"))
    }

    @Test func twoClientsBothReceive() throws {
        let (s, path) = try makeServer(["/bin/cat"])
        defer { s.stop() }
        let a = try RawClient(path), b = try RawClient(path)
        a.send(.create(kind: .shell, cwd: "/tmp", cols: 80, rows: 24))
        let t = try #require(a.created())
        a.send(.attach(id: t.id))
        b.send(.attach(id: t.id))
        Thread.sleep(forTimeInterval: 0.2)
        a.send(.input(id: t.id, data: Data("ikisi\n".utf8)))
        #expect(a.waitOutput(t.id, contains: "ikisi"))
        #expect(b.waitOutput(t.id, contains: "ikisi"))
    }

    @Test func exitedEventAndListState() throws {
        let (s, path) = try makeServer(["/bin/sh", "-c", "sleep 0.3; exit 3"])
        defer { s.stop() }
        let c = try RawClient(path)
        c.send(.create(kind: .shell, cwd: "/tmp", cols: 80, rows: 24))
        let t = try #require(c.created())
        c.send(.attach(id: t.id))
        let e = c.next { if case .exited = $0 { true } else { false } }
        #expect(e == .exited(id: t.id, code: 3))
        c.send(.list)
        if case let .terminals(list)? = c.next({ if case .terminals = $0 { true } else { false } }) {
            #expect(list.map(\.running) == [false] && list.first?.exitCode == 3)
        } else { Issue.record("liste gelmedi") }
    }

    @Test func killRemovesTerminal() throws {
        let (s, path) = try makeServer(["/bin/cat"])
        defer { s.stop() }
        let c = try RawClient(path)
        c.send(.create(kind: .shell, cwd: "/tmp", cols: 80, rows: 24))
        let t = try #require(c.created())
        c.send(.kill(id: t.id))
        c.send(.list)
        let e = c.next { if case .terminals = $0 { true } else { false } }
        #expect(e == .terminals([]))
    }

    /// Kabuk iş denetimiyle çocuğu ayrı süreç grubuna koyar ve çocuk SIGHUP'ı yok sayar (Claude Code gibi);
    /// terminal kapanınca yine de ölmeli, yoksa terminalsiz "bekliyor" durumunda asılı kalır.
    @Test func killEndsChildrenInOtherProcessGroups() throws {
        let (s, path) = try makeServer(["/bin/zsh", "-f", "-i", "-c", "trap '' HUP; sleep 300; :"])
        defer { s.stop() }
        let c = try RawClient(path)
        c.send(.create(kind: .shell, cwd: "/tmp", cols: 80, rows: 24))
        let t = try #require(c.created())
        Thread.sleep(forTimeInterval: 0.5)
        let kids = ProcessTree.descendants(of: t.pid)
        #expect(!kids.isEmpty)
        #expect(kids.allSatisfy { getpgid($0) != t.pid }) // gerçekten başka grupta
        c.send(.kill(id: t.id))
        Thread.sleep(forTimeInterval: 1.5)
        #expect(kids.allSatisfy { Darwin.kill($0, 0) != 0 })
    }

    @Test func envHasTerminalID() throws {
        let (s, path) = try makeServer(["/bin/sh", "-c", "echo id=$ATOLYE_TERMINAL_ID; sleep 5"])
        defer { s.stop() }
        let c = try RawClient(path)
        c.send(.create(kind: .shell, cwd: "/tmp", cols: 80, rows: 24))
        let t = try #require(c.created())
        c.send(.attach(id: t.id))
        #expect(c.waitOutput(t.id, contains: "id=\(t.id)"))
    }

    @Test func garbageFrameClosesOnlyThatClient() throws {
        let (s, path) = try makeServer(["/bin/cat"])
        defer { s.stop() }
        let bad = try RawClient(path), good = try RawClient(path)
        bad.sendRaw(Data([0xFF, 0xFF, 0xFF, 0xFF, 0]))
        #expect(bad.closedByServer())
        good.send(.list)
        #expect(good.next { if case .terminals = $0 { true } else { false } } == .terminals([]))
    }

    @Test func idleExitFires() async throws {
        let fired = Fired()
        let (s, _) = try makeServer(["/bin/cat"], idle: 0.3, onIdle: { fired.set() })
        defer { s.stop() }
        try await Task.sleep(for: .milliseconds(800))
        #expect(fired.value)
    }
}

final class Fired: @unchecked Sendable {
    private let lock = NSLock()
    private var v = false
    func set() { lock.withLock { v = true } }
    var value: Bool { lock.withLock { v } }
}
