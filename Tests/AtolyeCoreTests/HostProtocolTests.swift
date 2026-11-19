import Foundation
import Testing
@testable import AtolyeCore

private func roundTrip<T: Codable & Equatable>(_ v: T) -> T? {
    var r = Frame.Reader()
    guard let body = r.push(Frame.encode(v)).first else { return nil }
    return try? JSONDecoder().decode(T.self, from: body)
}

@Suite struct HostProtocolTests {
    let info = TerminalInfo(id: "t1", cwd: "/p/erp", title: "zsh", kind: .shell, pid: 42, running: true,
                            exitCode: nil, lastOutputAt: Date(timeIntervalSince1970: 1_000))

    @Test func roundTripsEveryCase() {
        let reqs: [HostRequest] = [.list, .create(kind: .claude, cwd: "/p", cols: 80, rows: 24), .attach(id: "t1"),
                                   .detach(id: "t1"), .input(id: "t1", data: Data([0, 27, 255])),
                                   .resize(id: "t1", cols: 120, rows: 40), .kill(id: "t1"), .killAll, .screen(id: "t"),
                                   .hello, .shutdown]
        for r in reqs { #expect(roundTrip(r) == r) }
        let evs: [HostEvent] = [.terminals([info]), .created(info), .output(id: "t1", data: Data("ğ\u{1b}[0m".utf8)),
                                .exited(id: "t1", code: 3), .exited(id: "t1", code: nil), .error("x"),
                                .screen(id: "t", lines: ["x"], cursorRow: 0), .hostInfo(version: "abc")]
        for e in evs { #expect(roundTrip(e) == e) }
    }

    @Test func createCarriesOptionalEnvironment() throws {
        let r = HostRequest.create(kind: .claude, cwd: "/p", cols: 80, rows: 24, env: ["CLAUDE_CONFIG_DIR": "/c"])
        #expect(roundTrip(r) == r)
        // Eski istemcinin gönderdiği (env'siz) istek de çözülür.
        let old = #"{"create":{"kind":"shell","cwd":"/p","cols":80,"rows":24}}"#
        #expect(try JSONDecoder().decode(HostRequest.self, from: Data(old.utf8)) == .create(kind: .shell, cwd: "/p", cols: 80, rows: 24, env: nil))
    }

    @Test func createCarriesRunSpec() throws {
        let run = RunSpec(cardID: "c1", name: "Deploy", command: "./deploy.sh")
        let r = HostRequest.create(kind: .shell, cwd: "/p", cols: 80, rows: 24, run: run)
        #expect(roundTrip(r) == r)
        var withRun = info
        withRun.run = run
        #expect(roundTrip(withRun) == withRun)
        // Eski istek kartsız çözülür.
        let old = #"{"create":{"kind":"shell","cwd":"/p","cols":80,"rows":24}}"#
        #expect(try JSONDecoder().decode(HostRequest.self, from: Data(old.utf8)) == .create(kind: .shell, cwd: "/p", cols: 80, rows: 24, run: nil))
        // Eski yardımcının bildirdiği (run alanı olmayan) terminal çözülür.
        let oldInfo = #"{"id":"t","cwd":"/p","title":"zsh","kind":"shell","pid":1,"running":true}"#
        #expect(try JSONDecoder().decode(TerminalInfo.self, from: Data(oldInfo.utf8)).run == nil)
    }

    @Test func readerHandlesSplitAndJoinedFrames() {
        var r = Frame.Reader()
        let a = Frame.encode(HostRequest.list), b = Frame.encode(HostRequest.killAll)
        #expect(r.push(a + b).count == 2)
        let c = Frame.encode(HostRequest.attach(id: "abc"))
        #expect(r.push(c.prefix(2)).isEmpty)
        #expect(r.push(c.dropFirst(2).prefix(3)).isEmpty)
        let out = r.push(c.dropFirst(5))
        #expect(out.count == 1 && (try? JSONDecoder().decode(HostRequest.self, from: out[0])) == .attach(id: "abc"))
        #expect(!r.broken)
    }

    @Test func readerRejectsHugeLength() {
        var r = Frame.Reader()
        #expect(r.push(Data([0xFF, 0xFF, 0xFF, 0xFF, 1, 2])).isEmpty)
        #expect(r.broken)
    }
}

@Suite struct RingBufferTests {
    private func str(_ b: RingBuffer) -> String { String(decoding: b.contents, as: UTF8.self) }

    @Test func ringKeepsNewestBytes() {
        var b = RingBuffer(capacity: 10)
        b.append(Data("0123456789AB".utf8))
        #expect(str(b) == "23456789AB")
    }

    @Test func ringSmallAppends() {
        var b = RingBuffer(capacity: 4)
        for s in ["ab", "cd", "e"] { b.append(Data(s.utf8)) }
        #expect(str(b) == "bcde")
    }

    @Test func ringHugeSingleAppend() {
        var b = RingBuffer(capacity: 4)
        b.append(Data(repeating: 65, count: 999) + Data("wxyz".utf8))
        #expect(str(b) == "wxyz")
    }

    @Test func ringUnderCapacity() {
        var b = RingBuffer(capacity: 8)
        b.append(Data("ab".utf8))
        #expect(str(b) == "ab")
    }
}
