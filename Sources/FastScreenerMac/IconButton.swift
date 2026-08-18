import AppKit

// Plain view (not NSControl) so a click is handled directly regardless
// of whether the window is key — matches CaptureFrameView's own raw
// mouseDown handling for the same reason.
final class IconButton: NSView {
    var onClick: (() -> Void)?
    var isActive: Bool = false { didSet { needsDisplay = true } }

    private let icon: NSImage

    init(icon: NSImage, frame: CGRect) {
        self.icon = icon
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        if isActive {
            NSColor.systemBlue.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let padding: CGFloat = 5
        icon.draw(in: bounds.insetBy(dx: padding, dy: padding), from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
