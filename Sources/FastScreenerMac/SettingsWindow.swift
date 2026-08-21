import AppKit

final class ColorWell: NSColorWell {
    private let onChange: (NSColor) -> Void

    init(color: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        self.color = color
        target = self
        action = #selector(changed)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changed() { onChange(color) }
}

final class NumberField: NSTextField, NSTextFieldDelegate {
    private let onChange: (CGFloat) -> Void

    init(value: CGFloat, onChange: @escaping (CGFloat) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 60).isActive = true
        stringValue = "\(Int(value))"
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func controlTextDidChange(_ obligatory: Notification) {
        if let value = Double(stringValue) {
            onChange(CGFloat(value))
        }
    }
}

final class CheckboxControl: NSButton {
    private let onChange: (Bool) -> Void

    init(title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setButtonType(.switch)
        self.title = title
        state = isOn ? .on : .off
        target = self
        action = #selector(changed)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changed() { onChange(state == .on) }
}

final class ActionButton: NSButton {
    private let onClick: () -> Void

    init(title: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.title = title
        bezelStyle = .rounded
        target = self
        action = #selector(tapped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onClick() }
}

final class ChoicePicker: NSPopUpButton {
    private let onChange: (String) -> Void

    init(options: [String], selected: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero, pullsDown: false)
        translatesAutoresizingMaskIntoConstraints = false
        addItems(withTitles: options)
        selectItem(withTitle: selected)
        target = self
        action = #selector(changed)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changed() { onChange(titleOfSelectedItem ?? "") }
}

// Dropdown of every installed font family, instead of free-typing a
// name and hoping it matches something NSFont(name:) can resolve.
final class FontPicker: NSPopUpButton {
    private let onChange: (String) -> Void
    private static let systemDefaultTitle = "System Default"

    init(selectedFamily: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero, pullsDown: false)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 180).isActive = true

        addItem(withTitle: Self.systemDefaultTitle)
        let families = NSFontManager.shared.availableFontFamilies.sorted()
        addItems(withTitles: families)

        if !selectedFamily.isEmpty, families.contains(selectedFamily) {
            selectItem(withTitle: selectedFamily)
        } else {
            selectItem(withTitle: Self.systemDefaultTitle)
        }

        target = self
        action = #selector(changed)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changed() {
        let title = titleOfSelectedItem ?? Self.systemDefaultTitle
        onChange(title == Self.systemDefaultTitle ? "" : title)
    }
}

final class SettingsWindow: NSWindow {
    private var profilePopup: NSPopUpButton!

    convenience init() {
        self.init(contentRect: CGRect(x: 0, y: 0, width: 400, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "Settings"
        isReleasedWhenClosed = false
        // The main capture window is .floating (always-on-top), so a
        // plain-level settings window ends up stuck behind it and is
        // unclickable. Needs to be higher than .floating, not just equal.
        level = .modalPanel
        minSize = CGSize(width: 360, height: 280)
        rebuildContent()
    }

    // Rebuilds the whole window body from the current settings values.
    // Needed after Load/Reset, since the form controls only push values
    // out via their onChange closures — there's no live binding pulling
    // programmatic changes back into them, so a full rebuild is the
    // simplest way to keep what's on screen in sync.
    private func rebuildContent() {
        let settings = AppSettings.shared

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(Self.sectionLabel("Arrow"))
        stack.addArrangedSubview(Self.row(title: "Color", control: ColorWell(color: settings.arrowColor) { settings.arrowColor = $0 }))
        stack.addArrangedSubview(Self.row(title: "Length (px, min 8)", control: NumberField(value: settings.arrowLength) { settings.arrowLength = max(8, $0) }))
        stack.addArrangedSubview(Self.row(title: "Width (px, 1-5)", control: NumberField(value: settings.arrowWidth) { settings.arrowWidth = min(5, max(1, $0)) }))

        stack.addArrangedSubview(Self.sectionLabel("Bar"))
        stack.addArrangedSubview(Self.row(title: "Color", control: ColorWell(color: settings.barColor) { settings.barColor = $0 }))
        let barHint = NSTextField(wrappingLabelWithString: "Drag the two thumbs on the right-side panel to mask off the top/bottom of the capture area; double-click the slider to reset both to 0.")
        barHint.font = .systemFont(ofSize: 11)
        barHint.textColor = .secondaryLabelColor
        barHint.preferredMaxLayoutWidth = 340
        stack.addArrangedSubview(barHint)

        stack.addArrangedSubview(Self.sectionLabel("File"))
        // Full-width vertical layout, not a title+control row: the path
        // text is too wide to share a row with a 170pt title column
        // without overflowing the window and breaking Auto Layout.
        let chooseButton = ActionButton(title: "Choose Save Folder…") { [weak self] in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.directoryURL = settings.saveFolderURL
            guard panel.runModal() == .OK, let url = panel.url else { return }
            settings.saveFolderPath = url.path
            self?.rebuildContent()
        }
        stack.addArrangedSubview(chooseButton)
        let pathLabel = NSTextField(wrappingLabelWithString: settings.saveFolderURL.path)
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.preferredMaxLayoutWidth = 320
        stack.addArrangedSubview(pathLabel)

        stack.addArrangedSubview(Self.row(title: "Format", control: ChoicePicker(options: ["png", "jpg"], selected: settings.fileFormat) { [weak self] value in
            settings.fileFormat = value
            self?.rebuildContent() // format switch changes which of PNG depth / JPEG quality applies below
        }))
        if settings.fileFormat == "jpg" {
            stack.addArrangedSubview(Self.row(title: "JPEG quality (1-100)", control: NumberField(value: CGFloat(settings.jpegQuality)) { settings.jpegQuality = Int(min(100, max(1, $0))) }))
        } else {
            stack.addArrangedSubview(Self.row(title: "PNG depth", control: ChoicePicker(options: ["32bpp", "24bpp", "8bpp"], selected: settings.pngDepth) { settings.pngDepth = $0 }))
        }

        stack.addArrangedSubview(Self.sectionLabel("Frame"))
        stack.addArrangedSubview(Self.row(title: "Color", control: ColorWell(color: settings.frameColor) { settings.frameColor = $0 }))
        stack.addArrangedSubview(Self.row(title: "Stroke width (px, 1-10)", control: NumberField(value: settings.frameStrokeWidth) { settings.frameStrokeWidth = min(10, max(1, $0)) }))
        stack.addArrangedSubview(Self.row(title: "Fixed width (px, min 32)", control: NumberField(value: settings.frameFixedWidth) { settings.frameFixedWidth = max(32, $0) }))
        stack.addArrangedSubview(Self.row(title: "Fixed height (px, min 32)", control: NumberField(value: settings.frameFixedHeight) { settings.frameFixedHeight = max(32, $0) }))
        let frameHint = NSTextField(wrappingLabelWithString: "Fixed width/height is the box a plain middle-click places with the Frame tool; dragging still draws a free-size box.")
        frameHint.font = .systemFont(ofSize: 11)
        frameHint.textColor = .secondaryLabelColor
        frameHint.preferredMaxLayoutWidth = 340
        stack.addArrangedSubview(frameHint)

        stack.addArrangedSubview(Self.sectionLabel("Guides"))
        stack.addArrangedSubview(CheckboxControl(title: "Show guides", isOn: settings.showGuides) { settings.showGuides = $0 })
        let guideTypeNames = ["Thirds", "Quarters", "Custom Margins"]
        stack.addArrangedSubview(Self.row(title: "Type", control: ChoicePicker(options: guideTypeNames, selected: guideTypeNames[settings.guidelineType - 1]) { value in
            settings.guidelineType = (guideTypeNames.firstIndex(of: value) ?? 2) + 1
        }))
        stack.addArrangedSubview(Self.row(title: "Color", control: ColorWell(color: settings.guideColor) { settings.guideColor = $0 }))
        stack.addArrangedSubview(Self.row(title: "Top indent (px)", control: NumberField(value: settings.guideTopIndent) { settings.guideTopIndent = max(0, $0) }))
        stack.addArrangedSubview(Self.row(title: "Bottom indent (px)", control: NumberField(value: settings.guideBottomIndent) { settings.guideBottomIndent = max(0, $0) }))
        stack.addArrangedSubview(Self.row(title: "Left indent (px)", control: NumberField(value: settings.guideLeftIndent) { settings.guideLeftIndent = max(0, $0) }))
        stack.addArrangedSubview(Self.row(title: "Right indent (px)", control: NumberField(value: settings.guideRightIndent) { settings.guideRightIndent = max(0, $0) }))
        let guideHint = NSTextField(wrappingLabelWithString: "Indents only apply to the Custom Margins type. Guides are a view-only aid — never included in the captured image.")
        guideHint.font = .systemFont(ofSize: 11)
        guideHint.textColor = .secondaryLabelColor
        guideHint.preferredMaxLayoutWidth = 340
        stack.addArrangedSubview(guideHint)

        stack.addArrangedSubview(Self.sectionLabel("Numbers"))
        stack.addArrangedSubview(Self.row(title: "Color", control: ColorWell(color: settings.numberColor) { settings.numberColor = $0 }))
        stack.addArrangedSubview(Self.row(title: "Font size (px)", control: NumberField(value: settings.numberFontSize) { settings.numberFontSize = max(6, $0) }))
        stack.addArrangedSubview(Self.row(title: "Font family", control: FontPicker(selectedFamily: settings.numberFontFamily) { settings.numberFontFamily = $0 }))

        stack.addArrangedSubview(Self.sectionLabel("Sizes"))
        for i in 0..<settings.presetSizes.count {
            stack.addArrangedSubview(Self.sizeRow(settings: settings, index: i))
        }
        let sizesHint = NSTextField(labelWithString: "The 4 presets applied by ⌥1-4 and the resolution-cycle button.")
        sizesHint.font = .systemFont(ofSize: 11)
        sizesHint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(sizesHint)

        stack.addArrangedSubview(Self.sectionLabel("Watermark"))
        stack.addArrangedSubview(Self.stubNote())

        stack.addArrangedSubview(Self.sectionLabel("Appearance"))
        stack.addArrangedSubview(Self.row(title: "Panel color (chrome)", control: ColorWell(color: settings.chromeColor) { settings.chromeColor = $0 }))
        stack.addArrangedSubview(CheckboxControl(title: "Clear elements after screenshot", isOn: settings.clearElementsAfterCapture) { settings.clearElementsAfterCapture = $0 })
        stack.addArrangedSubview(CheckboxControl(title: "DPI Scale", isOn: settings.dpiScale) { settings.dpiScale = $0 })
        let dpiHint = NSTextField(wrappingLabelWithString: "When on, the saved/copied image always matches the size shown exactly in pixels, regardless of Retina scale. When off, it keeps the display's native pixel density.")
        dpiHint.font = .systemFont(ofSize: 11)
        dpiHint.textColor = .secondaryLabelColor
        dpiHint.preferredMaxLayoutWidth = 340
        stack.addArrangedSubview(dpiHint)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = container
        container.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true

        let footer = buildFooter()

        let root = NSView()
        root.addSubview(scrollView)
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        contentView = root
    }

    // MARK: - Footer: profile Save as/Load/Delete/Reset, matching the original

    private func buildFooter() -> NSView {
        let settings = AppSettings.shared

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.addItems(withTitles: settings.profileNames)
        popup.selectItem(withTitle: settings.currentProfileName)
        profilePopup = popup

        let profileLabel = NSTextField(labelWithString: "Profile:")
        let profileRow = NSStackView(views: [profileLabel, popup])
        profileRow.orientation = .horizontal
        profileRow.spacing = 8

        let resetButton = ActionButton(title: "Reset") { [weak self] in
            AppSettings.shared.resetToDefaults()
            self?.rebuildContent()
        }
        let loadButton = ActionButton(title: "Load") { [weak self] in
            guard let name = self?.profilePopup.titleOfSelectedItem else { return }
            AppSettings.shared.loadProfile(named: name)
            self?.rebuildContent()
        }
        let saveButton = ActionButton(title: "Save as...") { [weak self] in
            self?.promptSaveProfile()
        }
        let deleteButton = ActionButton(title: "Delete") { [weak self] in
            guard let name = self?.profilePopup.titleOfSelectedItem, name != "default" else { return }
            AppSettings.shared.deleteProfile(named: name)
            self?.rebuildContent()
        }
        let okButton = ActionButton(title: "OK") { [weak self] in
            self?.close()
        }

        let buttonRow = NSStackView(views: [resetButton, loadButton, saveButton, deleteButton, okButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let footerStack = NSStackView(views: [profileRow, buttonRow])
        footerStack.orientation = .vertical
        footerStack.alignment = .centerX
        footerStack.spacing = 10
        footerStack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 16, right: 20)
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSStackView(views: [divider, footerStack])
        wrapper.orientation = .vertical
        wrapper.spacing = 0
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalTo: wrapper.widthAnchor).isActive = true
        return wrapper
    }

    private func promptSaveProfile() {
        let alert = NSAlert()
        alert.messageText = "Save Profile"
        alert.informativeText = "Enter a name for this profile:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        AppSettings.shared.saveProfile(named: name)
        profilePopup.removeAllItems()
        profilePopup.addItems(withTitles: AppSettings.shared.profileNames)
        profilePopup.selectItem(withTitle: name)
    }

    // MARK: - Row builders

    private static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private static func stubNote() -> NSView {
        let label = NSTextField(labelWithString: "Not implemented yet")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private static func row(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private static func sizeRow(settings: AppSettings, index: Int) -> NSView {
        let size = settings.presetSizes[index]

        let label = NSTextField(labelWithString: "Preset \(index + 1)")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let widthField = NumberField(value: size.width) { newWidth in
            var sizes = settings.presetSizes
            guard sizes.indices.contains(index) else { return }
            sizes[index].width = newWidth
            settings.presetSizes = sizes
        }
        let xLabel = NSTextField(labelWithString: "×")
        let heightField = NumberField(value: size.height) { newHeight in
            var sizes = settings.presetSizes
            guard sizes.indices.contains(index) else { return }
            sizes[index].height = newHeight
            settings.presetSizes = sizes
        }

        let row = NSStackView(views: [label, widthField, xLabel, heightField])
        row.orientation = .horizontal
        row.spacing = 6
        return row
    }
}
