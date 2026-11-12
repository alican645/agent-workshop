import CoreGraphics
import Testing
@testable import AjanTakipCore

@Suite struct PanelGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func growsDownKeepingTopLeft() {
        let r = PanelGeometry.fitted(current: CGRect(x: 100, y: 700, width: 100, height: 28),
                                     size: CGSize(width: 200, height: 128), visible: screen)
        #expect(r == CGRect(x: 100, y: 600, width: 200, height: 128))
    }

    @Test func shiftsLeftWhenOverflowingRight() {
        let r = PanelGeometry.fitted(current: CGRect(x: 864, y: 756, width: 120, height: 28),
                                     size: CGSize(width: 350, height: 200), visible: screen)
        #expect(r.maxX == 1000)
        #expect(r.maxY == 784)
    }

    @Test func shiftsUpWhenOverflowingBottom() {
        let r = PanelGeometry.fitted(current: CGRect(x: 100, y: 10, width: 100, height: 28),
                                     size: CGSize(width: 100, height: 300), visible: screen)
        #expect(r.minY == 0)
        #expect(r.height == 300)
    }
}

@Suite struct PanelSnapTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func nearestEdgeByCenter() {
        #expect(PanelGeometry.nearestEdge(of: CGRect(x: 300, y: 400, width: 100, height: 28), in: screen) == .left)
        #expect(PanelGeometry.nearestEdge(of: CGRect(x: 600, y: 400, width: 100, height: 28), in: screen) == .right)
    }

    @Test func snapKeepsVerticalAndHugsEdge() {
        let f = CGRect(x: 420, y: 400, width: 100, height: 28)
        #expect(PanelGeometry.snapped(f, to: .left, in: screen) == CGRect(x: 8, y: 400, width: 100, height: 28))
        #expect(PanelGeometry.snapped(f, to: .right, in: screen) == CGRect(x: 892, y: 400, width: 100, height: 28))
    }

    @Test func snapClampsVertically() {
        let f = CGRect(x: 420, y: 790, width: 100, height: 28)
        #expect(PanelGeometry.snapped(f, to: .left, in: screen).maxY == 800)
    }

    @Test func rightEdgeGrowsLeftward() {
        let r = PanelGeometry.fitted(current: CGRect(x: 892, y: 700, width: 100, height: 28),
                                     size: CGSize(width: 350, height: 128), visible: screen, edge: .right)
        #expect(r == CGRect(x: 642, y: 600, width: 350, height: 128))
    }

    @Test func leftEdgeGrowsRightward() {
        let r = PanelGeometry.fitted(current: CGRect(x: 8, y: 700, width: 100, height: 28),
                                     size: CGSize(width: 350, height: 128), visible: screen, edge: .left)
        #expect(r == CGRect(x: 8, y: 600, width: 350, height: 128))
    }
}
