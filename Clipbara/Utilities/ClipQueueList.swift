import Foundation

/// The ordered contents of a Clip Queue, kept free of AppKit so the ordering
/// rules can be tested on their own.
///
/// Items are stored in the order they were copied. By default the oldest is
/// pasted first; `pastesNewestFirst` flips that.
struct ClipQueueList<Item> {
    struct Entry: Identifiable {
        let id: UUID
        let item: Item
    }

    private(set) var entries: [Entry] = []
    var pastesNewestFirst = false
    /// Entries already pasted, the most recent first, kept so a paste that went
    /// wrong or was skipped can be put back.
    private(set) var pasted: [Entry] = []
    /// How many pasted entries `pasted` keeps.
    var pastedLimit = 5

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    /// The entry the next ⌘V will paste.
    var next: Entry? {
        pastesNewestFirst ? entries.last : entries.first
    }

    /// Entries in the order they will be pasted.
    var pasteOrder: [Entry] {
        pastesNewestFirst ? entries.reversed() : entries
    }

    /// Adds a copy. The same content copied twice is two entries, since the
    /// user may want to paste it twice.
    @discardableResult
    mutating func append(_ item: Item) -> Entry {
        let entry = Entry(id: UUID(), item: item)
        entries.append(entry)
        return entry
    }

    /// Removes and returns the entry that was just pasted, keeping it at the
    /// front of `pasted`.
    @discardableResult
    mutating func consumeNext() -> Entry? {
        guard !entries.isEmpty else { return nil }
        /// The entry just pasted.
        let entry = pastesNewestFirst ? entries.removeLast() : entries.removeFirst()
        pasted.insert(entry, at: 0)
        if pasted.count > pastedLimit { pasted.removeLast(pasted.count - pastedLimit) }
        return entry
    }

    /// Puts a pasted entry back in the queue as the next one to paste.
    /// - Parameter id: the entry, from `pasted`
    mutating func restore(id: UUID) {
        guard let index = pasted.firstIndex(where: { $0.id == id }) else { return }
        /// The entry going back in.
        let entry = pasted.remove(at: index)
        // Next in paste order: the end when pasting newest first, else the start.
        if pastesNewestFirst {
            entries.append(entry)
        } else {
            entries.insert(entry, at: 0)
        }
    }

    /// Moves an entry into another's place in paste order, shifting the ones
    /// between, as a drag in the queue window does.
    /// - Parameters:
    ///   - id: the entry being moved
    ///   - targetID: the entry whose place it takes
    mutating func move(id: UUID, to targetID: UUID) {
        /// Entries in paste order, rearranged here and stored back.
        var order = pasteOrder
        guard let from = order.firstIndex(where: { $0.id == id }),
              let to = order.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        order.insert(order.remove(at: from), at: to)
        entries = pastesNewestFirst ? order.reversed() : order
    }

    mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Empties the queue and forgets what it pasted.
    mutating func removeAll() {
        entries.removeAll()
        pasted.removeAll()
    }
}
