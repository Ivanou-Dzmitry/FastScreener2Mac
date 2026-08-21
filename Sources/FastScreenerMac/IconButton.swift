import AppKit

// Plain view (not NSControl) so a click is handled directly regardless
// of whether the window is key — matches CaptureFrameView's own raw
// mouseDown handling for the same reason.
final class IconButton: NSView {
    var onClick: (() -> Void)?
    var isActive: Bool = false { didSet { needsDisplay = true } }

    private let icon: NSImage
    private let iconPadding: CGFloat
    // Tool-select buttons (left toolbar) always sit on their own grey
    // chip, not just when active — matches the reference. Chrome buttons
    // (hamburger, close, etc.) stay transparent since they already sit
    // on a shared fixed-grey zone painted by the superview.
    private let showsBackgroundWhenInactive: Bool

    init(icon: NSImage, frame: CGRect, showsBackgroundWhenInactive: Bool = false, iconPadding: CGFloat = 5) {
        self.icon = icon
        self.showsBackgroundWhenInactive = showsBackgroundWhenInactive
        self.iconPadding = iconPadding
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Dark grey when off, near-black when on — the icons are white, so a
    // light-grey active chip (the original's look) washed out the
    // contrast here; near-black keeps the white icon clearly visible in
    // both states instead. Square corners, full bar width — matches the
    // reference, not a rounded inset "pill".
    override func draw(_ dirtyRect: NSRect) {
        if isActive {
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
            NSBezierPath(rect: bounds).fill()
        } else if showsBackgroundWhenInactive {
            NSColor(calibratedWhite: 0.35, alpha: 1).setFill()
            NSBezierPath(rect: bounds).fill()
        }
        icon.draw(in: bounds.insetBy(dx: iconPadding, dy: iconPadding), from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
