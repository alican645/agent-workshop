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
