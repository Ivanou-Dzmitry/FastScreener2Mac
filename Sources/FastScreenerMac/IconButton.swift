import AppKit

// Plain view (not NSControl) so a click is handled directly regardless
// of whether the window is key — matches CaptureFrameView's own raw
// mouseDown handling for the same reason.
final class IconButton: NSView {
    var onClick: (() -> Void)?
    var isActive: Bool = false { didSet { needsDisplay = true } }

    private let icon: NSImage
    // Tool-select buttons (left toolbar) always sit on their own grey
    // chip, not just when active — matches the reference. Chrome buttons
    // (hamburger, close, etc.) stay transparent since they already sit
    // on a shared fixed-grey zone painted by the superview.
    private let showsBackgroundWhenInactive: Bool

    init(icon: NSImage, frame: CGRect, showsBackgroundWhenInactive: Bool = false) {
        self.icon = icon
        self.showsBackgroundWhenInactive = showsBackgroundWhenInactive
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Dark grey when off, near-black when on — the icons are white, so a
    // light-grey active chip (the original's look) washed out the
    // contrast here; near-black keeps the white icon clearly visible in
    // both states instead.
    override func draw(_ dirtyRect: NSRect) {
        if isActive {
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        } else if showsBackgroundWhenInactive {
            NSColor(calibratedWhite: 0.35, alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let padding: CGFloat = 5
        icon.draw(in: bounds.insetBy(dx: padding, dy: padding), from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
