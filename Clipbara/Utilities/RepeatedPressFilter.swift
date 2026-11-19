import Foundation

/// Counts repeated reports of a single global shortcut press only once while a menu tracks.
struct RepeatedPressFilter {
    /// KeyboardShortcuts can report a press through two monitors a few milliseconds apart.
    static let interval: Duration = .milliseconds(100)
    /// Measure from the last accepted event so duplicate reports never extend the window.
    private var lastAccepted: ContinuousClock.Instant?

    /// Returns whether the handler should act on this report.
    /// - Parameter now: The monotonic time at which the key press was reported.
    mutating func accept(at now: ContinuousClock.Instant = .now) -> Bool {
        if let lastAccepted, now - lastAccepted < Self.interval {
            return false
        }
        lastAccepted = now
        return true
    }
}
