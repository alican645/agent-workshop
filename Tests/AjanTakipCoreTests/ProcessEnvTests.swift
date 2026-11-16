import Foundation
import Testing
@testable import AjanTakipCore

@Suite struct ProcessEnvTests {
    @Test func parsesProcargsLayout() {
        var bytes: [UInt8] = [2, 0, 0, 0]
        bytes += Array("/bin/x".utf8) + [0, 0, 0]
        bytes += Array("a".utf8) + [0] + Array("b".utf8) + [0]
        bytes += Array("K=V".utf8) + [0] + Array("CMUX_WORKSPACE_ID=W".utf8) + [0, 0]
        bytes += Array("ptr_munge=junk".utf8) + [0]
        #expect(ProcessEnv.parse(procargs: bytes) == ["K": "V", "CMUX_WORKSPACE_ID": "W"])
    }

    /// Sistem (platform) ikili dosyalarının ortamı çekirdekçe gizlenir; bu yüzden kendi sürecimizle denenir.
    @Test func readsOwnEnvironment() {
        let env = ProcessEnv.environment(pid: getpid())
        #expect(env?["HOME"] == ProcessInfo.processInfo.environment["HOME"])
        #expect(env?["HOME"] != nil)
    }

    @Test func cmuxIDsFromEnvironment() {
        #expect(ProcessEnv.cmuxIDs(env: ["CMUX_WORKSPACE_ID": "W1", "CMUX_SURFACE_ID": "S1"]) == CmuxIDs(workspace: "W1", surface: "S1"))
        #expect(ProcessEnv.cmuxIDs(env: ["CMUX_WORKSPACE_ID": "W1", "CMUX_SURFACE_ID": ""]) == CmuxIDs(workspace: "W1", surface: nil))
        #expect(ProcessEnv.cmuxIDs(env: ["A": "1"]) == nil)
        #expect(ProcessEnv.cmuxIDs(env: ["CMUX_WORKSPACE_ID": ""]) == nil)
    }

    @Test func deadPidIsNil() {
        #expect(ProcessEnv.environment(pid: 999_999) == nil)
    }
}
