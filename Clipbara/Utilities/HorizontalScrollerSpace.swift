import AppKit
import SwiftUI

/// Room a horizontal scroll bar takes below the content.
///
/// With System Settings > Appearance > Show scroll bars set to Always (or a mouse
/// attached), the scroll bar is the legacy kind and sits under the content
/// instead of over it. A card row sized to fill its whole area then pushed the
/// scroll view below the panel's bottom edge, along with the scroll bar.
@MainActor
enum HorizontalScrollerSpace {
    /// Height to keep free for the scroll bar right now: the legacy scroll bar's
    /// height, or 0 when scroll bars float over the content.
    static var current: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
    }
}

extension View {
    /// Keeps `space` equal to `HorizontalScrollerSpace.current`, following changes
    /// to the scroll bar setting and to the attached pointing devices.
    /// - Parameter space: the state to keep up to date
    func tracksHorizontalScrollerSpace(_ space: Binding<CGFloat>) -> some View {
        onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
            space.wrappedValue = HorizontalScrollerSpace.current
        }
    }
}
