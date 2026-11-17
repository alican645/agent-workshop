import Foundation
import Testing
@testable import AjanTakipCore

private func entryJSON(pid: Int32, sid: String) -> String {
    #"{"pid":\#(pid),"sessionId":"\#(sid)","cwd":"/x/erp","status":"busy","updatedAt":1}"#
}

/// Geçici bir profil dizini: `sessions/` altına verilen dosyaları yazar, dizini döner.
private func tmpProfile(_ files: [String: String]) throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ajantakip-reg-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: dir + "/sessions", withIntermediateDirectories: true)
    for (name, body) in files { try body.write(toFile: dir + "/sessions/" + name, atomically: true, encoding: .utf8) }
    return dir
}

/// Dosyayı yazar ve mtime'ı ileri alır (aynı saniye içinde değişiklik görünsün).
private func writeAfterTick(_ path: String, _ body: String) throws {
    try body.write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: path)
}

@Suite struct RegistryScannerTests {
    @Test func readsAllProfiles() throws {
        let a = try tmpProfile(["42.json": entryJSON(pid: 42, sid: "s1")])
        let b = try tmpProfile(["7.json": entryJSON(pid: 7, sid: "s2")])
        var sc = RegistryScanner()
        let r = sc.scan(dirs: [("default", a), ("p2", b)], isAlive: { _ in true })
        #expect(Set(r.map { "\($0.profileID):\($0.sessionID)" }) == ["default:s1", "p2:s2"])
    }

    @Test func ignoresNonPidFilesAndDeadProcesses() throws {
        let a = try tmpProfile(["42.json": entryJSON(pid: 42, sid: "s1"), "x.json": entryJSON(pid: 1, sid: "z"),
                                "43.json": entryJSON(pid: 43, sid: "s3"), "44.abc.key": "k"])
        var sc = RegistryScanner()
        #expect(sc.scan(dirs: [("d", a)], isAlive: { $0 == 42 }).map(\.sessionID) == ["s1"])
    }

    @Test func corruptFileKeepsPreviousEntry() throws {
        let a = try tmpProfile(["42.json": entryJSON(pid: 42, sid: "s1")])
        var sc = RegistryScanner()
        _ = sc.scan(dirs: [("d", a)], isAlive: { _ in true })
        try writeAfterTick(a + "/sessions/42.json", #"{"pid":42,"#)
        #expect(sc.scan(dirs: [("d", a)], isAlive: { _ in true }).map(\.sessionID) == ["s1"])
    }

    @Test func changedFileIsReread() throws {
        let a = try tmpProfile(["42.json": entryJSON(pid: 42, sid: "s1")])
        var sc = RegistryScanner()
        _ = sc.scan(dirs: [("d", a)], isAlive: { _ in true })
        try writeAfterTick(a + "/sessions/42.json", entryJSON(pid: 42, sid: "s9"))
        #expect(sc.scan(dirs: [("d", a)], isAlive: { _ in true }).map(\.sessionID) == ["s9"])
    }

    @Test func removedFileDisappears() throws {
        let a = try tmpProfile(["42.json": entryJSON(pid: 42, sid: "s1")])
        var sc = RegistryScanner()
        _ = sc.scan(dirs: [("d", a)], isAlive: { _ in true })
        try FileManager.default.removeItem(atPath: a + "/sessions/42.json")
        #expect(sc.scan(dirs: [("d", a)], isAlive: { _ in true }).isEmpty)
    }

    @Test func missingDirIsEmpty() {
        var sc = RegistryScanner()
        #expect(sc.scan(dirs: [("d", "/nonexistent-\(UUID())")], isAlive: { _ in true }).isEmpty)
    }
}
