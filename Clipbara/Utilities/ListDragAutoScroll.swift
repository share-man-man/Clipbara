import AppKit
import SwiftUI

extension View {
    /// Scrolls the list this modifies while a row is dragged near its top or
    /// bottom edge.
    ///
    /// A SwiftUI `List` reorders with AppKit's table drag, which only scrolls
    /// when the drag goes past the list's edge. In the queue panel, which never
    /// becomes key, it didn't scroll at all; this scrolls from just inside the edge.
    func autoScrollsWhileDragging() -> some View {
        background(ListDragAutoScrollProbe())
    }
}

/// When the list scrolls during a row drag, and by how much. Kept apart from
/// the view so it can be tested.
enum ListDragAutoScroll {
    /// How far inside the edge the list starts scrolling.
    static let edgeZone: CGFloat = 28
    /// Points scrolled per tick with the pointer at, or past, the edge.
    static let maxStep: CGFloat = 14
    /// Points to scroll this tick, faster the closer the pointer is to an edge.
    /// - Parameters:
    ///   - fromTop: distance from the pointer to the list's top edge, negative past it
    ///   - fromBottom: distance from the pointer to the list's bottom edge, negative past it
    /// - Returns: negative to scroll up, positive to scroll down, 0 away from the edges
    static func step(fromTop: CGFloat, fromBottom: CGFloat) -> CGFloat {
        if fromTop < edgeZone {
            return -maxStep * min(1, (edgeZone - fromTop) / edgeZone)
        }
        if fromBottom < edgeZone {
            return maxStep * min(1, (edgeZone - fromBottom) / edgeZone)
        }
        return 0
    }
}

/// Sits behind a `List` and finds its scroll view when a press starts on it.
private struct ListDragAutoScrollProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> ListDragAutoScrollView {
        ListDragAutoScrollView()
    }

    func updateNSView(_ view: ListDragAutoScrollView, context: Context) {}
}

/// Watches for a press on the list it sits behind, then scrolls the list while
/// the button is held, the pointer has moved off the press (a drag), and it is
/// near the top or bottom edge.
final class ListDragAutoScrollView: NSView {
    /// How often the scroll advances while held at an edge.
    private static let tickInterval: TimeInterval = 1.0 / 60

    /// Sees presses before the list does, to start watching the drag.
    private var mouseDownMonitor: Any?
    /// Advances the scroll while the button is held.
    private var timer: Timer?
    /// The list's scroll view, found when a press starts.
    private weak var scrollView: NSScrollView?
    /// Where the button went down, in screen coordinates.
    private var pressLocation: NSPoint = .zero
    /// Whether the pointer has left the press location, so this press is a drag.
    private var isDragging = false

    // Never takes clicks: they go to the list in front.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopWatching()
            if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
            mouseDownMonitor = nil
        } else if mouseDownMonitor == nil {
            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.pressed(event)
                return event
            }
        }
    }

    /// Starts watching when a press lands on the list.
    /// - Parameter event: the mouse-down event
    private func pressed(_ event: NSEvent) {
        guard event.window === window,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              let found = Self.tableScrollView(in: window?.contentView) else { return }
        scrollView = found
        pressLocation = NSEvent.mouseLocation
        isDragging = false
        startWatching()
    }

    /// Ticks until the button is let go. Runs in common modes so it keeps
    /// going inside AppKit's drag loop.
    private func startWatching() {
        timer?.invalidate()
        /// The tick timer, added to the common modes below.
        let tick = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// Stops the tick timer, once the button is let go or the view leaves its window.
    private func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    /// Scrolls one step toward the edge the pointer is near, faster the closer it is.
    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0,
              let scrollView, let window = scrollView.window else {
            stopWatching()
            return
        }
        // A press that hasn't moved is a click, not a drag: leave the list still,
        // or the row (or its remove button) would slide away under the pointer.
        if !isDragging {
            guard PointerDrag.hasStarted(from: pressLocation, to: NSEvent.mouseLocation) else { return }
            isDragging = true
        }
        /// The clip view, whose bounds origin is the scroll position.
        let clip = scrollView.contentView
        /// The pointer, in the clip view's coordinates.
        let point = clip.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        /// The visible part of the list.
        let visible = clip.bounds
        // Only while over the list's column, so a drag out to another app doesn't scroll it.
        guard point.x >= visible.minX, point.x <= visible.maxX else { return }

        // The clip view is flipped: y grows downward.
        /// Points to scroll: negative is up.
        let step = ListDragAutoScroll.step(fromTop: point.y - visible.minY, fromBottom: visible.maxY - point.y)
        guard step != 0 else { return }

        /// The furthest the list can scroll down.
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - visible.height)
        /// The new scroll position, kept within the list.
        let y = min(max(visible.minY + step, 0), maxY)
        guard y != visible.minY else { return }
        clip.scroll(to: NSPoint(x: visible.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    /// The scroll view holding a table (the `List`), searched depth first.
    /// - Parameter view: the view to search from
    static func tableScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView, scroll.documentView is NSTableView { return scroll }
        for subview in view.subviews {
            if let found = tableScrollView(in: subview) { return found }
        }
        return nil
    }
}
