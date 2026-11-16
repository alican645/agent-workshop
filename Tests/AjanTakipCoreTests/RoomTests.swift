import Foundation
import Testing
@testable import AjanTakipCore

@Suite struct RoomTests {
    @Test func addFillsThreePanesThenTabs() {
        var r = Room()
        for id in ["a", "b", "c", "d"] { r.add(.terminal(id)) }
        #expect(r.panes.count == 3)
        #expect(r.panes.map(\.tabs) == [[.terminal("a")], [.terminal("b")], [.terminal("c"), .terminal("d")]])
        #expect(r.focusedPane == 2 && r.panes[2].selected == 1)
        #expect(r.panes.allSatisfy { abs($0.width - 1.0 / 3) < 0.0001 })
    }

    @Test func removeDropsEmptyPane() {
        var r = Room()
        for id in ["a", "b"] { r.add(.terminal(id)) }
        r.remove(.terminal("a"))
        #expect(r.panes.map(\.tabs) == [[.terminal("b")]])
        #expect(r.focusedPane == 0 && r.panes[0].width == 1)
        r.remove(.terminal("b"))
        #expect(r.panes.isEmpty && r.focusedPane == 0)
    }

    @Test func removeKeepsSelectionValid() {
        var r = Room()
        for id in ["a", "b", "c", "d", "e"] { r.add(.terminal(id)) }
        r.remove(.terminal("e"))
        #expect(r.panes[2].tabs == [.terminal("c"), .terminal("d")] && r.panes[2].selected == 1)
    }

    @Test func focusFindsTab() {
        var r = Room()
        for id in ["a", "b", "c", "d"] { r.add(.terminal(id)) }
        let found = r.focus(.terminal("c"))
        #expect(found)
        #expect(r.focusedPane == 2 && r.panes[2].selected == 0)
        let missing = r.focus(.terminal("zzz"))
        #expect(!missing)
    }

    @Test func pruneRemovesDeadTerminals() {
        var r = Room()
        r.add(.terminal("a"))
        r.add(.markdown("/p/README.md"))
        r.add(.terminal("b"))
        r.prune(liveTerminals: ["b"])
        #expect(r.panes.map(\.tabs) == [[.markdown("/p/README.md")], [.terminal("b")]])
    }

    @Test func storeRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rooms-\(UUID()).json")
        #expect(RoomStore.load(from: url) == RoomStore())
        var s = RoomStore()
        s.rooms["/p/erp"] = { var r = Room(); r.add(.terminal("a")); return r }()
        s.pinned = ["/p/x"]
        try s.save(to: url)
        #expect(RoomStore.load(from: url) == s)
    }
}
