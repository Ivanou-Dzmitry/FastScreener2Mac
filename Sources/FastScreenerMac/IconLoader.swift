import AppKit

// Loads the flat black-fill SVG icons carried over from the original
// FastScreener2 (Windows) app's Resources folder. They already ship as
// solid black shapes on transparent, matching the original's black
// icons — default tint keeps that as-is; white icons read as washed
// out/distracting against the app's grey chrome.
enum IconLoader {
    static func load(_ name: String, tint: NSColor = .black) -> NSImage {
        guard let url = AppResourceBundle.shared.url(forResource: name, withExtension: "svg", subdirectory: "Resources"),
              let raw = NSImage(contentsOf: url) else {
            return NSImage(size: CGSize(width: 16, height: 16))
        }
        return tinted(raw, color: tint)
    }

    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let size = image.size
        let output = NSImage(size: size)
        output.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        CGRect(origin: .zero, size: size).fill(using: .sourceAtop)
        output.unlockFocus()
        return output
    }
}
