import AppKit

// Small floating companion window for the tool-select icons, positioned
// to overlap the main window's left edge (tracks its move/resize). Kept
// as a separate window — not embedded in CaptureFrameView's own chrome —
// because it visually overlaps outside the main window's bounds in the
// reference layout, and because a separate window can never collide with
// CaptureFrameView's own edge-resize hit zones the way an embedded
// subview did.
final class ToolPaletteWindow: NSWindow {
    private static let buttonSize: CGFloat = 28
    private static let rowHeight: CGFloat = 34
    private static let width: CGFloat = 34

    private var buttons: [AnnotationTool: IconButton] = [:]

    var onToolSelected: ((AnnotationTool) -> Void)? {
        didSet {
            for (tool, button) in buttons {
                button.onClick = { [weak self] in self?.onToolSelected?(tool) }
            }
        }
    }

    convenience init() {
        let tools: [(AnnotationTool, String)] = [
            (.arrow, "arrow_icon"),
            (.frame, "frame_icon"),
            (.number, "number_icon"),
        ]
        let height = Self.rowHeight * CGFloat(tools.count)

        self.init(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.92)
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false

        let container = NSView(frame: CGRect(x: 0, y: 0, width: Self.width, height: height))
        for (index, pair) in tools.enumerated() {
            let (tool, iconName) = pair
            let y = height - CGFloat(index + 1) * Self.rowHeight + (Self.rowHeight - Self.buttonSize) / 2
            let button = IconButton(icon: IconLoader.load(iconName), frame: CGRect(x: (Self.width - Self.buttonSize) / 2, y: y, width: Self.buttonSize, height: Self.buttonSize))
            container.addSubview(button)
            buttons[tool] = button
        }
        contentView = container
    }

    override var canBecomeKey: Bool { false }

    func highlight(_ tool: AnnotationTool) {
        for (t, button) in buttons {
            button.isActive = (t == tool)
        }
    }
}
