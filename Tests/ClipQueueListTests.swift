import XCTest

final class ClipQueueListTests: XCTestCase {
    private func queue(_ items: [String], newestFirst: Bool = false) -> ClipQueueList<String> {
        var queue = ClipQueueList<String>()
        queue.pastesNewestFirst = newestFirst
        items.forEach { queue.append($0) }
        return queue
    }

    func testPastesInCopyOrderByDefault() {
        var list = queue(["a", "b", "c"])
        XCTAssertEqual(list.next?.item, "a")
        XCTAssertEqual(list.consumeNext()?.item, "a")
        XCTAssertEqual(list.consumeNext()?.item, "b")
        XCTAssertEqual(list.next?.item, "c")
    }

    func testNewestFirstPastesFromTheEnd() {
        var list = queue(["a", "b", "c"], newestFirst: true)
        XCTAssertEqual(list.pasteOrder.map(\.item), ["c", "b", "a"])
        XCTAssertEqual(list.consumeNext()?.item, "c")
        XCTAssertEqual(list.next?.item, "b")
    }

    func testFlippingTheOrderChangesTheNextItem() {
        var list = queue(["a", "b"])
        list.pastesNewestFirst = true
        XCTAssertEqual(list.next?.item, "b")
        list.pastesNewestFirst = false
        XCTAssertEqual(list.next?.item, "a")
    }

    func testTheSameContentCanBeQueuedTwice() {
        let list = queue(["a", "a"])
        XCTAssertEqual(list.count, 2)
        XCTAssertNotEqual(list.entries[0].id, list.entries[1].id)
    }

    func testRemovingAnEntryKeepsTheRestInOrder() {
        var list = queue(["a", "b", "c"])
        list.remove(id: list.entries[1].id)
        XCTAssertEqual(list.pasteOrder.map(\.item), ["a", "c"])
    }

    func testMovingDownTakesTheTargetsPlace() {
        var list = queue(["a", "b", "c"])
        list.move(id: list.entries[0].id, to: list.entries[2].id)
        XCTAssertEqual(list.pasteOrder.map(\.item), ["b", "c", "a"])
        XCTAssertEqual(list.next?.item, "b")
    }

    func testMovingUpTakesTheTargetsPlace() {
        var list = queue(["a", "b", "c"])
        list.move(id: list.entries[2].id, to: list.entries[0].id)
        XCTAssertEqual(list.pasteOrder.map(\.item), ["c", "a", "b"])
    }

    func testMovingWorksInNewestFirstPasteOrder() {
        // Paste order is c, b, a; dragging a to the top makes it next.
        var list = queue(["a", "b", "c"], newestFirst: true)
        list.move(id: list.entries[0].id, to: list.entries[2].id)
        XCTAssertEqual(list.pasteOrder.map(\.item), ["a", "c", "b"])
        XCTAssertEqual(list.consumeNext()?.item, "a")
        XCTAssertEqual(list.consumeNext()?.item, "c")
    }

    func testMovingOntoItselfChangesNothing() {
        var list = queue(["a", "b"])
        list.move(id: list.entries[0].id, to: list.entries[0].id)
        XCTAssertEqual(list.pasteOrder.map(\.item), ["a", "b"])
    }

    func testConsumingAnEmptyQueueReturnsNothing() {
        var list = queue([])
        XCTAssertNil(list.consumeNext())
        XCTAssertNil(list.next)
        XCTAssertTrue(list.isEmpty)
    }

    // MARK: - Pasted entries

    func testPastingKeepsTheEntryMostRecentFirst() {
        var list = queue(["a", "b", "c"])
        list.consumeNext()
        list.consumeNext()
        XCTAssertEqual(list.pasted.map(\.item), ["b", "a"])
        XCTAssertEqual(list.pasteOrder.map(\.item), ["c"])
    }

    func testPastedEntriesAreCappedAtTheLimit() {
        var list = queue(["a", "b", "c"])
        list.pastedLimit = 2
        list.consumeNext()
        list.consumeNext()
        list.consumeNext()
        XCTAssertEqual(list.pasted.map(\.item), ["c", "b"])
    }

    func testRestoringPutsTheEntryNext() {
        var list = queue(["a", "b", "c"])
        list.consumeNext()
        let pastedID = list.pasted[0].id
        list.restore(id: pastedID)
        XCTAssertEqual(list.next?.id, pastedID)
        XCTAssertEqual(list.pasteOrder.map(\.item), ["a", "b", "c"])
        XCTAssertTrue(list.pasted.isEmpty)
    }

    func testRestoringPutsTheEntryNextWhenPastingNewestFirst() {
        var list = queue(["a", "b", "c"], newestFirst: true)
        list.consumeNext()
        list.restore(id: list.pasted[0].id)
        XCTAssertEqual(list.pasteOrder.map(\.item), ["c", "b", "a"])
    }

    func testRemovingAnEntryDoesNotCountAsPasted() {
        var list = queue(["a", "b"])
        list.remove(id: list.entries[0].id)
        XCTAssertTrue(list.pasted.isEmpty)
    }

    func testRemovingAllForgetsThePastedEntries() {
        var list = queue(["a", "b"])
        list.consumeNext()
        list.removeAll()
        XCTAssertTrue(list.pasted.isEmpty)
        XCTAssertTrue(list.isEmpty)
    }
}
