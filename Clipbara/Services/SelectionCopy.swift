import AppKit
import os.log

/// Starting the Clip Queue with its shortcut presses ⌘C for the user, so the
/// front app's selection becomes the first item without a separate copy.
///
/// It is the user's own ⌘C, nothing more: the app decides what to copy, with all
/// its formats, and the clipboard monitor records it like any other copy. With
/// nothing selected most apps copy nothing; editors such as VS Code copy the
/// current line, as they would for the user.
@MainActor
enum SelectionCopy {
    /// Settings > Shortcuts > Copy Selection When Starting. Missing means on.
    nonisolated static let enabledDefaultsKey = "clipQueueCopiesSelection"
    /// Whether it is on before the user changes the setting.
    nonisolated static let enabledByDefault = true

    /// Whether ⌘C went out, for diagnosing a copy that didn't reach the queue.
    nonisolated private static let logger = Logger(clipbaraCategory: "SelectionCopy")

    /// Whether this build offers it. Posting ⌘C needs Accessibility, which only
    /// the DMG build may use (see `DirectPaste.isAvailable`).
    nonisolated static var isAvailable: Bool { DirectPaste.isAvailable }

    static var isEnabled: Bool {
        isAvailable && (UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? enabledByDefault)
    }

    /// Longest wait for the queue shortcut's keys to be let go.
    nonisolated private static let releaseTimeout: Duration = .seconds(1.5)
    /// How often to check whether the keys are up.
    nonisolated private static let releasePollInterval: Duration = .milliseconds(20)

    /// Waits until the queue shortcut's keys are let go, or `releaseTimeout`.
    ///
    /// The shortcut is still held when it fires, and ⌘C posted then did not copy
    /// in Chrome: the held modifiers mix in, even though the posted events carry
    /// only Command.
    /// - Parameter shortcutKey: key code of the queue shortcut, waited on as well
    /// - Returns: whether the keys were let go. False after the timeout, when ⌘C
    ///   must not be sent: with ⇧ still down it would be ⌘⇧C, which opens
    ///   Chrome's developer tools.
    static func waitForRelease(of shortcutKey: CGKeyCode?) async -> Bool {
        /// When to give up waiting.
        let deadline = ContinuousClock.now + releaseTimeout
        while isHoldingKeys(shortcutKey) {
            guard ContinuousClock.now < deadline else {
                logger.notice("Shortcut still held after the timeout; not sending ⌘C")
                return false
            }
            try? await Task.sleep(for: releasePollInterval)
        }
        return true
    }

    /// Sends ⌘C to the front app. Call once the shortcut is let go.
    static func copy() {
        /// Whether the ⌘C events were posted.
        let sent = DirectPaste.sendCopyShortcut()
        logger.notice("Sent ⌘C: \(sent)")
    }

    /// Whether any modifier, or the shortcut's own key, is still held down.
    /// - Parameter shortcutKey: key code of the queue shortcut
    private static func isHoldingKeys(_ shortcutKey: CGKeyCode?) -> Bool {
        /// Modifiers that would mix into the posted ⌘C.
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        if !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            return true
        }
        if let shortcutKey, CGEventSource.keyState(.combinedSessionState, key: shortcutKey) {
            return true
        }
        return false
    }
}
