import AppKit

// Persisted user-configurable settings, matching fields from the
// original FastScreener2's settings classes: arrow color/length/width,
// frame color/stroke width/fixed click size, number color/font, panel
// (chrome) color, clear-after-capture, and the 4 size presets. Also
// supports named profiles (Save as/Load/Delete/Reset), like the
// original's Profile dropdown.
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private static let profilesKey = "settingsProfiles"
    // Matches the Windows app's CreateDefaultSettings() first-run values
    // exactly (frame_color / number_color both "#FFA500", not the .NET
    // named colors "Orange" (Color.Orange) or "OrangeRed" that appear
    // elsewhere in that file's fallback code paths).
    static let defaultOrange = NSColor(calibratedRed: 0xFF / 255.0, green: 0xA5 / 255.0, blue: 0x00 / 255.0, alpha: 1)
    static let defaultProfileSizes: [CGSize] = [
        CGSize(width: 650, height: 366),
        CGSize(width: 650, height: 650),
        CGSize(width: 650, height: 700),
        CGSize(width: 960, height: 600),
    ]

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

    var textColor: NSColor { didSet { save() } }
    var textFontSize: CGFloat { didSet { save() } }
    var textFontFamily: String { didSet { save() } } // empty = system default

    var chromeColor: NSColor { didSet { save() } } // top/left/bottom bar background ("Panel Color" in the original)
    var clearElementsAfterCapture: Bool { didSet { save() } }
    var saveToFile: Bool { didSet { save() } } // if off, F4 only copies to clipboard
    var showInfoLabel: Bool { didSet { save() } } // the Pos/Size/Elements status text
    // When on (default, matches the original), the captured image is
    // downsampled to exactly captureRect's point-size in pixels, so a
    // 650x366 capture is always a 650x366px file regardless of Retina
    // scale. When off, the file keeps the display's native pixel density.
    var dpiScale: Bool { didSet { save() } }

    var presetSizes: [CGSize] { didSet { save() } } // the 4 Alt+1..4 sizes ("Sizes" category in the original)

    // Where captures get saved ("File" category). nil = the default
    // Desktop/FastScreener Screens folder (created on first use).
    var saveFolderPath: String? { didSet { save() } }
    static let defaultSaveFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FastScreener Screens")
    var saveFolderURL: URL {
        if let path = saveFolderPath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return Self.defaultSaveFolder
    }

    // Last 10 filenames typed into the toolbar's name field, most
    // recent first — feeds the field's autocomplete/dropdown history.
    // Matches the original's "last_names" (SaveFileNameToHistory).
    var filenameHistory: [String] { didSet { save() } }

    func recordFilenameUsed(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var history = filenameHistory
        history.removeAll { $0 == trimmed }
        history.insert(trimmed, at: 0)
        filenameHistory = Array(history.prefix(10))
    }

    // "png" or "jpg". "32bpp"/"24bpp"/"8bpp" for pngDepth (only meaningful
    // when fileFormat == "png"). jpegQuality 1...100 (only meaningful when
    // fileFormat == "jpg").
    var fileFormat: String { didSet { save() } }
    var pngDepth: String { didSet { save() } }
    var jpegQuality: Int { didSet { save() } }

    // Guidelines: view-only alignment aids, never baked into the capture.
    // guidelineType: 1 = thirds grid, 2 = quarters grid, 3 = custom
    // margins (guideTop/Bottom/Left/RightIndent from each edge).
    var showGuides: Bool { didSet { save() } }
    var guidelineType: Int { didSet { save() } }
    var guideColor: NSColor { didSet { save() } }
    var guideTopIndent: CGFloat { didSet { save() } }
    var guideBottomIndent: CGFloat { didSet { save() } }
    var guideLeftIndent: CGFloat { didSet { save() } }
    var guideRightIndent: CGFloat { didSet { save() } }

    // Bars: two solid mask rectangles at the top/bottom of the capture
    // area, sized by the right-side dual-thumb slider — unlike Guides,
    // these ARE baked into the captured image (for covering/redacting
    // parts of the shot). Fractions are 0...1 of the capture height.
    var barColor: NSColor { didSet { save() } }
    var barTopFraction: CGFloat { didSet { save() } }
    var barBottomFraction: CGFloat { didSet { save() } }

    // Name of the profile last saved/loaded, persisted across restarts so
    // the Settings profile dropdown reopens on the same selection instead
    // of always jumping back to "default".
    var currentProfileName: String { didSet { save() } }

    private init() {
        arrowColor = Self.loadColor(key: "arrowColor") ?? .cyan
        arrowLength = Self.loadNumber(key: "arrowLength") ?? 50
        arrowWidth = Self.loadNumber(key: "arrowWidth") ?? 1

        frameColor = Self.loadColor(key: "frameColor") ?? Self.defaultOrange
        frameStrokeWidth = Self.loadNumber(key: "frameStrokeWidth") ?? 1
        frameFixedWidth = Self.loadNumber(key: "frameFixedWidth") ?? 80
        frameFixedHeight = Self.loadNumber(key: "frameFixedHeight") ?? 80

        numberColor = Self.loadColor(key: "numberColor") ?? Self.defaultOrange
        numberFontSize = Self.loadNumber(key: "numberFontSize") ?? 26
        numberFontFamily = defaults.string(forKey: "numberFontFamily") ?? ""

        textColor = Self.loadColor(key: "textColor") ?? Self.defaultOrange
        textFontSize = Self.loadNumber(key: "textFontSize") ?? 26
        textFontFamily = defaults.string(forKey: "textFontFamily") ?? ""

        chromeColor = Self.loadColor(key: "chromeColor") ?? NSColor(calibratedRed: 112.0 / 255, green: 128.0 / 255, blue: 144.0 / 255, alpha: 1) // SlateGray, opaque like the original
        clearElementsAfterCapture = defaults.object(forKey: "clearElementsAfterCapture") as? Bool ?? true
        saveToFile = defaults.object(forKey: "saveToFile") as? Bool ?? true
        showInfoLabel = defaults.object(forKey: "showInfoLabel") as? Bool ?? true
        dpiScale = defaults.object(forKey: "dpiScale") as? Bool ?? true

        presetSizes = Self.loadPresetSizes() ?? Self.defaultProfileSizes
        saveFolderPath = defaults.string(forKey: "saveFolderPath")
        filenameHistory = defaults.stringArray(forKey: "filenameHistory") ?? []
        fileFormat = defaults.string(forKey: "fileFormat") ?? "png"
        pngDepth = defaults.string(forKey: "pngDepth") ?? "32bpp"
        jpegQuality = defaults.object(forKey: "jpegQuality") as? Int ?? 75

        showGuides = defaults.object(forKey: "showGuides") as? Bool ?? false
        guidelineType = defaults.object(forKey: "guidelineType") as? Int ?? 3
        guideColor = Self.loadColor(key: "guideColor") ?? NSColor(calibratedWhite: 0xD3 / 255.0, alpha: 1) // LightGray #D3D3D3
        guideTopIndent = Self.loadNumber(key: "guideTopIndent") ?? 10
        guideBottomIndent = Self.loadNumber(key: "guideBottomIndent") ?? 10
        guideLeftIndent = Self.loadNumber(key: "guideLeftIndent") ?? 10
        guideRightIndent = Self.loadNumber(key: "guideRightIndent") ?? 10

        barColor = Self.loadColor(key: "barColor") ?? NSColor(calibratedWhite: 0x31 / 255.0, alpha: 1) // #313131
        barTopFraction = Self.loadNumber(key: "barTopFraction") ?? 0
        barBottomFraction = Self.loadNumber(key: "barBottomFraction") ?? 0

        currentProfileName = defaults.string(forKey: "currentProfileName") ?? "default"
    }

    private func save() {
        defaults.set(Double(arrowLength), forKey: "arrowLength")
        defaults.set(Double(arrowWidth), forKey: "arrowWidth")
        defaults.set(Double(frameStrokeWidth), forKey: "frameStrokeWidth")
        defaults.set(Double(frameFixedWidth), forKey: "frameFixedWidth")
        defaults.set(Double(frameFixedHeight), forKey: "frameFixedHeight")
        defaults.set(Double(numberFontSize), forKey: "numberFontSize")
        defaults.set(numberFontFamily, forKey: "numberFontFamily")
        defaults.set(Double(textFontSize), forKey: "textFontSize")
        defaults.set(textFontFamily, forKey: "textFontFamily")
        defaults.set(clearElementsAfterCapture, forKey: "clearElementsAfterCapture")
        defaults.set(saveToFile, forKey: "saveToFile")
        defaults.set(showInfoLabel, forKey: "showInfoLabel")
        defaults.set(dpiScale, forKey: "dpiScale")
        defaults.set(presetSizes.map { Double($0.width) }, forKey: "presetWidths")
        defaults.set(presetSizes.map { Double($0.height) }, forKey: "presetHeights")
        if let saveFolderPath { defaults.set(saveFolderPath, forKey: "saveFolderPath") } else { defaults.removeObject(forKey: "saveFolderPath") }
        defaults.set(filenameHistory, forKey: "filenameHistory")
        defaults.set(fileFormat, forKey: "fileFormat")
        defaults.set(pngDepth, forKey: "pngDepth")
        defaults.set(jpegQuality, forKey: "jpegQuality")
        defaults.set(showGuides, forKey: "showGuides")
        defaults.set(guidelineType, forKey: "guidelineType")
        defaults.set(Double(guideTopIndent), forKey: "guideTopIndent")
        defaults.set(Double(guideBottomIndent), forKey: "guideBottomIndent")
        defaults.set(Double(guideLeftIndent), forKey: "guideLeftIndent")
        defaults.set(Double(guideRightIndent), forKey: "guideRightIndent")
        Self.saveColor(guideColor, key: "guideColor")
        defaults.set(Double(barTopFraction), forKey: "barTopFraction")
        defaults.set(Double(barBottomFraction), forKey: "barBottomFraction")
        Self.saveColor(barColor, key: "barColor")
        defaults.set(currentProfileName, forKey: "currentProfileName")
        Self.saveColor(arrowColor, key: "arrowColor")
        Self.saveColor(frameColor, key: "frameColor")
        Self.saveColor(numberColor, key: "numberColor")
        Self.saveColor(textColor, key: "textColor")
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

    private static func loadPresetSizes() -> [CGSize]? {
        guard let widths = UserDefaults.standard.array(forKey: "presetWidths") as? [Double],
              let heights = UserDefaults.standard.array(forKey: "presetHeights") as? [Double],
              widths.count == heights.count, !widths.isEmpty else { return nil }
        return zip(widths, heights).map { CGSize(width: $0, height: $1) }
    }

    // MARK: - Profiles

    struct Snapshot: Codable {
        var arrowColor: Data
        var arrowLength: Double
        var arrowWidth: Double
        var frameColor: Data
        var frameStrokeWidth: Double
        var frameFixedWidth: Double
        var frameFixedHeight: Double
        var numberColor: Data
        var numberFontSize: Double
        var numberFontFamily: String
        var textColor: Data
        var textFontSize: Double
        var textFontFamily: String
        var chromeColor: Data
        var clearElementsAfterCapture: Bool
        var saveToFile: Bool
        var showInfoLabel: Bool
        var dpiScale: Bool
        var presetWidths: [Double]
        var presetHeights: [Double]
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(
            arrowColor: Self.encode(arrowColor), arrowLength: arrowLength, arrowWidth: arrowWidth,
            frameColor: Self.encode(frameColor), frameStrokeWidth: frameStrokeWidth,
            frameFixedWidth: frameFixedWidth, frameFixedHeight: frameFixedHeight,
            numberColor: Self.encode(numberColor), numberFontSize: numberFontSize, numberFontFamily: numberFontFamily,
            textColor: Self.encode(textColor), textFontSize: textFontSize, textFontFamily: textFontFamily,
            chromeColor: Self.encode(chromeColor), clearElementsAfterCapture: clearElementsAfterCapture,
            saveToFile: saveToFile, showInfoLabel: showInfoLabel, dpiScale: dpiScale,
            presetWidths: presetSizes.map { Double($0.width) }, presetHeights: presetSizes.map { Double($0.height) }
        )
    }

    private func apply(_ snapshot: Snapshot) {
        arrowColor = Self.decode(snapshot.arrowColor) ?? arrowColor
        arrowLength = CGFloat(snapshot.arrowLength)
        arrowWidth = CGFloat(snapshot.arrowWidth)
        frameColor = Self.decode(snapshot.frameColor) ?? frameColor
        frameStrokeWidth = CGFloat(snapshot.frameStrokeWidth)
        frameFixedWidth = CGFloat(snapshot.frameFixedWidth)
        frameFixedHeight = CGFloat(snapshot.frameFixedHeight)
        numberColor = Self.decode(snapshot.numberColor) ?? numberColor
        numberFontSize = CGFloat(snapshot.numberFontSize)
        numberFontFamily = snapshot.numberFontFamily
        textColor = Self.decode(snapshot.textColor) ?? textColor
        textFontSize = CGFloat(snapshot.textFontSize)
        textFontFamily = snapshot.textFontFamily
        chromeColor = Self.decode(snapshot.chromeColor) ?? chromeColor
        clearElementsAfterCapture = snapshot.clearElementsAfterCapture
        saveToFile = snapshot.saveToFile
        showInfoLabel = snapshot.showInfoLabel
        dpiScale = snapshot.dpiScale
        if snapshot.presetWidths.count == snapshot.presetHeights.count, !snapshot.presetWidths.isEmpty {
            presetSizes = zip(snapshot.presetWidths, snapshot.presetHeights).map { CGSize(width: $0, height: $1) }
        }
    }

    private static func encode(_ color: NSColor) -> Data {
        (try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)) ?? Data()
    }

    private static func decode(_ data: Data) -> NSColor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    private var profilesDict: [String: Data] {
        get { (defaults.dictionary(forKey: Self.profilesKey) as? [String: Data]) ?? [:] }
        set { defaults.set(newValue, forKey: Self.profilesKey) }
    }

    var profileNames: [String] {
        var names = Array(profilesDict.keys).sorted()
        if !names.contains("default") { names.insert("default", at: 0) }
        return names
    }

    func saveProfile(named name: String) {
        guard let data = try? JSONEncoder().encode(currentSnapshot()) else { return }
        var dict = profilesDict
        dict[name] = data
        profilesDict = dict
        currentProfileName = name
    }

    func loadProfile(named name: String) {
        guard let data = profilesDict[name], let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        apply(snapshot)
        currentProfileName = name
    }

    func deleteProfile(named name: String) {
        var dict = profilesDict
        dict.removeValue(forKey: name)
        profilesDict = dict
        if currentProfileName == name { currentProfileName = "default" }
    }

    func resetToDefaults() {
        arrowColor = .cyan
        arrowLength = 50
        arrowWidth = 1
        frameColor = Self.defaultOrange
        frameStrokeWidth = 1
        frameFixedWidth = 80
        frameFixedHeight = 80
        numberColor = Self.defaultOrange
        numberFontSize = 26
        numberFontFamily = ""
        textColor = Self.defaultOrange
        textFontSize = 26
        textFontFamily = ""
        chromeColor = NSColor(calibratedRed: 112.0 / 255, green: 128.0 / 255, blue: 144.0 / 255, alpha: 1)
        clearElementsAfterCapture = true
        saveToFile = true
        showInfoLabel = true
        dpiScale = true
        presetSizes = Self.defaultProfileSizes
        saveFolderPath = nil
        filenameHistory = []
        fileFormat = "png"
        pngDepth = "32bpp"
        jpegQuality = 75
        showGuides = false
        guidelineType = 3
        guideColor = NSColor(calibratedWhite: 0xD3 / 255.0, alpha: 1)
        guideTopIndent = 10
        guideBottomIndent = 10
        guideLeftIndent = 10
        guideRightIndent = 10
        barColor = NSColor(calibratedWhite: 0x31 / 255.0, alpha: 1)
        barTopFraction = 0
        barBottomFraction = 0
    }
}
