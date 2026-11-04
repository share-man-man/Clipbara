import Foundation

/// Where the Clip Queue window sits on its screen: inset from the nearer side and
/// from the top. Kept relative to the screen rather than as a point, so it carries
/// over to whichever screen the queue opens on, of any size. The top stays put
/// because the window grows downward as clips join.
struct ClipQueuePlacement: Codable, Equatable {
    /// Where the user last dragged the window, as JSON.
    nonisolated static let defaultsKey = "clipQueuePlacement"

    /// Whether the window keeps to the left side, else to the right.
    var fromLeft: Bool
    /// Distance from that side of the visible screen area.
    var horizontalInset: CGFloat
    /// Distance from the top of the visible screen area.
    var topInset: CGFloat

    /// - Parameters:
    ///   - fromLeft: keeps to the left side, else to the right
    ///   - horizontalInset: distance from that side
    ///   - topInset: distance from the top
    init(fromLeft: Bool, horizontalInset: CGFloat, topInset: CGFloat) {
        self.fromLeft = fromLeft
        self.horizontalInset = horizontalInset
        self.topInset = topInset
    }

    /// Measures a window frame against its screen, keeping to the nearer side.
    /// - Parameters:
    ///   - frame: the window frame
    ///   - visible: visible area of the window's screen
    init(frame: CGRect, in visible: CGRect) {
        fromLeft = frame.midX < visible.midX
        horizontalInset = fromLeft ? frame.minX - visible.minX : visible.maxX - frame.maxX
        topInset = visible.maxY - frame.maxY
    }

    /// The window origin on a screen, kept fully on it.
    /// - Parameters:
    ///   - size: the window size
    ///   - visible: visible area of the screen to place on
    func origin(for size: CGSize, in visible: CGRect) -> CGPoint {
        /// Left edge before keeping it on screen.
        let x = fromLeft ? visible.minX + horizontalInset : visible.maxX - horizontalInset - size.width
        /// Bottom edge before keeping it on screen.
        let y = visible.maxY - topInset - size.height
        return CGPoint(
            x: min(max(x, visible.minX), visible.maxX - size.width),
            y: min(max(y, visible.minY), visible.maxY - size.height)
        )
    }

    /// The saved placement, or nil before the first drag.
    /// - Parameter defaults: where it is saved
    static func load(from defaults: UserDefaults = .standard) -> ClipQueuePlacement? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ClipQueuePlacement.self, from: data)
    }

    /// Saves the placement for the next time the queue opens.
    /// - Parameter defaults: where to save it
    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// The size the user resized the Clip Queue window to, kept for the next queue.
enum ClipQueueWindowSize {
    /// The size the user last resized the window to, as JSON.
    nonisolated static let defaultsKey = "clipQueueSize"

    /// A saved size, grown to the minimum if it was saved before the minimum was raised.
    /// - Parameters:
    ///   - size: the saved size
    ///   - minimum: the window's minimum size
    static func restored(_ size: CGSize, minimum: CGSize) -> CGSize {
        CGSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
    }

    /// The size the user last picked, or nil if they never resized the window.
    /// - Parameters:
    ///   - minimum: the window's minimum size
    ///   - defaults: where it is saved
    static func load(minimum: CGSize, from defaults: UserDefaults = .standard) -> CGSize? {
        guard let data = defaults.data(forKey: defaultsKey),
              let size = try? JSONDecoder().decode(CGSize.self, from: data) else {
            return nil
        }
        return restored(size, minimum: minimum)
    }

    /// Saves the size the user picked.
    /// - Parameters:
    ///   - size: the window size
    ///   - defaults: where to save it
    static func save(_ size: CGSize, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(size) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
