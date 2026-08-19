import AppKit

// Persisted user-configurable annotation settings, matching fields from
// the original FastScreener2's Arrow/Frame settings classes: arrow
// color/length/width, frame color/stroke width/fixed click size.
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var arrowColor: NSColor { didSet { save() } }
    var arrowLength: CGFloat { didSet { save() } } // px, min 8
    var arrowWidth: CGFloat { didSet { save() } } // px, 1...5

    var frameColor: NSColor { didSet { save() } }
    var frameStrokeWidth: CGFloat { didSet { save() } } // px, 1...10
    var frameFixedWidth: CGFloat { didSet { save() } } // px, min 32 — size of the box a plain middle-click places
    var frameFixedHeight: CGFloat { didSet { save() } } // px, min 32

    var numberColor: NSColor { didSet { save() } }
    var numberFontSize: CGFloat { didSet { save() } }
    var numberFontFamily: String { didSet { save() } } // empty = system default

    var chromeColor: NSColor { didSet { save() } } // top/left/bottom bar background ("Panel Color" in the original)
    var clearElementsAfterCapture: Bool { didSet { save() } }

    private init() {
        arrowColor = Self.loadColor(key: "arrowColor") ?? .cyan
        arrowLength = Self.loadNumber(key: "arrowLength") ?? 50
        arrowWidth = Self.loadNumber(key: "arrowWidth") ?? 1

        frameColor = Self.loadColor(key: "frameColor") ?? NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.0, alpha: 1.0)
        frameStrokeWidth = Self.loadNumber(key: "frameStrokeWidth") ?? 1
        frameFixedWidth = Self.loadNumber(key: "frameFixedWidth") ?? 80
        frameFixedHeight = Self.loadNumber(key: "frameFixedHeight") ?? 80

        numberColor = Self.loadColor(key: "numberColor") ?? .yellow
        numberFontSize = Self.loadNumber(key: "numberFontSize") ?? 26
        numberFontFamily = defaults.string(forKey: "numberFontFamily") ?? ""

        chromeColor = Self.loadColor(key: "chromeColor") ?? NSColor(calibratedRed: 112.0 / 255, green: 128.0 / 255, blue: 144.0 / 255, alpha: 0.92) // SlateGray
        clearElementsAfterCapture = defaults.object(forKey: "clearElementsAfterCapture") as? Bool ?? true
    }

    private func save() {
        defaults.set(Double(arrowLength), forKey: "arrowLength")
        defaults.set(Double(arrowWidth), forKey: "arrowWidth")
        defaults.set(Double(frameStrokeWidth), forKey: "frameStrokeWidth")
        defaults.set(Double(frameFixedWidth), forKey: "frameFixedWidth")
        defaults.set(Double(frameFixedHeight), forKey: "frameFixedHeight")
        defaults.set(Double(numberFontSize), forKey: "numberFontSize")
        defaults.set(numberFontFamily, forKey: "numberFontFamily")
        defaults.set(clearElementsAfterCapture, forKey: "clearElementsAfterCapture")
        Self.saveColor(arrowColor, key: "arrowColor")
        Self.saveColor(frameColor, key: "frameColor")
        Self.saveColor(numberColor, key: "numberColor")
        Self.saveColor(chromeColor, key: "chromeColor")
    }

    private static func loadNumber(key: String) -> CGFloat? {
        let value = UserDefaults.standard.double(forKey: key)
        return value == 0 ? nil : CGFloat(value)
    }

    private static func loadColor(key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    private static func saveColor(_ color: NSColor, key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
