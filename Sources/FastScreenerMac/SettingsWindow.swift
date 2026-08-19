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

final class StringField: NSTextField, NSTextFieldDelegate {
    private let onChange: (String) -> Void

    init(value: String, placeholder: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 140).isActive = true
        stringValue = value
        placeholderString = placeholder
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func controlTextDidChange(_ obligatory: Notification) { onChange(stringValue) }
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

final class SettingsWindow: NSWindow {
    convenience init() {
        self.init(contentRect: CGRect(x: 0, y: 0, width: 340, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Settings"
        isReleasedWhenClosed = false
        level = .floating

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

        stack.addArrangedSubview(Self.sectionLabel("Frame"))
        stack.addArrangedSubview(Self.row(title: "Color", control: ColorWell(color: settings.frameColor) { settings.frameColor = $0 }))
        stack.addArrangedSubview(Self.row(title: "Stroke width (px, 1-10)", control: NumberField(value: settings.frameStrokeWidth) { settings.frameStrokeWidth = min(10, max(1, $0)) }))
        stack.addArrangedSubview(Self.row(title: "Fixed width (px, min 32)", control: NumberField(value: settings.frameFixedWidth) { settings.frameFixedWidth = max(32, $0) }))
        stack.addArrangedSubview(Self.row(title: "Fixed height (px, min 32)", control: NumberField(value: settings.frameFixedHeight) { settings.frameFixedHeight = max(32, $0) }))

        let frameHint = NSTextField(wrappingLabelWithString: "Fixed width/height is the box a plain middle-click places with the Frame tool; dragging still draws a free-size box.")
        frameHint.font = .systemFont(ofSize: 11)
        frameHint.textColor = .secondaryLabelColor
        frameHint.preferredMaxLayoutWidth = 280
        stack.addArrangedSubview(frameHint)

        stack.addArrangedSubview(Self.sectionLabel("Number"))
        stack.addArrangedSubview(Self.row(title: "Color", control: ColorWell(color: settings.numberColor) { settings.numberColor = $0 }))
        stack.addArrangedSubview(Self.row(title: "Font size (px)", control: NumberField(value: settings.numberFontSize) { settings.numberFontSize = max(6, $0) }))
        stack.addArrangedSubview(Self.row(title: "Font family (blank = default)", control: StringField(value: settings.numberFontFamily, placeholder: "System") { settings.numberFontFamily = $0 }))

        stack.addArrangedSubview(Self.sectionLabel("Panel"))
        stack.addArrangedSubview(Self.row(title: "Panel color (chrome)", control: ColorWell(color: settings.chromeColor) { settings.chromeColor = $0 }))
        stack.addArrangedSubview(CheckboxControl(title: "Clear elements after screenshot", isOn: settings.clearElementsAfterCapture) { settings.clearElementsAfterCapture = $0 })

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        contentView = container
    }

    private static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
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
}
