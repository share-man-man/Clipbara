import XCTest

final class ListDragAutoScrollTests: XCTestCase {
    func testNoScrollAwayFromTheEdges() {
        XCTAssertEqual(ListDragAutoScroll.step(fromTop: 100, fromBottom: 100), 0)
    }

    func testScrollsUpNearTheTopFasterCloserToIt() {
        let far = ListDragAutoScroll.step(fromTop: ListDragAutoScroll.edgeZone - 4, fromBottom: 200)
        let near = ListDragAutoScroll.step(fromTop: 2, fromBottom: 200)
        XCTAssertLessThan(far, 0)
        XCTAssertLessThan(near, far)
    }

    func testScrollsDownNearTheBottom() {
        XCTAssertGreaterThan(ListDragAutoScroll.step(fromTop: 200, fromBottom: 2), 0)
    }

    func testPastTheEdgeScrollsAtFullSpeed() {
        XCTAssertEqual(ListDragAutoScroll.step(fromTop: -50, fromBottom: 300), -ListDragAutoScroll.maxStep)
        XCTAssertEqual(ListDragAutoScroll.step(fromTop: 300, fromBottom: -50), ListDragAutoScroll.maxStep)
    }
}
