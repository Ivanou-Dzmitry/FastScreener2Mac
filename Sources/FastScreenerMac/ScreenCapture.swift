import AppKit
import ScreenCaptureKit

// Captures an arbitrary screen rect (in AppKit global screen coordinates,
// e.g. an NSWindow.frame) to an image, excluding our own window from the
// result. Handles the AppKit (bottom-left origin) <-> Quartz/SCDisplay
// (top-left origin) coordinate flip and per-display Retina scale, so it
// works correctly across multiple monitors.
enum ScreenCapture {
    enum CaptureError: Error { case noScreen, noDisplay }

    static func captureRect(_ rect: CGRect, excludingWindowNumbers: [Int]) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let nsScreen = screenContaining(rect) else { throw CaptureError.noScreen }
        let screenNumber = (nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        guard let scDisplay = content.displays.first(where: { $0.displayID == screenNumber }) else {
            throw CaptureError.noDisplay
        }

        let excludedIDs = Set(excludingWindowNumbers.map { CGWindowID($0) })
        let excluded = content.windows.filter { excludedIDs.contains($0.windowID) }

        let filter = SCContentFilter(display: scDisplay, excludingWindows: excluded)
        let config = SCStreamConfiguration()

        // AppKit global coords: origin at bottom-left of the primary screen (screens[0]), y up.
        // Quartz/SCDisplay coords: origin at top-left of the primary screen, y down.
        let primaryHeight = NSScreen.screens[0].frame.height
        let cgGlobalRect = CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        let localRect = cgGlobalRect.offsetBy(dx: -scDisplay.frame.origin.x, dy: -scDisplay.frame.origin.y)
        config.sourceRect = localRect

        let scale = nsScreen.backingScaleFactor
        config.width = max(1, Int(localRect.width * scale))
        config.height = max(1, Int(localRect.height * scale))
        config.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cgImage, size: rect.size)
    }

    private static func screenContaining(_ rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            area(a.frame.intersection(rect)) < area(b.frame.intersection(rect))
        }
    }

    private static func area(_ r: CGRect) -> CGFloat { r.width * r.height }
}
