import AppKit

enum AnnotationTool: CaseIterable {
    case none, arrow, frame, number
}

enum Annotation {
    case arrow(start: CGPoint, end: CGPoint)
    case frame(rect: CGRect)
    case number(point: CGPoint, value: Int)

    func draw(color: NSColor = .systemYellow, lineWidth: CGFloat = 3) {
        switch self {
        case .arrow(let start, let end):
            Self.drawArrow(from: start, to: end, color: color, lineWidth: lineWidth)
        case .frame(let rect):
            let path = NSBezierPath(rect: rect)
            path.lineWidth = lineWidth
            color.setStroke()
            path.stroke()
        case .number(let point, let value):
            Self.drawNumber(value, at: point, color: color)
        }
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 14
        let headAngle: CGFloat = .pi / 7
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

    private static func drawNumber(_ value: Int, at point: CGPoint, color: NSColor) {
        let radius: CGFloat = 12
        let circleRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        color.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        let text = "\(value)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attrs)
    }
}
