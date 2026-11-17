import Foundation
import Testing
@testable import AjanTakipCore

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("robotpool-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private let glb = Data([0x67, 0x6C, 0x54, 0x46]) + Data(count: 16)

@Suite struct RobotPoolTests {
    @Test func validateRejectsNonGLB() {
        #expect(throws: RobotPoolError.notGLB) { try RobotPool.validate(Data("hello".utf8)) }
    }

    @Test func validateRejectsTooLarge() {
        #expect(throws: RobotPoolError.tooLarge) { try RobotPool.validate(Data([0x67, 0x6C, 0x54, 0x46]) + Data(count: 31_457_280)) }
    }

    @Test func validateAcceptsGLBHeader() throws {
        try RobotPool.validate(glb)
    }

    @Test func addWritesFileAndConfig() throws {
        let dir = tempDir()
        let s = RobotPoolStore(dir: dir)
        let r = try s.add(data: glb, name: "Benim", role: .sub)
        #expect(FileManager.default.fileExists(atPath: s.fileURL(r.id).path))
        let s2 = RobotPoolStore(dir: dir); s2.load()
        #expect(s2.config.customs == [CustomRobot(id: r.id, name: "Benim", role: .sub, flipped: false)])
    }

    @Test func cannotDisableLastMain() throws {
        let s = RobotPoolStore(dir: tempDir())
        try s.setEnabled("usta", false)
        try s.setEnabled("muhendis", false)
        #expect(throws: RobotPoolError.lastInRole) { try s.setEnabled("kasif", false) }
        try s.setEnabled("usta", true)
        try s.setEnabled("kasif", false)
    }

    @Test func customBothCountsForBothRoles() throws {
        let s = RobotPoolStore(dir: tempDir())
        let r = try s.add(data: glb, name: "İkili", role: .both)
        for b in RobotPool.builtins { try s.setEnabled(b.id, false) }
        #expect(throws: RobotPoolError.lastInRole) { try s.remove(r.id) }
        #expect(throws: RobotPoolError.lastInRole) { try s.setEnabled(r.id, false) }
    }

    @Test func removeDeletesFile() throws {
        let s = RobotPoolStore(dir: tempDir())
        let r = try s.add(data: glb, name: "x", role: .main)
        try s.remove(r.id)
        #expect(!FileManager.default.fileExists(atPath: s.fileURL(r.id).path))
        #expect(s.config.customs.isEmpty)
    }

    @Test func sceneRobotsListsEnabledOnly() throws {
        let s = RobotPoolStore(dir: tempDir())
        let r = try s.add(data: glb, name: "x", role: .main)
        try s.setEnabled("vida", false)
        let list = RobotPool.sceneRobots(s.config)
        #expect(list.filter(\.builtin).map(\.id) == ["usta", "muhendis", "kasif", "kivilcim", "pit"])
        #expect(list.first { $0.id == r.id }?.url == "atolye://app/robots/\(r.id).glb")
        #expect(list.filter(\.builtin).allSatisfy { $0.url == nil })
    }
}
