import AppKit

/// Marks what this running Clipbara puts on the clipboard, so the clipboard
/// monitor can tell its own writes from the user's copies by content rather
/// than by timing. A timing-based skip swallowed a copy the user made between
/// two polls.
enum OwnPasteboardWrite {
    /// The marker type. Unique per launch: another Clipbara (the Dev build, or
    /// another Mac over Universal Clipboard) still records what this one writes.
    nonisolated static let type = NSPasteboard.PasteboardType(
        "com.minsang.PasteClip.own." + UUID().uuidString
    )

    /// Tags the clipboard's current contents as written by this Clipbara.
    /// Call after the write is complete, so the tag can't reorder its items.
    /// - Parameter pasteboard: the pasteboard just written to
    @MainActor
    static func mark(_ pasteboard: NSPasteboard) {
        pasteboard.setData(Data(), forType: type)
    }

    /// Whether the clipboard's current contents came from this Clipbara.
    /// Reading the types never asks a data provider for promised data.
    /// - Parameter pasteboard: the pasteboard to check
    @MainActor
    static func isOwn(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(type) == true
    }
}
