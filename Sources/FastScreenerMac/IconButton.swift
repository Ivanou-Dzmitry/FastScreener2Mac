import AppKit

// Plain view (not NSControl) so a click is handled directly regardless
// of whether the window is key — matches CaptureFrameView's own raw
// mouseDown handling for the same reason.
final class IconButton: NSView {
    var onClick: (() -> Void)?
    var isActive: Bool = false { didSet { needsDisplay = true } }
    private var isHovering = false { didSet { needsDisplay = true } }

    private let icon: NSImage
    private let iconPadding: CGFloat
    // Tool-select buttons (left toolbar) always sit on their own grey
    // chip, not just when active — matches the reference. Chrome buttons
    // (hamburger, close, etc.) stay transparent since they already sit
    // on a shared fixed-grey zone painted by the superview.
    private let showsBackgroundWhenInactive: Bool
    // Close button in the original turns Brown on hover (DimGray
    // otherwise); every other icon gets a generic subtle highlight
    // instead, since only Close had a custom WinForms MouseEnter/Leave
    // handler — the rest relied on the OS's free native button hover,
    // which our raw NSView buttons don't get automatically.
    private let hoverColor: NSColor?

    init(icon: NSImage, frame: CGRect, showsBackgroundWhenInactive: Bool = false, iconPadding: CGFloat = 5, hoverColor: NSColor? = nil) {
        self.icon = icon
        self.showsBackgroundWhenInactive = showsBackgroundWhenInactive
        self.iconPadding = iconPadding
        self.hoverColor = hoverColor
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    // Dark grey when off, near-black when on — the icons are white, so a
    // light-grey active chip (the original's look) washed out the
    // contrast here; near-black keeps the white icon clearly visible in
    // both states instead. Square corners, full bar width — matches the
    // reference, not a rounded inset "pill".
    override func draw(_ dirtyRect: NSRect) {
        if isActive {
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
            NSBezierPath(rect: bounds).fill()
        } else if isHovering, let hoverColor {
            hoverColor.setFill()
            NSBezierPath(rect: bounds).fill()
        } else if showsBackgroundWhenInactive {
            NSColor(calibratedWhite: isHovering ? 0.45 : 0.35, alpha: 1).setFill()
            NSBezierPath(rect: bounds).fill()
        } else if isHovering {
            NSColor(calibratedWhite: 1, alpha: 0.15).setFill()
            NSBezierPath(rect: bounds).fill()
        }
        icon.draw(in: bounds.insetBy(dx: iconPadding, dy: iconPadding), from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
