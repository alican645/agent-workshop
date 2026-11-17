import Foundation
import Testing
@testable import AjanTakipCore

@Suite struct DeskTests {
    private func t(_ id: String) -> RoomTab { .terminal(id) }

    @Test func openAddsCascadedWindowsOnTop() {
        var d = Desk()
        let a = d.open(t("a"), root: "/p/x")
        let b = d.open(t("b"), root: "/p/x")
        #expect(d.windows.map(\.id) == [a, b])
        #expect(d.front?.id == b)
        let fa = d.windows[0].frame, fb = d.windows[1].frame
        #expect(fb.x > fa.x && fb.y > fa.y && fb.w == fa.w)
    }

    @Test func openExistingTabRaisesAndRestores() {
        var d = Desk()
        let a = d.open(t("a"), root: "/p/x")
        _ = d.open(t("b"), root: "/p/x")
        d.minimize(a)
        #expect(d.window(a)?.minimized == true && d.front?.tab == t("b"))
        let again = d.open(t("a"), root: "/p/x")
        #expect(again == a && d.windows.count == 2)
        #expect(d.front?.id == a && d.window(a)?.minimized == false)
    }

    @Test func frontSkipsMinimized() {
        var d = Desk()
        let a = d.open(t("a"), root: "/p/x")
        let b = d.open(t("b"), root: "/p/x")
        d.minimize(b)
        #expect(d.front?.id == a)
        d.minimize(a)
        #expect(d.front == nil)
    }

    @Test func raiseMovesToTop() {
        var d = Desk()
        let a = d.open(t("a"), root: "/p/x")
        _ = d.open(t("b"), root: "/p/y")
        d.raise(a)
        #expect(d.windows.last?.id == a)
    }

    @Test func raiseAllBringsProjectWindowsUpKeepingOrder() {
        var d = Desk()
        let a = d.open(t("a"), root: "/p/x")
        let b = d.open(t("b"), root: "/p/x")
        let c = d.open(t("c"), root: "/p/y")
        d.minimize(a)
        let raised = d.raiseAll(root: "/p/x")
        #expect(raised)
        #expect(d.windows.map(\.id) == [c, a, b])
        #expect(d.window(a)?.minimized == false)
        let none = d.raiseAll(root: "/p/none")
        #expect(!none)
    }

    @Test func setFrameClampsInsideAndToMinimumSize() {
        var d = Desk()
        let a = d.open(t("a"), root: "/p/x")
        d.setFrame(a, FloatRect(x: 0.9, y: -0.2, w: 0.5, h: 0.01))
        let f = d.window(a)!.frame
        #expect(f.w == 0.5 && f.h == Desk.minSize)
        #expect(f.x == 0.5 && f.y == 0)
        d.setFrame(a, FloatRect(x: -1, y: 0.5, w: 3, h: 0.3))
        #expect(d.window(a)!.frame == FloatRect(x: 0, y: 0.5, w: 1, h: 0.3))
    }

    @Test func setFrameEndsMaximize() {
        var d = Desk()
        let a = d.open(t("a"), root: "/p/x")
        d.toggleMaximize(a)
        #expect(d.window(a)?.maximized == true)
        d.setFrame(a, FloatRect(x: 0.1, y: 0.1, w: 0.4, h: 0.4))
        #expect(d.window(a)?.maximized == false)
        d.toggleMaximize(a)
        d.toggleMaximize(a)
        #expect(d.window(a)?.frame == FloatRect(x: 0.1, y: 0.1, w: 0.4, h: 0.4))
    }

    @Test func removeTabAndPrune() {
        var d = Desk()
        _ = d.open(t("a"), root: "/p/x")
        _ = d.open(.git("/p/x"), root: "/p/x")
        _ = d.open(t("b"), root: "/p/x")
        d.remove(t("b"))
        #expect(d.windows.map(\.tab) == [t("a"), .git("/p/x")])
        d.prune(liveTerminals: [])
        #expect(d.windows.map(\.tab) == [.git("/p/x")])
    }

    @Test func cycleFocusesNextVisible() {
        var d = Desk()
        let a = d.open(t("a"), root: "/p/x")
        let b = d.open(t("b"), root: "/p/x")
        let c = d.open(t("c"), root: "/p/x")
        d.minimize(b)
        d.cycle(by: 1)
        #expect(d.front?.id == a)
        d.cycle(by: 1)
        #expect(d.front?.id == c)
    }

    @Test func snapZones() {
        let size = (w: 1000.0, h: 600.0)
        #expect(Desk.snap(pointer: (5, 300), in: size) == FloatRect(x: 0, y: 0, w: 0.5, h: 1))
        #expect(Desk.snap(pointer: (996, 300), in: size) == FloatRect(x: 0.5, y: 0, w: 0.5, h: 1))
        #expect(Desk.snap(pointer: (500, 3), in: size) == FloatRect(x: 0, y: 0, w: 1, h: 1))
        #expect(Desk.snap(pointer: (4, 4), in: size) == FloatRect(x: 0, y: 0, w: 0.5, h: 0.5))
        #expect(Desk.snap(pointer: (995, 595), in: size) == FloatRect(x: 0.5, y: 0.5, w: 0.5, h: 0.5))
        #expect(Desk.snap(pointer: (500, 300), in: size) == nil)
    }

    @Test func migratesRoomsCascaded() {
        var s = RoomStore()
        var r = Room()
        r.add(t("a"))
        r.split(t("b"), beside: r.panes[0].id, edge: .right)
        s.rooms["/p/x"] = r
        s.pinned = ["/p/y"]
        let d = Desk(migrating: s)
        #expect(d.windows.map(\.tab) == [t("a"), t("b")] && d.windows.allSatisfy { $0.root == "/p/x" })
        #expect(d.pinned == ["/p/y"])
    }

    @Test func storeRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("desk-\(UUID()).json")
        #expect(Desk.load(from: url) == nil)
        var d = Desk()
        let a = d.open(t("a"), root: "/p/x")
        d.toggleMaximize(a)
        d.pinned = ["/p/y"]
        try d.save(to: url)
        #expect(Desk.load(from: url) == d)
    }
}
