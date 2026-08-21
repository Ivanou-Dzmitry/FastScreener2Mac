import AppKit

// Shared position/size math for the watermark overlay, ported from
// FSUtils.RenderWatermark — used both for the live overlay
// (CaptureFrameView) and when baking it into the saved/copied output
// (AppDelegate.composite), so the two can't drift apart.
enum WatermarkRenderer {
    // `size` is the target length of the image's LONGER side (aspect
    // ratio preserved, matching the original), `padding` is the offset
    // from whichever edges the corner position touches.
    static func layout(imageSize: CGSize, in rect: CGRect, size: CGFloat, padding: CGFloat, position: String) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let aspect = imageSize.width / imageSize.height
        var targetSize = CGSize(width: size, height: size)
        if imageSize.width > imageSize.height {
            targetSize.height = size / aspect
        } else {
            targetSize.width = size * aspect
        }

        let origin: CGPoint
        switch position {
        case "top-left":
            origin = CGPoint(x: rect.minX + padding, y: rect.maxY - targetSize.height - padding)
        case "bottom-left":
            origin = CGPoint(x: rect.minX + padding, y: rect.minY + padding)
        case "bottom-right":
            origin = CGPoint(x: rect.maxX - targetSize.width - padding, y: rect.minY + padding)
        case "top-right":
            origin = CGPoint(x: rect.maxX - targetSize.width - padding, y: rect.maxY - targetSize.height - padding)
        default:
            origin = CGPoint(x: rect.minX + padding, y: rect.maxY - targetSize.height - padding)
        }
        return CGRect(origin: origin, size: targetSize)
    }
}
