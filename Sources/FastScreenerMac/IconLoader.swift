import AppKit

// Loads the flat black-fill SVG icons carried over from the original
// FastScreener2 (Windows) app's Resources folder, and recolors them for
// our dark chrome bars (they ship as solid black shapes on transparent,
// so a sourceAtop fill over the drawn icon retints them cleanly).
enum IconLoader {
    static func load(_ name: String, tint: NSColor = .white) -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Resources"),
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
