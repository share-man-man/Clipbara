import XCTest

final class RepeatedPressFilterTests: XCTestCase {
    /// One press can be reported several times while a menu is open.
    func testMenuBurstCountsAsOnePress() {
        var filter = RepeatedPressFilter()
        /// The original press, before the duplicate callbacks arrive.
        let start = ContinuousClock.now
        XCTAssertTrue(filter.accept(at: start))
        for _ in 0..<3 {
            XCTAssertFalse(filter.accept(at: start.advanced(by: .milliseconds(51))))
        }
    }

    /// A late duplicate cannot suppress a distinct press at the boundary.
    func testRejectedPressDoesNotExtendTheWindow() {
        var filter = RepeatedPressFilter()
        /// The first accepted report.
        let start = ContinuousClock.now
        XCTAssertTrue(filter.accept(at: start))
        XCTAssertFalse(filter.accept(at: start.advanced(by: .milliseconds(99))))
        XCTAssertTrue(filter.accept(at: start.advanced(by: RepeatedPressFilter.interval)))
    }
}
