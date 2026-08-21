import AppKit

// Ported from the original's VerticalRangeTrackBar: two independent
// thumbs on a vertical track, controlling top/bottom mask-bar heights
// as fractions (0...1) of the capture area. Double-click resets both to
// 0 (no masking), matching the original's LowerValue=0/UpperValue=100
// reset.
final class VerticalRangeSlider: NSView {
    var topFraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var bottomFraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var onChange: ((CGFloat, CGFloat) -> Void)?

    private let minGap: CGFloat = 0.05
    private let thumbHitRadius: CGFloat = 10
    private var draggingTop = false
    private var draggingBottom = false

    override func draw(_ dirtyRect: NSRect) {
        let trackWidth = bounds.width / 3
        let trackRect = CGRect(x: bounds.midX - trackWidth / 2, y: 0, width: trackWidth, height: bounds.height)
        NSColor(calibratedWhite: 0.7, alpha: 1).setFill()
        NSBezierPath(rect: trackRect).fill()

        let topY = thumbY(forTop: topFraction)
        let bottomY = thumbY(forBottom: bottomFraction)

        // Unmasked middle range, for visual feedback.
        NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.0, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: trackRect.minX, y: bottomY, width: trackWidth, height: max(0, topY - bottomY))).fill()

        drawThumb(at: topY)
        drawThumb(at: bottomY)
    }

    private func drawThumb(at y: CGFloat) {
        let w = bounds.width * 0.75
        let h: CGFloat = 8
        let rect = CGRect(x: bounds.midX - w / 2, y: y - h / 2, width: w, height: h)
        NSColor.black.setFill()
        NSBezierPath(rect: rect).fill()
    }

    // topFraction 0 = thumb at the very top; 1 = thumb at the bottom.
    private func thumbY(forTop fraction: CGFloat) -> CGFloat {
        bounds.height - bounds.height * fraction
    }

    // bottomFraction 0 = thumb at the very bottom; 1 = thumb at the top.
    private func thumbY(forBottom fraction: CGFloat) -> CGFloat {
        bounds.height * fraction
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if event.clickCount >= 2 {
            topFraction = 0
            bottomFraction = 0
            onChange?(topFraction, bottomFraction)
            return
        }

        let topY = thumbY(forTop: topFraction)
        let bottomY = thumbY(forBottom: bottomFraction)
        if abs(p.y - topY) <= abs(p.y - bottomY) {
            draggingTop = true
        } else {
            draggingBottom = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard bounds.height > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)

        if draggingTop {
            let raw = 1 - (p.y / bounds.height)
            topFraction = max(0, min(raw, 1 - bottomFraction - minGap))
            onChange?(topFraction, bottomFraction)
        } else if draggingBottom {
            let raw = p.y / bounds.height
            bottomFraction = max(0, min(raw, 1 - topFraction - minGap))
            onChange?(topFraction, bottomFraction)
        }
    }

    override func mouseUp(with event: NSEvent) {
        draggingTop = false
        draggingBottom = false
    }
}
