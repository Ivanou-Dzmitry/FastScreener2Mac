import AppKit

// Borderless, transparent, always-on-top "capture frame" window.
// Equivalent to FS2MainForm in the original WinForms app: the window's
// content area IS the screen region that will be captured, so it must
// show nothing itself (interior stays fully transparent) while still
// receiving mouse events for move/annotation.
//
// styleMask deliberately omits .resizable: with it present, macOS gives
// borderless windows their own system-level edge-drag resize behavior
// regardless of what CaptureFrameView's own mouse handling does — that
// was the actual source of "resize by hand still works" even after all
// hand-resize logic was removed from the view.
final class CaptureWindow: NSWindow {
    convenience init(contentRect: CGRect) {
        // .miniaturizable is needed for the minimize button to work at
        // all — without it in styleMask, window.miniaturize(_:) is a no-op
        // even though nothing about it requires a visible title bar.
        self.init(contentRect: contentRect, styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false

        let view = CaptureFrameView(frame: CGRect(origin: .zero, size: contentRect.size))
        view.autoresizingMask = [.width, .height]
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // AppKit auto-constrains a window's frame to stay clear of the menu
    // bar by default, even for programmatic setFrameOrigin calls — which
    // silently capped how far up the capture zone could snap. Returning
    // the proposed frame unchanged lets it reach the true top of the
    // screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
