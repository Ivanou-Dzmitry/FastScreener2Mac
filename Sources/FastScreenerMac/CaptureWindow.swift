import AppKit

// Borderless, transparent, always-on-top "capture frame" window.
// Equivalent to FS2MainForm in the original WinForms app: the window's
// content area IS the screen region that will be captured, so it must
// show nothing itself (interior stays fully transparent) while still
// receiving mouse events for resize/move/annotation.
final class CaptureWindow: NSWindow {
    convenience init(contentRect: CGRect) {
        self.init(contentRect: contentRect, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)

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
}
