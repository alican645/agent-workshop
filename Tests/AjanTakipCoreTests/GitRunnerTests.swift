import Foundation
import Testing
@testable import AjanTakipCore

@Suite(.serialized) struct GitRunnerTests {
    private func repo() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitrun-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["-c", "user.name=T", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "ilk commit"]] {
            _ = GitRunner.run(args, in: dir)
        }
        try "a\n".write(toFile: dir + "/a.txt", atomically: true, encoding: .utf8)
        try "yeni\n".write(toFile: dir + "/yeni dosya.txt", atomically: true, encoding: .utf8)
        _ = GitRunner.run(["add", "a.txt"], in: dir)
        try "a\nb\n".write(toFile: dir + "/a.txt", atomically: true, encoding: .utf8)
        return dir
    }

    @Test func statusOfRealRepo() throws {
        let dir = try repo()
        let s = try #require(GitRunner.status(dir))
        #expect(s.branch == "main")
        #expect(s.staged.map(\.path) == ["a.txt"] && s.unstaged.map(\.path) == ["a.txt"])
        #expect(s.untracked.map(\.path) == ["yeni dosya.txt"])
        #expect(GitRunner.log(dir, limit: 5).map(\.subject) == ["ilk commit"])
        #expect(GitRunner.badge(dir)?.headSubject == "ilk commit")
    }

    @Test func diffsForEachGroup() throws {
        let dir = try repo()
        #expect(GitRunner.diff(.unstaged("a.txt"), in: dir).contains { $0.kind == .add && $0.text == "+b" })
        #expect(GitRunner.diff(.staged("a.txt"), in: dir).contains { $0.kind == .add && $0.text == "+a" })
        #expect(GitRunner.diff(.untracked("yeni dosya.txt"), in: dir).contains { $0.kind == .add && $0.text == "+yeni" })
        let head = try #require(GitRunner.log(dir, limit: 1).first)
        #expect(GitRunner.diff(.commit(head.hash), in: dir).contains { $0.text.contains("ilk commit") })
    }

    @Test func notARepoIsNil() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("norepo-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        #expect(GitRunner.status(dir) == nil && GitRunner.badge(dir) == nil)
    }
}
