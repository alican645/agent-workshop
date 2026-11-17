import Foundation
import Testing
@testable import AjanTakipCore

struct UsageSourcesTests {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("us-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Profil 2'nin projects klasörü Profil 1'inkine symlink: aynı kayıt iki kez sayılmasın.
    @Test func symlinkedProjectsCountedOnce() throws {
        let root = tempDir(), fm = FileManager.default
        let main = root.appendingPathComponent("main"), p2 = root.appendingPathComponent("p2")
        try fm.createDirectory(at: main.appendingPathComponent("projects/a"), withIntermediateDirectories: true)
        try fm.createDirectory(at: p2, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: p2.appendingPathComponent("projects"), withDestinationURL: main.appendingPathComponent("projects"))
        try Data("{}\n".utf8).write(to: main.appendingPathComponent("projects/a/s.jsonl"))
        let files = TranscriptFiles.modified(since: .distantPast, in: [main.path, p2.path])
        #expect(files.count == 1)
        #expect(TranscriptFiles.canonical(p2.appendingPathComponent("projects/a/s.jsonl").path) == files.first)
    }

    @Test func skipsNonDirectoriesInProjects() throws {
        let main = tempDir()
        try FileManager.default.createDirectory(at: main.appendingPathComponent("projects"), withIntermediateDirectories: true)
        try Data().write(to: main.appendingPathComponent("projects/.DS_Store"))
        #expect(TranscriptFiles.modified(since: .distantPast, in: [main.path]).isEmpty)
    }

    private func u(_ f: Double, _ t: TimeInterval) -> AccountUsage {
        AccountUsage(fiveHour: f, fiveHourResetsAt: nil, sevenDay: nil, sevenDayResetsAt: nil, reportedAt: Date(timeIntervalSince1970: t))
    }

    /// cmux ~/.claude'da Profil 2'nin hesabıyla çalışıyor: Profil 2 o hesabın en taze raporunu göstermeli.
    @Test func limitsFollowAccountNotFolder() {
        let profiles = [(id: "p1", dir: "/a"), (id: "p2", dir: "/b")]
        let r = AccountLimits.byProfile(profiles: profiles,
                                        reports: ["/a": u(0.06, 200), "/b": u(0.0, 100)],
                                        logins: ["/a": "Iki@x.com", "/b": "iki@x.com"])
        #expect(r["p2"]?.fiveHour == 0.06)
        #expect(r["p1"]?.fiveHour == 0.06)
    }

    @Test func limitsStayPerFolderForDifferentAccounts() {
        let profiles = [(id: "p1", dir: "/a"), (id: "p2", dir: "/b")]
        let r = AccountLimits.byProfile(profiles: profiles,
                                        reports: ["/a": u(0.5, 200), "/b": u(0.1, 100)],
                                        logins: ["/a": "bir@x.com", "/b": "iki@x.com"])
        #expect(r["p1"]?.fiveHour == 0.5)
        #expect(r["p2"]?.fiveHour == 0.1)
    }

    @Test func limitsWithoutLoginUseOwnFolder() {
        let r = AccountLimits.byProfile(profiles: [(id: "p1", dir: "/a"), (id: "p2", dir: "/b")],
                                        reports: ["/a": u(0.5, 200)], logins: [:])
        #expect(r["p1"]?.fiveHour == 0.5)
        #expect(r["p2"] == nil)
    }
}
