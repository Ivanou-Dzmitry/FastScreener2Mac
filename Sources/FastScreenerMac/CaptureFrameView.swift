import AppKit

// Draws the frame outline and handles edge/corner drag-resize plus
// interior drag-move (left button), with snapping to screen edges.
// Middle mouse button places annotations (arrow/frame/number) — handled
// directly by this view's own otherMouseDown/Dragged/Up, since it's
// already the topmost window over that screen area; no global event tap
// needed, unlike the original app's WH_MOUSE_LL hook.
final class CaptureFrameView: NSView {
    private let edgeMargin: CGFloat = 8
    private let minSize: CGFloat = 80
    private let snapMargin: CGFloat = 8
    private let borderWidth: CGFloat = 2
    private let borderColor = NSColor.systemRed
    private let annotationColor = NSColor.systemYellow

    private enum DragMode {
        case none
        case move(offset: CGPoint)
        case resize(left: Bool, right: Bool, top: Bool, bottom: Bool, startFrame: CGRect, startPoint: CGPoint)
    }
    private var dragMode: DragMode = .none

    var currentTool: AnnotationTool = .arrow { didSet { needsDisplay = true } }
    var annotations: [Annotation] = []
    private var nextNumber = 1
    private var pendingStart: CGPoint?
    private var pendingCurrent: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for annotation in annotations {
            annotation.draw(color: annotationColor)
        }
        drawPendingPreview()

        let inset = borderWidth / 2
        let path = NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset))
        path.lineWidth = borderWidth
        borderColor.setStroke()
        path.stroke()

        drawStatusLabel()
    }

    private func drawPendingPreview() {
        guard let start = pendingStart, let current = pendingCurrent else { return }
        let previewColor = annotationColor.withAlphaComponent(0.6)
        switch currentTool {
        case .arrow:
            Annotation.arrow(start: start, end: current).draw(color: previewColor)
        case .frame:
            let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
            Annotation.frame(rect: rect).draw(color: previewColor)
        case .none, .number:
            break
        }
    }

    private func drawStatusLabel() {
        let toolName: String
        switch currentTool {
        case .none: toolName = "None"
        case .arrow: toolName = "Arrow"
        case .frame: toolName = "Frame"
        case .number: toolName = "Number"
        }
        let text = "Tool: \(toolName)  [1 Arrow 2 Frame 3 Number 0 None | F4 Capture | ⌘Z Undo ⌘⇧Z Clear]"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.55),
        ]
        text.draw(at: CGPoint(x: 6, y: bounds.height - 18), withAttributes: attrs)
    }

    // MARK: - Left button: resize / move

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        let p = convert(event.locationInWindow, from: nil)
        let left = p.x <= edgeMargin
        let right = p.x >= bounds.width - edgeMargin
        let bottom = p.y <= edgeMargin
        let top = p.y >= bounds.height - edgeMargin

        if left || right || top || bottom {
            dragMode = .resize(left: left, right: right, top: top, bottom: bottom, startFrame: window.frame, startPoint: NSEvent.mouseLocation)
        } else {
            let winOrigin = window.frame.origin
            let mouseLoc = NSEvent.mouseLocation
            dragMode = .move(offset: CGPoint(x: mouseLoc.x - winOrigin.x, y: mouseLoc.y - winOrigin.y))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let mouseLoc = NSEvent.mouseLocation

        switch dragMode {
        case .move(let offset):
            let newOrigin = snappedOrigin(
                CGPoint(x: mouseLoc.x - offset.x, y: mouseLoc.y - offset.y),
                size: window.frame.size
            )
            window.setFrameOrigin(newOrigin)

        case .resize(let left, let right, let top, let bottom, let startFrame, let startPoint):
            let dx = mouseLoc.x - startPoint.x
            let dy = mouseLoc.y - startPoint.y
            var f = startFrame

            if left {
                let newX = min(startFrame.origin.x + dx, startFrame.maxX - minSize)
                f.size.width = startFrame.maxX - newX
                f.origin.x = newX
            } else if right {
                f.size.width = max(minSize, startFrame.width + dx)
            }

            if bottom {
                let newY = min(startFrame.origin.y + dy, startFrame.maxY - minSize)
                f.size.height = startFrame.maxY - newY
                f.origin.y = newY
            } else if top {
                f.size.height = max(minSize, startFrame.height + dy)
            }

            f = snappedResizeFrame(f, left: left, right: right, top: top, bottom: bottom)
            window.setFrame(f, display: true)

        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
    }

    override func resetCursorRects() {
        addCursorRect(NSRect(x: 0, y: bounds.height - edgeMargin, width: bounds.width, height: edgeMargin), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: edgeMargin), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: 0, width: edgeMargin, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - edgeMargin, y: 0, width: edgeMargin, height: bounds.height), cursor: .resizeLeftRight)
    }

    // MARK: - Middle button: annotations

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        let p = convert(event.locationInWindow, from: nil)
        switch currentTool {
        case .arrow, .frame:
            pendingStart = p
            pendingCurrent = p
        case .number:
            annotations.append(.number(point: p, value: nextNumber))
            nextNumber += 1
        case .none:
            break
        }
        needsDisplay = true
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard pendingStart != nil else { return }
        pendingCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func otherMouseUp(with event: NSEvent) {
        defer {
            pendingStart = nil
            pendingCurrent = nil
            needsDisplay = true
        }
        guard let start = pendingStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        guard hypot(end.x - start.x, end.y - start.y) > 4 else { return }

        switch currentTool {
        case .arrow:
            annotations.append(.arrow(start: start, end: end))
        case .frame:
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            annotations.append(.frame(rect: rect))
        case .none, .number:
            break
        }
    }

    // MARK: - Keyboard: tool switching + undo/clear

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else { return super.keyDown(with: event) }

        if event.modifierFlags.contains(.command), chars == "z" {
            if event.modifierFlags.contains(.shift) {
                annotations.removeAll()
                nextNumber = 1
            } else {
                _ = annotations.popLast()
            }
            needsDisplay = true
            return
        }

        switch chars {
        case "1": currentTool = .arrow
        case "2": currentTool = .frame
        case "3": currentTool = .number
        case "0": currentTool = .none
        default: super.keyDown(with: event)
        }
    }

    func clearAnnotationsAfterCapture() {
        annotations.removeAll()
        nextNumber = 1
        needsDisplay = true
    }

    // MARK: - Snapping (simplified: snaps to the union of all screens' bounds)

    private func virtualScreenFrame() -> CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    private func snappedOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let screenFrame = virtualScreenFrame()
        var o = origin
        if abs(o.x - screenFrame.minX) < snapMargin { o.x = screenFrame.minX }
        if abs((o.x + size.width) - screenFrame.maxX) < snapMargin { o.x = screenFrame.maxX - size.width }
        if abs(o.y - screenFrame.minY) < snapMargin { o.y = screenFrame.minY }
        if abs((o.y + size.height) - screenFrame.maxY) < snapMargin { o.y = screenFrame.maxY - size.height }
        return o
    }

    private func snappedResizeFrame(_ frame: CGRect, left: Bool, right: Bool, top: Bool, bottom: Bool) -> CGRect {
        let screenFrame = virtualScreenFrame()
        var f = frame
        if right, abs(f.maxX - screenFrame.maxX) < snapMargin {
            f.size.width = screenFrame.maxX - f.origin.x
        }
        if left, abs(f.minX - screenFrame.minX) < snapMargin {
            let delta = f.origin.x - screenFrame.minX
            f.origin.x -= delta
            f.size.width += delta
        }
        if top, abs(f.maxY - screenFrame.maxY) < snapMargin {
            f.size.height = screenFrame.maxY - f.origin.y
        }
        if bottom, abs(f.minY - screenFrame.minY) < snapMargin {
            let delta = f.origin.y - screenFrame.minY
            f.origin.y -= delta
            f.size.height += delta
        }
        return f
    }
}
