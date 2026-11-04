import XCTest

final class PointerDragTests: XCTestCase {
    /// Where the press starts in these tests.
    private let start = CGPoint(x: 100, y: 100)

    func testAPressThatBarelyMovesIsNotADrag() {
        XCTAssertFalse(PointerDrag.hasStarted(from: start, to: start))
        XCTAssertFalse(PointerDrag.hasStarted(from: start, to: CGPoint(x: 102, y: 102)))
    }

    func testMovingPastTheThresholdIsADrag() {
        XCTAssertTrue(PointerDrag.hasStarted(from: start, to: CGPoint(x: 100, y: 110)))
    }
}
