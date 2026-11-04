import AppKit
import SwiftData
import CryptoKit

@MainActor
@Observable
final class ClipboardMonitor {
    private var timer: Timer?
    /// Removes expired clips while no copies happen, since time-based retention
    /// can expire clips without anything new arriving.
    private var cleanupTimer: Timer?
    private var lastChangeCount: Int = 0
    private let classifier = ContentTypeClassifier()
    private var modelContext: ModelContext?
    private var excludedBundleIds: Set<String> = []

    /// How often to check the clipboard. macOS sends no notice when another app
    /// copies, so polling is the only way; a check reads one integer, so a short
    /// interval costs next to nothing and keeps copies from feeling late.
    nonisolated static let pollInterval: TimeInterval = 0.1
    /// How often expired clips are swept while the app is idle.
    nonisolated static let cleanupInterval: TimeInterval = 60 * 60
    /// UserDefaults key for the History Limit (number of unpinned clips, 0 = unlimited).
    nonisolated static let historyLimitDefaultsKey = "historyLimit"
    /// History Limit used when nothing is stored.
    nonisolated static let defaultHistoryLimit = 500

    var isMonitoring: Bool = false
    /// Called with every copy Clipbara records, including one that matched a
    /// clip copied moments earlier. The Clip Queue collects from here.
    @ObservationIgnored var onCapture: ((ClipboardItem) -> Void)?
    var latestItems: [ClipboardItem] = []
    var historyLimit: Int {
        get { UserDefaults.standard.object(forKey: Self.historyLimitDefaultsKey) as? Int ?? Self.defaultHistoryLimit }
        set { UserDefaults.standard.set(newValue, forKey: Self.historyLimitDefaultsKey) }
    }

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        lastChangeCount = NSPasteboard.general.changeCount
        loadExcludedApps()
        isMonitoring = true

        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        // Let the system batch wakeups a little; the delay stays well under what a person notices.
        timer?.tolerance = Self.pollInterval / 5

        // Drop clips that expired while the app was not running, then keep sweeping hourly.
        cleanupOldItems()
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: Self.cleanupInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupOldItems()
            }
        }
        cleanupTimer?.tolerance = Self.cleanupInterval / 10
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        isMonitoring = false
    }

    func toggle() {
        if isMonitoring { stop() } else if let ctx = modelContext { start(modelContext: ctx) }
    }

    func refreshLatestItems() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = 5
        latestItems = (try? modelContext.fetch(limited)) ?? []
    }

    /// The newest clip in history, the first one the history list shows.
    func newestItem() -> ClipboardItem? {
        guard let modelContext else { return nil }
        /// Newest first, just the one.
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Our own write (a paste, or the Clip Queue lining up its next item).
        // Checked by content: a user copy that lands between two polls is
        // still recorded.
        if OwnPasteboardWrite.isOwn(pasteboard) {
            return
        }

        // Check excluded apps
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = frontApp.bundleIdentifier,
           excludedBundleIds.contains(bundleId) {
            return
        }

        guard let content = classifier.classify(pasteboard) else { return }

        let hash = SHA256.hash(data: content.rawData)
            .compactMap { String(format: "%02x", $0) }
            .joined()

        // Duplicate check within last 10 seconds
        if let recent = recentDuplicate(hash: hash) {
            onCapture?(recent)
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication
        let item = ClipboardItem(
            contentType: content.contentType,
            rawData: content.rawData,
            textContent: content.textContent,
            sourceAppName: sourceApp?.localizedName,
            sourceAppBundleId: sourceApp?.bundleIdentifier,
            contentHash: hash
        )

        // Generate thumbnail for images
        if content.contentType == .image {
            item.thumbnailData = generateThumbnail(from: content.rawData)
        }

        modelContext?.insert(item)
        try? modelContext?.save()
        cleanupOldItems()
        refreshLatestItems()
        SoundFeedback.playCopy()
        onCapture?(item)
    }

    /// Applies the History Limit and Keep History For settings now, for example
    /// right after either one changes in Settings.
    func applyHistoryRules() {
        cleanupOldItems()
        refreshLatestItems()
    }

    /// Deletes unpinned clips older than the retention period, then the oldest
    /// unpinned clips beyond the History Limit. Pinned clips are always kept.
    private func cleanupOldItems() {
        guard let modelContext else { return }

        // 1. Time-based retention: everything unpinned copied before the cutoff.
        if let cutoff = HistoryRetention.current.cutoff(from: Date()) {
            /// Unpinned clips copied before the cutoff.
            let expiredDescriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { !$0.isPinned && $0.copiedAt < cutoff }
            )
            if let expired = try? modelContext.fetch(expiredDescriptor) {
                delete(expired, in: modelContext)
            }
        }

        // 2. Count-based limit: the oldest unpinned clips beyond the limit.
        /// Snapshot of the limit so both reads below agree.
        let limit = historyLimit
        guard limit > 0 else { return }

        /// Counts the unpinned clips.
        let countDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned }
        )
        /// Number of unpinned clips in history.
        let unpinnedCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0

        guard unpinnedCount > limit else { return }

        /// Oldest unpinned clips first, just the ones over the limit.
        var fetchDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.copiedAt, order: .forward)]
        )
        fetchDescriptor.fetchLimit = unpinnedCount - limit

        guard let itemsToDelete = try? modelContext.fetch(fetchDescriptor) else { return }
        delete(itemsToDelete, in: modelContext)
    }

    /// Deletes clips along with any pinboard entries that point at them, then saves.
    /// - Parameters:
    ///   - items: The clips to delete.
    ///   - modelContext: The context the clips live in.
    private func delete(_ items: [ClipboardItem], in modelContext: ModelContext) {
        guard !items.isEmpty else { return }
        for item in items {
            /// The clip's id, captured for the predicate.
            let itemId = item.id
            /// Pinboard entries that reference this clip.
            let entryDescriptor = FetchDescriptor<PinboardEntry>(
                predicate: #Predicate { $0.clipboardItem?.id == itemId }
            )
            if let entries = try? modelContext.fetch(entryDescriptor) {
                for entry in entries {
                    modelContext.delete(entry)
                }
            }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    private func recentDuplicate(hash: String) -> ClipboardItem? {
        guard let modelContext else { return nil }
        let tenSecondsAgo = Date().addingTimeInterval(-10)
        let predicate = #Predicate<ClipboardItem> { item in
            item.contentHash == hash && item.copiedAt > tenSecondsAgo
        }
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func generateThumbnail(from data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let maxSize: CGFloat = 320
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height, 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        thumbnail.unlockFocus()

        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }

    func loadExcludedApps() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ExcludedApp>()
        let apps = (try? modelContext.fetch(descriptor)) ?? []
        excludedBundleIds = Set(apps.map(\.bundleId))
    }
}
