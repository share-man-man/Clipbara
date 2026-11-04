import XCTest

final class ClipQueueWindowGeometryTests: XCTestCase {
    /// A 1000×800 visible screen area, offset like a second display.
    private let screen = CGRect(x: 100, y: 50, width: 1000, height: 800)
    /// The queue window's minimum size in these tests.
    private let minimum = CGSize(width: 240, height: 140)

    // MARK: - ClipQueuePlacement

    func testMeasuresFromTheNearerSide() {
        let left = ClipQueuePlacement(frame: CGRect(x: 120, y: 600, width: 300, height: 200), in: screen)
        XCTAssertEqual(left, ClipQueuePlacement(fromLeft: true, horizontalInset: 20, topInset: 50))

        let right = ClipQueuePlacement(frame: CGRect(x: 780, y: 600, width: 300, height: 200), in: screen)
        XCTAssertEqual(right, ClipQueuePlacement(fromLeft: false, horizontalInset: 20, topInset: 50))
    }

    func testPlacesRelativeToTheTopAndSide() {
        let placement = ClipQueuePlacement(fromLeft: false, horizontalInset: 12, topInset: 12)
        let origin = placement.origin(for: CGSize(width: 300, height: 200), in: screen)
        XCTAssertEqual(origin, CGPoint(x: 1100 - 12 - 300, y: 850 - 12 - 200))
    }

    func testRoundTripsThroughAFrame() {
        let frame = CGRect(x: 400, y: 300, width: 300, height: 200)
        let placement = ClipQueuePlacement(frame: frame, in: screen)
        XCTAssertEqual(placement.origin(for: frame.size, in: screen), frame.origin)
    }

    func testCarriesOverToAScreenOfAnotherSize() {
        // 20 pt from the right and 30 pt from the top, on a smaller screen.
        let placement = ClipQueuePlacement(fromLeft: false, horizontalInset: 20, topInset: 30)
        let small = CGRect(x: 0, y: 0, width: 600, height: 400)
        let origin = placement.origin(for: CGSize(width: 300, height: 100), in: small)
        XCTAssertEqual(origin, CGPoint(x: 280, y: 270))
    }

    func testKeepsTheWindowOnScreen() {
        // Saved far off to the side and below on a bigger screen.
        let placement = ClipQueuePlacement(fromLeft: true, horizontalInset: 900, topInset: 750)
        let origin = placement.origin(for: CGSize(width: 300, height: 200), in: screen)
        XCTAssertEqual(origin, CGPoint(x: 1100 - 300, y: 50))
    }

    // MARK: - ClipQueueWindowSize

    func testRestoringGrowsAnOldSizeToTheMinimum() {
        XCTAssertEqual(
            ClipQueueWindowSize.restored(CGSize(width: 200, height: 400), minimum: minimum),
            CGSize(width: 240, height: 400)
        )
        XCTAssertEqual(ClipQueueWindowSize.restored(CGSize(width: 100, height: 100), minimum: minimum), minimum)
    }

    func testRestoringKeepsALargerSize() {
        let size = CGSize(width: 320, height: 400)
        XCTAssertEqual(ClipQueueWindowSize.restored(size, minimum: minimum), size)
    }

    func testSavedSizeLoadsBack() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ClipQueueWindowGeometryTests"))
        defer { defaults.removePersistentDomain(forName: "ClipQueueWindowGeometryTests") }
        XCTAssertNil(ClipQueueWindowSize.load(minimum: minimum, from: defaults))
        ClipQueueWindowSize.save(CGSize(width: 320, height: 400), to: defaults)
        XCTAssertEqual(ClipQueueWindowSize.load(minimum: minimum, from: defaults), CGSize(width: 320, height: 400))
    }
}
