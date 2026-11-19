import Darwin
import Foundation
import Testing
@testable import AtolyeHostKit

@Suite(.serialized) struct HostTeardownTests {
    /// Yardımcı öldürülünce torunları (claude gibi SIGHUP/SIGTERM'i yok sayanlar dahil) da biter;
    /// fonksiyon döndüğünde hiçbiri yaşamıyor (oturum ikinci kez açılmadan önce).
    @Test func killsHelperAndStubbornDescendants() async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sh -c 'trap \"\" TERM HUP; while :; do sleep 1; done' & wait"]
        try p.run()
        try await Task.sleep(for: .milliseconds(300))
        let kids = ProcessTree.descendants(of: p.processIdentifier)
        try #require(!kids.isEmpty)
        let done = await HostTeardown.terminate(helper: p.processIdentifier, graceful: false, grace: 1)
        #expect(done)
        p.waitUntilExit()
        try await Task.sleep(for: .milliseconds(200))
        for k in kids { #expect(Darwin.kill(k, 0) != 0, "torun yaşıyor: \(k)") }
    }
}
