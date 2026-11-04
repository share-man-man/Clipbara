import XCTest

final class HistoryRetentionTests: XCTestCase {
    /// A fixed calendar so the tests don't depend on the machine's time zone.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 2026-03-31 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_774_958_400)

    func testForeverHasNoCutoff() {
        XCTAssertNil(HistoryRetention.forever.cutoff(from: now, calendar: calendar))
    }

    func testCutoffStepsBackByWholeDays() {
        for retention in HistoryRetention.allCases where retention != .forever {
            /// Expected cutoff, counted in days on the same calendar.
            let expected = calendar.date(byAdding: .day, value: -retention.rawValue, to: now)
            XCTAssertEqual(retention.cutoff(from: now, calendar: calendar), expected)
        }
    }

    func testOneDayCutoffIsTwentyFourHoursEarlierInUTC() {
        XCTAssertEqual(HistoryRetention.day.cutoff(from: now, calendar: calendar), now.addingTimeInterval(-86_400))
    }

    func testUnknownStoredValueFallsBackToDefault() {
        XCTAssertNil(HistoryRetention(rawValue: 2))
        XCTAssertEqual(HistoryRetention.defaultValue, .forever)
    }
}
