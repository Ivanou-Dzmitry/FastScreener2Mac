import AppKit

// Ported from FSUtils.PromptForText: middle-click with the Text tool
// opens this modal dialog to type text, pick a color/font, and place
// it at the click point on OK. Unlike Arrow/Frame/Number, the original
// only ever keeps ONE text on screen — placing a new one replaces the
// old (handled by the caller in CaptureFrameView, not here).
//
// The original used Windows' ColorDialog/FontDialog; this uses the
// native NSColorPanel/NSFontPanel instead, which is the closer match
// to how a Mac app actually offers color/font pickers.
@MainActor
final class TextToolDialog: NSObject {
    private var panel: NSPanel!
    private var textField: NSTextField!
    private var infoLabel: NSTextField!
    private var currentColor: NSColor = .black
    private var currentFontFamily: String = ""
    private var currentFontSize: CGFloat = 26
    private var result: String?

    static func prompt(over parentWindow: NSWindow, initialText: String) -> String? {
        let dialog = TextToolDialog()
        return dialog.run(over: parentWindow, initialText: initialText)
    }

    private func run(over parentWindow: NSWindow, initialText: String) -> String? {
        let settings = AppSettings.shared
        currentColor = settings.textColor
        currentFontFamily = settings.textFontFamily
        currentFontSize = settings.textFontSize

        buildUI(initialText: initialText)
        updateInfoLabel()

        panel.center()
        NSApp.runModal(for: panel)
        return result
    }

    private func buildUI(initialText: String) {
        let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.title = "Text (45 symbols)"
        p.isReleasedWhenClosed = false
        p.level = .modalPanel

        textField = NSTextField(frame: CGRect(x: 20, y: 155, width: 360, height: 24))
        textField.placeholderString = "Input text..."
        textField.stringValue = initialText
        textField.delegate = self
        p.contentView?.addSubview(textField)

        let colorButton = ActionButton(title: "Color") { [weak self] in self?.pickColor() }
        colorButton.frame = CGRect(x: 20, y: 115, width: 90, height: 28)
        p.contentView?.addSubview(colorButton)

        let fontButton = ActionButton(title: "Font") { [weak self] in self?.pickFont() }
        fontButton.frame = CGRect(x: 120, y: 115, width: 90, height: 28)
        p.contentView?.addSubview(fontButton)

        infoLabel = NSTextField(labelWithString: "")
        infoLabel.frame = CGRect(x: 20, y: 75, width: 260, height: 20)
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.drawsBackground = true
        p.contentView?.addSubview(infoLabel)

        let okButton = ActionButton(title: "OK") { [weak self] in self?.okClicked() }
        okButton.frame = CGRect(x: 290, y: 20, width: 90, height: 32)
        okButton.keyEquivalent = "\r"
        p.contentView?.addSubview(okButton)

        let cancelButton = ActionButton(title: "Cancel") { [weak self] in self?.cancelClicked() }
        cancelButton.frame = CGRect(x: 195, y: 20, width: 90, height: 32)
        cancelButton.keyEquivalent = "\u{1b}"
        p.contentView?.addSubview(cancelButton)

        panel = p
    }

    private func okClicked() {
        let text = String(textField.stringValue.prefix(Self.maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        result = text.isEmpty ? nil : text
        finish()
    }

    private func cancelClicked() {
        result = nil
        finish()
    }

    private func finish() {
        NSColorPanel.shared.close()
        NSFontPanel.shared.close()
        NSApp.stopModal()
        panel.orderOut(nil)
    }

    static let maxLength = 45

    // Color/Font choices persist to AppSettings the instant they
    // change, independent of the final OK/Cancel — matches the
    // original writing FS2SettingsManager.textColor/textFont directly
    // inside each picker's own change handler.
    private func pickColor() {
        let cp = NSColorPanel.shared
        cp.setTarget(self)
        cp.setAction(#selector(colorChanged(_:)))
        cp.color = currentColor
        cp.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        currentColor = sender.color
        AppSettings.shared.textColor = currentColor
        updateInfoLabel()
    }

    private func pickFont() {
        let fm = NSFontManager.shared
        fm.target = self
        fm.action = #selector(changeFont(_:))
        let font = NSFont(name: currentFontFamily, size: currentFontSize) ?? NSFont.systemFont(ofSize: currentFontSize)
        NSFontPanel.shared.setPanelFont(font, isMultiple: false)
        fm.orderFrontFontPanel(nil)
    }

    @objc private func changeFont(_ sender: NSFontManager) {
        let base = NSFont(name: currentFontFamily, size: currentFontSize) ?? NSFont.systemFont(ofSize: currentFontSize)
        let newFont = sender.convert(base)
        currentFontFamily = newFont.fontName
        currentFontSize = newFont.pointSize
        AppSettings.shared.textFontFamily = currentFontFamily
        AppSettings.shared.textFontSize = currentFontSize
        updateInfoLabel()
    }

    private func updateInfoLabel() {
        let familyLabel = currentFontFamily.isEmpty ? "System Default" : currentFontFamily
        infoLabel.stringValue = "Font (size, family): \(Int(currentFontSize)), \(familyLabel)"
        infoLabel.textColor = currentColor
        infoLabel.backgroundColor = currentColor.invertedForBackground
    }
}

extension TextToolDialog: NSTextFieldDelegate {
    func controlTextDidChange(_ obligatory: Notification) {
        if textField.stringValue.count > Self.maxLength {
            textField.stringValue = String(textField.stringValue.prefix(Self.maxLength))
        }
    }
}

private extension NSColor {
    // Matches the original's InvertColor: a simple per-component
    // 255-minus inversion, used as the info label's background so the
    // chosen text color always stays legible against it.
    var invertedForBackground: NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else { return .white }
        return NSColor(calibratedRed: 1 - rgb.redComponent, green: 1 - rgb.greenComponent, blue: 1 - rgb.blueComponent, alpha: 1)
    }
}
