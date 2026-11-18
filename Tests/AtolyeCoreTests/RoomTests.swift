import Foundation
import Testing
@testable import AtolyeCore

@Suite struct RoomTests {
    private func t(_ id: String) -> RoomTab { .terminal(id) }

    /// Düzeni okunur biçimde yazar: bölme `[a,b*]` (* seçili), bölünme `(h a | b)` / `(v a / b)`.
    private func shape(_ r: Room) -> String {
        func node(_ n: LayoutNode) -> String {
            switch n {
            case let .pane(p):
                let names = p.tabs.enumerated().map { i, tab -> String in
                    let s: String = switch tab { case let .terminal(id): id; case let .markdown(p): p; case let .git(r): "git:" + r }
                    return i == p.selected && p.tabs.count > 1 ? s + "*" : s
                }
                return "[" + names.joined(separator: ",") + "]"
            case let .split(_, axis, _, a, b):
                return axis == .horizontal ? "(h \(node(a)) | \(node(b)))" : "(v \(node(a)) / \(node(b)))"
            }
        }
        return r.root.map(node) ?? "∅"
    }

    private func pane(_ r: Room, _ tab: RoomTab) -> String { r.paneID(of: tab)! }

    @Test func addPutsTabsIntoFocusedPane() {
        var r = Room()
        r.add(t("a"))
        r.add(t("b"))
        #expect(shape(r) == "[a,b*]")
        #expect(r.focusedPaneID == pane(r, t("b")))
    }

    @Test func splitRightPutsNewPaneBeside() {
        var r = Room()
        r.add(t("a"))
        r.split(t("b"), beside: pane(r, t("a")), edge: .right)
        #expect(shape(r) == "(h [a] | [b])")
        #expect(r.focusedPaneID == pane(r, t("b")))
        if case let .split(_, _, ratio, _, _) = r.root { #expect(ratio == 0.5) } else { Issue.record("split yok") }
    }

    @Test func splitTopPutsNewPaneFirst() {
        var r = Room()
        r.add(t("a"))
        r.split(t("b"), beside: pane(r, t("a")), edge: .top)
        #expect(shape(r) == "(v [b] / [a])")
    }

    @Test func moveToCenterJoinsTabsAndCollapsesSplit() {
        var r = Room()
        r.add(t("a"))
        r.split(t("b"), beside: pane(r, t("a")), edge: .right)
        r.move(t("b"), to: pane(r, t("a")), edge: .center)
        #expect(shape(r) == "[a,b*]")
        #expect(r.focusedPaneID == pane(r, t("b")))
    }

    @Test func moveToEdgeOfOwnPaneSplitsIt() {
        var r = Room()
        r.add(t("a"))
        r.add(t("b"))
        r.move(t("b"), to: pane(r, t("a")), edge: .bottom)
        #expect(shape(r) == "(v [a] / [b])")
    }

    @Test func moveOnlyTabToOwnEdgeChangesNothing() {
        var r = Room()
        r.add(t("a"))
        let before = r
        r.move(t("a"), to: pane(r, t("a")), edge: .left)
        #expect(r == before)
    }

    @Test func moveIntoNestedPaneAndBack() {
        var r = Room()
        r.add(t("a"))
        r.split(t("b"), beside: pane(r, t("a")), edge: .right)
        r.split(t("c"), beside: pane(r, t("b")), edge: .bottom)
        #expect(shape(r) == "(h [a] | (v [b] / [c]))")
        r.move(t("a"), to: pane(r, t("c")), edge: .right)
        #expect(shape(r) == "(v [b] / (h [c] | [a]))")
    }

    @Test func moveWithIndexReordersTabs() {
        var r = Room()
        for id in ["a", "b", "c"] { r.add(t(id)) }
        r.move(t("c"), to: pane(r, t("a")), edge: .center, index: 0)
        #expect(shape(r) == "[c*,a,b]")
    }

    @Test func removeCollapsesSplitAndKeepsFocusValid() {
        var r = Room()
        r.add(t("a"))
        r.split(t("b"), beside: pane(r, t("a")), edge: .right)
        r.split(t("c"), beside: pane(r, t("b")), edge: .bottom)
        r.remove(t("c"))
        #expect(shape(r) == "(h [a] | [b])")
        #expect(r.panes.contains { $0.id == r.focusedPaneID })
        r.remove(t("a"))
        r.remove(t("b"))
        #expect(r.root == nil && r.focusedPaneID == nil)
    }

    @Test func removeKeepsSelectionValid() {
        var r = Room()
        for id in ["a", "b", "c"] { r.add(t(id)) }
        r.remove(t("c"))
        #expect(shape(r) == "[a,b*]")
    }

    @Test func focusFindsTab() {
        var r = Room()
        r.add(t("a"))
        r.add(t("b"))
        r.split(t("c"), beside: pane(r, t("a")), edge: .right)
        let found = r.focus(t("a"))
        #expect(found)
        #expect(r.focusedPaneID == pane(r, t("a")) && r.focusedPane?.current == t("a"))
        let missing = r.focus(t("zzz"))
        #expect(!missing)
    }

    @Test func cycleTabWraps() {
        var r = Room()
        for id in ["a", "b", "c"] { r.add(t(id)) }
        r.cycleTab(by: 1)
        #expect(r.focusedPane?.current == t("a"))
        r.cycleTab(by: -1)
        #expect(r.focusedPane?.current == t("c"))
    }

    @Test func setRatioClamps() {
        var r = Room()
        r.add(t("a"))
        r.split(t("b"), beside: pane(r, t("a")), edge: .right)
        guard case let .split(id, _, _, _, _) = r.root else { Issue.record("split yok"); return }
        r.setRatio(id, 0.97)
        if case let .split(_, _, ratio, _, _) = r.root { #expect(ratio == 0.9) }
        r.setRatio(id, 0.3)
        if case let .split(_, _, ratio, _, _) = r.root { #expect(ratio == 0.3) }
    }

    @Test func pruneRemovesDeadTerminals() {
        var r = Room()
        r.add(t("a"))
        r.add(.markdown("/p/README.md"))
        r.split(t("b"), beside: pane(r, t("a")), edge: .right)
        r.prune(liveTerminals: ["b"])
        #expect(shape(r) == "(h [/p/README.md] | [b])")
    }

    @Test func legacyColumnsDecodeAsHorizontalSplits() throws {
        let old = #"""
        {"rooms":{"/p/x":{"focusedPane":1,"panes":[
          {"selected":0,"tabs":[{"terminal":{"_0":"a"}}],"width":0.5},
          {"selected":1,"tabs":[{"terminal":{"_0":"b"}},{"terminal":{"_0":"c"}}],"width":0.5}]}},
         "pinned":["/p/y"]}
        """#
        let s = try JSONDecoder().decode(RoomStore.self, from: Data(old.utf8))
        let r = try #require(s.rooms["/p/x"])
        #expect(shape(r) == "(h [a] | [b,c*])")
        #expect(r.focusedPaneID == pane(r, t("c")))
        #expect(s.pinned == ["/p/y"])
    }

    @Test func storeRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rooms-\(UUID()).json")
        #expect(RoomStore.load(from: url) == RoomStore())
        var s = RoomStore()
        var r = Room()
        r.add(t("a"))
        r.split(t("b"), beside: pane(r, t("a")), edge: .bottom)
        s.rooms["/p/erp"] = r
        s.pinned = ["/p/x"]
        try s.save(to: url)
        #expect(RoomStore.load(from: url) == s)
    }

    @Test func gitTabSurvivesPruneAndRoundTrips() throws {
        var r = Room()
        r.add(.git("/p/x"))
        r.add(t("a"))
        r.prune(liveTerminals: [])
        #expect(shape(r) == "[git:/p/x]")
        let back = try JSONDecoder().decode(Room.self, from: JSONEncoder().encode(r))
        #expect(back == r)
    }
}
