import CoreGraphics

/// Tells a click from a drag by how far the pointer moved while the button was down.
enum PointerDrag {
    /// How far the pointer moves from the press before it counts as a drag,
    /// matching the distance AppKit waits for before it starts a row drag.
    static let threshold: CGFloat = 4

    /// Whether the pointer moved far enough from the press to be a drag rather than a click.
    /// - Parameters:
    ///   - start: where the button went down, in screen coordinates
    ///   - current: where the pointer is now, in screen coordinates
    static func hasStarted(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) > threshold
    }
}
