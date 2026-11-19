import SwiftData
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

@MainActor
final class HistoryPruningTests: XCTestCase {
    /// A fresh in-memory store for every test.
    private var container: ModelContainer!
    /// The history context shared by selection and deletion.
    private var context: ModelContext { container.mainContext }
    /// Shared reference date independent of the day the tests run.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        container = try ModelContainer(
            for: ClipboardItem.self, Pinboard.self, PinboardEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Inserts and saves a history item at a known age.
    /// - Parameters:
    ///   - name: Unique text to identify the clip in assertions.
    ///   - daysAgo: Age measured against the fixed reference date.
    ///   - pinned: Explicit pin flag, independent of any pinboard entries.
    @discardableResult
    private func clip(_ name: String, daysAgo: Int, pinned: Bool = false) throws -> ClipboardItem {
        /// The stored item under test.
        let item = ClipboardItem(contentType: .plainText, rawData: Data(name.utf8), textContent: name, contentHash: name)
        item.copiedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        item.isPinned = pinned
        context.insert(item)
        try context.save()
        return item
    }

    /// Creates board membership without setting the legacy pin flag.
    /// - Parameter item: Clip that must survive through its relationship alone.
    private func addToBoard(_ item: ClipboardItem) throws {
        /// A different board on each call allows testing multiple memberships.
        let board = Pinboard(name: "Board")
        context.insert(board)
        context.insert(PinboardEntry(clipboardItem: item, pinboard: board))
        try context.save()
    }

    /// Returns all remaining stored clip texts.
    private func remaining() throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<ClipboardItem>()).compactMap(\.textContent))
    }

    /// A preview is read-only, uses the same cutoff as pruning, and protects both kinds of pin.
    func testPreviewAndApplyExpiration() throws {
        try clip("expired", daysAgo: 8)
        try clip("on cutoff", daysAgo: 7)
        try clip("explicit pin", daysAgo: 40, pinned: true)
        try addToBoard(clip("on board", daysAgo: 40))

        /// Candidates presented by Settings before it writes the new preference.
        let preview = try HistoryRetention.week.itemsToRemove(in: context, limit: 0, now: now)
        XCTAssertEqual(preview.compactMap(\.textContent), ["expired"])
        XCTAssertEqual(try remaining().count, 4)
        try HistoryRetention.week.prune(in: context, limit: 0, now: now)
        XCTAssertEqual(try remaining(), ["on cutoff", "explicit pin", "on board"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PinboardEntry>()), 1)
    }

    /// A board member doesn't consume quota, even if oldest or on multiple boards.
    func testCountLimitKeepsTheNewestEligibleClips() throws {
        /// This clip could be imported by reference to an existing unpinned local clip.
        let onBoard = try clip("on two boards", daysAgo: 100)
        try addToBoard(onBoard)
        try addToBoard(onBoard)
        try clip("explicit pin", daysAgo: 180, pinned: true)
        try clip("expired", daysAgo: 10)
        try clip("overflow", daysAgo: 4)
        try clip("recent", daysAgo: 2)
        try clip("newest", daysAgo: 1)

        try HistoryRetention.week.prune(in: context, limit: 2, now: now)
        XCTAssertEqual(try remaining(), ["on two boards", "explicit pin", "recent", "newest"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PinboardEntry>()), 2)
        try HistoryRetention.forever.prune(in: context, limit: 2, now: now)
        XCTAssertEqual(try remaining().count, 4)
    }

    /// Manual clear protects board relationships rechecked after confirmation was opened.
    func testManualClearKeepsNewClipsAndNewPinboardMemberships() throws {
        try clip("ordinary", daysAgo: 1)
        try clip("flag without a board", daysAgo: 1, pinned: true)
        try addToBoard(clip("already on board", daysAgo: 2))
        /// This clip becomes protected after it is shown in the confirmation.
        let newlyPinned = try clip("pinned while confirming", daysAgo: 1)
        /// The user approved these three clips, including the one subsequently pinned.
        let preview = Set(try HistoryRetention.clearableItems(in: context).map(\.id))
        XCTAssertEqual(preview.count, 3)
        try addToBoard(newlyPinned)
        try clip("copied while confirming", daysAgo: 0)

        try HistoryRetention.clear(preview, in: context)
        XCTAssertEqual(try remaining(), ["already on board", "pinned while confirming", "copied while confirming"])
    }
}
