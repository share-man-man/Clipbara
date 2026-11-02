import SwiftUI

/// A horizontal `ScrollView` that fades out at each edge with more content
/// past it, and stays sharp at an edge once the content is scrolled up to it.
///
/// macOS 14 has no scroll offset API, so the content reports where it sits in
/// the scroll view's coordinate space and that is compared with the visible
/// width.
struct EdgeFadingHorizontalScrollView<Content: View>: View {
    /// How far each fade reaches into the scroll view.
    let fadeWidth: CGFloat
    @ViewBuilder let content: Content

    /// Where the content sits inside the visible area, moving as it scrolls.
    @State private var contentFrame: CGRect = .zero
    /// Visible width of the scroll view.
    @State private var viewportWidth: CGFloat = 0

    /// Coordinate space of the scroll view, for reading how far it has scrolled.
    private static var coordinateSpace: String { "edgeFadingHorizontalScroll" }

    /// - Parameters:
    ///   - fadeWidth: How far each fade reaches into the scroll view.
    ///   - content: The scrolled content.
    init(fadeWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.fadeWidth = fadeWidth
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(Self.coordinateSpace))
                } action: { contentFrame = $0 }
        }
        .coordinateSpace(.named(Self.coordinateSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .mask(fadeMask)
    }

    /// Whether content is scrolled out of view past the leading edge.
    private var hasContentBefore: Bool {
        contentFrame.minX < -1
    }

    /// Whether content is cut off past the trailing edge.
    private var hasContentAfter: Bool {
        contentFrame.maxX > viewportWidth + 1
    }

    /// Opaque in the middle, fading to clear at an edge with more content.
    private var fadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [hasContentBefore ? .clear : .black, .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)

            Rectangle()

            LinearGradient(
                colors: [.black, hasContentAfter ? .clear : .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
        }
    }
}
