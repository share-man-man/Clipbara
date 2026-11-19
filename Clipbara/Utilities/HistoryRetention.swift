import Foundation
import SwiftData

/// How long unpinned clips stay in history (Settings > General > Keep History For).
/// Works alongside the History Limit: a clip is removed when it falls outside either.
/// The raw value is the number of days; 0 keeps clips forever.
enum HistoryRetention: Int, CaseIterable, Identifiable, Sendable {
    case forever = 0
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case year = 365

    /// UserDefaults key holding the raw value (days).
    nonisolated static let defaultsKey = "historyRetentionDays"
    /// Used when nothing is stored, so existing installs keep every clip as before.
    nonisolated static let defaultValue: HistoryRetention = .forever

    var id: Int { rawValue }

    /// The stored setting; an unknown stored value falls back to the default.
    static var current: HistoryRetention {
        HistoryRetention(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? defaultValue
    }

    /// Clips copied before this moment are expired.
    /// - Parameters:
    ///   - now: The moment to measure from.
    ///   - calendar: The calendar used to step back by whole days.
    /// - Returns: The cutoff date, or nil when clips are kept forever.
    func cutoff(from now: Date, calendar: Calendar = .current) -> Date? {
        guard self != .forever else { return nil }
        return calendar.date(byAdding: .day, value: -rawValue, to: now)
    }

    /// The name shown in the Settings picker.
    var displayName: String {
        switch self {
        case .forever: String(localized: "Forever")
        case .day: String(localized: "1 Day")
        case .week: String(localized: "1 Week")
        case .month: String(localized: "1 Month")
        case .threeMonths: String(localized: "3 Months")
        case .year: String(localized: "1 Year")
        }
    }

    /// Selects the oldest eligible clips outside either limit without changing the store.
    /// - Parameters:
    ///   - context: The history and pinboard entries to inspect.
    ///   - limit: Maximum number of unpinned, off-board clips to keep; zero has no count limit.
    ///   - now: Date used to preview or enforce the selected age limit.
    @MainActor
    func itemsToRemove(in context: ModelContext, limit: Int, now: Date = .now) throws -> [ClipboardItem] {
        /// All clips without the explicit pin flag, including possible legacy pinboard members.
        var unpinned = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.copiedAt)]
        )
        /// Upper bound on the count overflow before checking actual board membership.
        let excess = limit > 0 ? max(0, try context.fetchCount(unpinned) - limit) : 0
        /// Clips outside the chosen time window, before checking membership.
        let expired: [ClipboardItem]
        if let cutoff = cutoff(from: now) {
            expired = try context.fetch(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { !$0.isPinned && $0.copiedAt < cutoff }
            ))
        } else {
            expired = []
        }
        guard excess > 0 || !expired.isEmpty else { return [] }

        // A board member can lack the pin flag in existing or imported databases.
        // If this fetch fails, propagate the error before making any deletions.
        let entries = try context.fetch(FetchDescriptor<PinboardEntry>(
            predicate: #Predicate { $0.clipboardItem?.isPinned == false }
        ))
        /// Count a clip only once, even when it belongs to multiple boards.
        let protectedIDs = Set(entries.compactMap { $0.clipboardItem?.id })
        /// Eligible clips already covered by the age limit.
        let expiredOffBoard = expired.filter { !protectedIDs.contains($0.id) }
        /// Remaining count overflow after excluding every protected clip from the quota.
        let overflow = excess - protectedIDs.count
        guard overflow > expiredOffBoard.count else { return expiredOffBoard }

        // Both policies remove the oldest clips. Here the count limit includes
        // every expired clip. Fetch enough to skip even the oldest board members.
        unpinned.fetchLimit = excess
        /// Oldest candidates, including any protected board entries that fall in the prefix.
        let oldest = try context.fetch(unpinned)
        return Array(oldest.lazy.filter { !protectedIDs.contains($0.id) }.prefix(overflow))
    }

    /// Applies the same selection used by the retention preview.
    /// - Parameters:
    ///   - context: The history store to update.
    ///   - limit: Maximum number of eligible clips to keep, or zero for unlimited.
    ///   - now: Date used to compute the expiration cutoff.
    @MainActor
    func prune(in context: ModelContext, limit: Int, now: Date = .now) throws {
        try Self.delete(itemsToRemove(in: context, limit: limit, now: now), in: context)
    }

    /// Manual clearing keeps actual pinboard members, as the history panel always has.
    /// - Parameters:
    ///   - items: History from a query or a fresh fetch.
    ///   - entries: Current pinboard memberships in the same store.
    @MainActor
    static func clearableItems(_ items: [ClipboardItem], entries: [PinboardEntry]) -> [ClipboardItem] {
        /// Items that must remain available from their pinboards.
        let onBoards = Set(entries.compactMap { $0.clipboardItem?.id })
        return items.filter { !onBoards.contains($0.id) }
    }

    /// Loads the current selection for manual clearing. A failed fetch aborts the operation.
    /// - Parameter context: The history and pinboards for the active window.
    @MainActor
    static func clearableItems(in context: ModelContext) throws -> [ClipboardItem] {
        /// Read every membership before assembling a destructive selection.
        let entries = try context.fetch(FetchDescriptor<PinboardEntry>())
        /// Clips in the same context as those memberships.
        let history = try context.fetch(FetchDescriptor<ClipboardItem>())
        return clearableItems(history, entries: entries)
    }

    /// Rechecks membership at confirmation and leaves newly captured clips alone.
    /// - Parameters:
    ///   - ids: Snapshot of the clips included in the displayed count.
    ///   - context: The history store to clear.
    @MainActor
    static func clear(_ ids: Set<UUID>, in context: ModelContext) throws {
        try delete(clearableItems(in: context).filter { ids.contains($0.id) }, in: context)
    }

    /// Saves all selected deletions together after every protection check succeeds.
    /// - Parameters:
    ///   - items: Eligible history clips.
    ///   - context: The clips' model context.
    @MainActor
    private static func delete(_ items: [ClipboardItem], in context: ModelContext) throws {
        guard !items.isEmpty else { return }
        // The monitor and settings share this context. Preserve other edits before
        // starting so a failed deletion can be rolled back independently.
        if context.hasChanges { try context.save() }
        for item in items { context.delete(item) }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
