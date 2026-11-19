import Darwin
import Foundation
import Testing
@testable import AtolyeHostKit

/// `atolye-hook`'un yaptığı gibi: olayı yazar, yazma ucunu kapatır, cevabı bağlantı kapanana dek okur.
private func hookCall(_ path: String, _ body: String) throws -> String {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    var addr = try HostServer.address(path)
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard ok == 0 else { throw POSIXError(.ECONNREFUSED) }
    var tv = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    let d = Data(body.utf8)
    _ = d.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    shutdown(fd, SHUT_WR)
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fd, &buf, buf.count)
        if n > 0 { out.append(buf, count: n) } else { break }
    }
    return String(decoding: out, as: UTF8.self)
}

private final class Box: @unchecked Sendable {
    let lock = NSLock()
    var got: [String] = []
}

@Suite struct HookServerTests {
    @Test func deliversEventAndReplies() throws {
        let path = "/tmp/hk-\(UUID().uuidString.prefix(8)).sock"
        let box = Box()
        let s = HookServer(socketPath: path) { data, conn in
            let text = String(decoding: data, as: UTF8.self)
            box.lock.withLock { box.got.append(text) }
            // Büyük olay da tamamı gelsin; cevap biraz sonra (bağlantı beklemede kalır).
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { conn.reply(text == "sessiz" ? nil : "cevap:\(text.count)") }
        }
        try s.start()
        defer { s.stop() }
        let big = String(repeating: "x", count: 200_000)
        #expect(try hookCall(path, big) == "cevap:200000")
        #expect(try hookCall(path, "sessiz") == "")
        #expect(box.lock.withLock { box.got.count } == 2)
    }

    @Test func emptyConnectionIsIgnored() throws {
        let path = "/tmp/hk-\(UUID().uuidString.prefix(8)).sock"
        let box = Box()
        let s = HookServer(socketPath: path) { data, conn in
            box.lock.withLock { box.got.append(String(decoding: data, as: UTF8.self)) }
            conn.reply(nil)
        }
        try s.start()
        defer { s.stop() }
        #expect(try hookCall(path, "") == "")
        #expect(box.lock.withLock { box.got.isEmpty })
    }
}
