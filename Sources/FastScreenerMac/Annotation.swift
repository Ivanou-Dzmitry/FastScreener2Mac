import AppKit

enum AnnotationTool: CaseIterable {
    case none, arrow, frame, number, text
}

enum Annotation {
    case arrow(start: CGPoint, end: CGPoint)
    case frame(rect: CGRect)
    case number(point: CGPoint, value: Int)
    case text(point: CGPoint, string: String)

    func draw(color: NSColor = .systemYellow, lineWidth: CGFloat = 3, fontSize: CGFloat = 26, fontFamily: String = "") {
        switch self {
        case .arrow(let start, let end):
            Self.drawArrow(from: start, to: end, color: color, lineWidth: lineWidth)
        case .frame(let rect):
            let path = NSBezierPath(rect: rect)
            path.lineWidth = lineWidth
            color.setStroke()
            path.stroke()
        case .number(let point, let value):
            Self.drawNumber(value, at: point, color: color, fontSize: fontSize, fontFamily: fontFamily)
        case .text(let point, let string):
            Self.drawText(string, at: point, color: color, fontSize: fontSize, fontFamily: fontFamily)
        }
    }

    // Matches the original's RenderArrows: a slightly-offset black
    // "shadow" copy drawn first, then the real arrow on top, so it
    // reads clearly against any background.
    private static func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let shadowDY: CGFloat = -2 // Cocoa Y-up: negative = shifted down, matching the original's downward shift
        drawArrowShape(
            from: CGPoint(x: start.x, y: start.y + shadowDY),
            to: CGPoint(x: end.x, y: end.y + shadowDY),
            color: .black,
            lineWidth: lineWidth + 1,
            headLength: 13
        )
        drawArrowShape(from: start, to: end, color: color, lineWidth: lineWidth, headLength: 14)
    }

    private static func drawArrowShape(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat, headLength: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headAngle: CGFloat = .pi / 7

        // Stop the shaft short of the tip, instead of running it all the
        // way to `end` underneath the head triangle (which let a thick
        // shaft poke out past the triangle's edges). The triangle's base
        // (the p1-p2 line) sits at headLength*cos(headAngle) back from
        // the tip, not a full headLength back — pulling the shaft back
        // by the full headLength overshot the base and left a visible
        // gap. A tiny extra pullback keeps the stroke's rounded/butt
        // edge safely under the fill regardless of anti-aliasing.
        let shaftPullback = headLength * cos(headAngle) - 1
        let shaftEnd = CGPoint(x: end.x - shaftPullback * cos(angle), y: end.y - shaftPullback * sin(angle))
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: shaftEnd)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()

        let p1 = CGPoint(x: end.x - headLength * cos(angle - headAngle), y: end.y - headLength * sin(angle - headAngle))
        let p2 = CGPoint(x: end.x - headLength * cos(angle + headAngle), y: end.y - headLength * sin(angle + headAngle))
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: p1)
        head.line(to: p2)
        head.close()
        color.setFill()
        head.fill()
    }

    // Matches the original's RenderNumbers: just the digit(s), no
    // background shape — a black shadow copy (one point larger, shifted
    // down) drawn first, then the real colored number on top, centered.
    private static func drawNumber(_ value: Int, at point: CGPoint, color: NSColor, fontSize: CGFloat, fontFamily: String) {
        let text = "\(value)"
        let shadowDY: CGFloat = -1 // Cocoa Y-up: negative = shifted down

        let shadowFont = font(family: fontFamily, size: fontSize + 1)
        let shadowAttrs: [NSAttributedString.Key: Any] = [.font: shadowFont, .foregroundColor: NSColor.black]
        let shadowSize = text.size(withAttributes: shadowAttrs)
        text.draw(at: CGPoint(x: point.x - shadowSize.width / 2, y: point.y - shadowSize.height / 2 + shadowDY), withAttributes: shadowAttrs)

        let mainFont = font(family: fontFamily, size: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: mainFont, .foregroundColor: color]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attrs)
    }

    private static func font(family: String, size: CGFloat) -> NSFont {
        if !family.isEmpty, let font = NSFont(name: family, size: size) {
            return font
        }
        return NSFont.boldSystemFont(ofSize: size)
    }

    // Matches the original's RenderText: left-aligned at the click X
    // (not centered, unlike Number), vertically centered on the click
    // Y, no shadow copy.
    private static func drawText(_ string: String, at point: CGPoint, color: NSColor, fontSize: CGFloat, fontFamily: String) {
        let attrs: [NSAttributedString.Key: Any] = [.font: textFont(family: fontFamily, size: fontSize), .foregroundColor: color]
        let size = string.size(withAttributes: attrs)
        string.draw(at: CGPoint(x: point.x, y: point.y - size.height / 2), withAttributes: attrs)
    }

    // Regular weight, not bold — matches the original's
    // SystemFonts.DefaultFont fallback (Number's bold default is its
    // own choice, not shared with Text).
    private static func textFont(family: String, size: CGFloat) -> NSFont {
        if !family.isEmpty, let font = NSFont(name: family, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size)
    }
}
