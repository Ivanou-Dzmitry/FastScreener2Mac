import AppKit

// Draws the frame outline and handles edge/corner drag-resize plus
// interior drag-move, with snapping to screen edges. Equivalent to the
// WinForms drag panels around panelScreenArea.
final class CaptureFrameView: NSView {
    private let edgeMargin: CGFloat = 8
    private let minSize: CGFloat = 80
    private let snapMargin: CGFloat = 8
    private let borderWidth: CGFloat = 2
    private let borderColor = NSColor.systemRed

    private enum DragMode {
        case none
        case move(offset: CGPoint)
        case resize(left: Bool, right: Bool, top: Bool, bottom: Bool, startFrame: CGRect, startPoint: CGPoint)
    }
    private var dragMode: DragMode = .none

    override func draw(_ dirtyRect: NSRect) {
        let inset = borderWidth / 2
        let path = NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset))
        path.lineWidth = borderWidth
        borderColor.setStroke()
        path.stroke()
    }

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
