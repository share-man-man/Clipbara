import AppKit
import SwiftUI

/// The small floating list shown while a Clip Queue is on.
///
/// It never becomes key: if it took keyboard focus, the user's next ⌘V would
/// land here instead of in the app they are pasting into.
@MainActor
final class ClipQueueWindowController {
    /// Sizes and timings of the queue window.
    private typealias Tokens = DesignTokens.ClipQueue

    private var panel: ClipQueuePanel?
    /// Observes the user dragging the window, to remember where it went.
    private var moveObserver: NSObjectProtocol?
    /// Observes the user resizing the window, to keep the size they pick.
    private var resizeObserver: NSObjectProtocol?
    /// Set while the window is moved by code, so only drags are remembered.
    private var isPlacing = false
    /// Observes Clipbara coming to the front, which a row drag in the list does.
    private var activationObserver: NSObjectProtocol?
    /// Waits for a row drag that brought Clipbara to the front to end.
    private var deactivateTimer: Timer?

    func show(queue: ClipQueue) {
        if panel == nil {
            /// The size the user last picked, or the default one.
            let size = ClipQueueWindowSize.load(minimum: Tokens.minimumSize) ?? Tokens.defaultSize
            let panel = ClipQueuePanel(contentRect: NSRect(origin: .zero, size: size))
            let host = FirstMouseHostingView(rootView: ClipQueueView(queue: queue))
            // The window sets the size, never the content.
            host.sizingOptions = []
            // The content runs under the hidden title bar, not below it.
            host.safeAreaRegions = []
            // Inside a plain view rather than as the window's content view: as
            // the content view of a titled window, the hosting view resizes the
            // window itself after each layout, which looped until AppKit threw
            // ("more Update Constraints in Window passes than there are views").
            /// Holds the content, filling the window.
            let container = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
            host.frame = container.bounds
            host.autoresizingMask = [.width, .height]
            container.addSubview(host)
            panel.contentView = container
            self.panel = panel
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rememberPlacement() }
            }
            observeResizing(of: panel)
            observeActivation()
        }
        guard let panel else { return }
        place()
        // Fade in rather than the system zoom, which wobbled with the content
        // settling in. Starts from the current alpha, so a show during a fade out
        // picks up where it is.
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Tokens.fadeDuration
            panel.animator().alphaValue = 1
        }
    }

    /// Keeps the size the user resizes the window to, for the next queue.
    /// - Parameter panel: the queue window
    private func observeResizing(of panel: NSPanel) {
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                ClipQueueWindowSize.save(panel.frame.size)
                // Resizing by the top or left edge moves the window too.
                self.rememberPlacement()
            }
        }
    }

    /// Hands the front back when a drag in the list brings Clipbara forward.
    ///
    /// The window never activates Clipbara when clicked, but the list's row
    /// drag (AppKit's table drag) did. The app the user was pasting into lost
    /// the front, and its first ⌘V after they clicked back came out empty.
    private func observeActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didBecomeActive() }
        }
    }

    /// Steps back once the drag ends, if a press in this window brought Clipbara forward.
    private func didBecomeActive() {
        guard let panel, panel.isVisible,
              NSEvent.pressedMouseButtons & 1 != 0,
              panel.frame.contains(NSEvent.mouseLocation) else { return }
        deactivateTimer?.invalidate()
        // Not mid-drag, which would cancel it: after the button comes up.
        // In the common modes, so it keeps checking inside AppKit's drag loop.
        /// Checks for the button coming up.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self?.deactivateTimer?.invalidate()
                self?.deactivateTimer = nil
                // The app that was in front before comes back.
                NSApp.deactivate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        deactivateTimer = timer
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Tokens.fadeDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Shown again while fading out: keep it up.
                guard let panel = self?.panel, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        }
    }

    /// Puts the window on the screen under the mouse, where the user last dragged
    /// it on whichever screen that was, or at the top right the first time.
    private func place() {
        guard let panel else { return }
        /// The screen the user is working on.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        /// The last drag, or the top right corner.
        let placement = ClipQueuePlacement.load() ?? ClipQueuePlacement(
            fromLeft: false, horizontalInset: Tokens.screenMargin, topInset: Tokens.screenMargin
        )
        isPlacing = true
        panel.setFrameOrigin(placement.origin(for: panel.frame.size, in: visible))
        isPlacing = false
    }

    /// Saves where the user dropped the window, relative to its screen.
    private func rememberPlacement() {
        guard !isPlacing, let panel, let visible = panel.screen?.visibleFrame else { return }
        ClipQueuePlacement(frame: panel.frame, in: visible).save()
    }
}

/// A titled window with its title bar hidden, so the system handles resizing:
/// the edges resize it, show the resize cursors (even with Clipbara in the
/// background), keep to `minSize`, and the system draws the rounded corners
/// and shadow.
final class ClipQueuePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Hide the title bar: no title, no traffic lights, the content under it.
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The SwiftUI content draws the background.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // The controller fades it in and out instead.
        animationBehavior = .none
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        // Clipbara stays in the background while the queue is up, and AppKit
        // otherwise shows tooltips only in the active app: the rows' full text
        // and the buttons' help never appeared.
        allowsToolTipsWhenApplicationIsInactive = true
        minSize = DesignTokens.ClipQueue.minimumSize
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Double-clicking the hidden title bar would zoom or minimize the window,
    // depending on the user's Dock setting. Neither fits a floating list.
    override func zoom(_ sender: Any?) {}
    override func performZoom(_ sender: Any?) {}
    override func miniaturize(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}
}

/// Lets buttons respond to the first click in a window that never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
