import AppKit

/// Menu bar icon: the template image asset (`DesignTokens.MenuBar.iconAssetName`),
/// followed by the build badge (`Bundle.buildBadge`) when the build has one.
@MainActor
enum MenuBarIconImage {
    /// The icon for this build.
    static let current: NSImage = make(badge: Bundle.main.buildBadge)

    /// Combines the icon asset and the badge into one template image, so it follows
    /// the menu bar's light and dark appearance.
    /// - Parameter badge: text drawn after the icon, such as "DEV"; nil returns the icon alone
    /// - Returns: the icon, or the combined template image
    static func make(badge: String?) -> NSImage {
        /// The icon asset.
        let icon = self.icon()
        guard let badge else { return icon }

        /// Gap between the icon and the badge.
        let gap: CGFloat = 1
        /// Size of the icon, to size the combined image.
        let iconSize = icon.size
        /// Size of the badge text, to size the combined image.
        let tagSize = tag(badge).size()

        /// The combined image, drawn on demand at the menu bar's scale.
        let image = NSImage(
            size: NSSize(width: iconSize.width + gap + tagSize.width, height: iconSize.height),
            flipped: false
        ) { _ in
            // Parts are rebuilt here: the drawing handler may run off the main actor.
            /// The icon, drawn at the left.
            let icon = self.icon()
            /// The badge text, drawn after the icon.
            let tag = tag(badge)
            icon.draw(in: NSRect(origin: .zero, size: icon.size))
            tag.draw(at: NSPoint(x: icon.size.width + gap, y: (icon.size.height - tag.size().height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The menu bar icon asset.
    nonisolated private static func icon() -> NSImage {
        NSImage(named: DesignTokens.MenuBar.iconAssetName) ?? NSImage()
    }

    /// The badge text drawn after the icon.
    /// - Parameter badge: text to draw, such as "DEV"
    nonisolated private static func tag(_ badge: String) -> NSAttributedString {
        NSAttributedString(string: badge, attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .heavy),
            .foregroundColor: NSColor.black,
        ])
    }
}
