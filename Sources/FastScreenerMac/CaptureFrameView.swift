import AppKit
import Carbon.HIToolbox

// The whole window's content view. Bounds = chrome (top bar, left bar,
// bottom bar) + the interior capture rect, matching the original
// FastScreener2 layout: dashed-outlined capture area in the middle,
// hamburger/capture/filename/close along the top, tool icons down the
// left, status text along the bottom. Only the interior rect is ever
// captured — the window itself is excluded from ScreenCaptureKit's
// output, so all this chrome never leaks into a screenshot regardless
// of where it's drawn.
final class CaptureFrameView: NSView {
    static let topBarHeight: CGFloat = 28
    static let leftBarWidth: CGFloat = 32
    static let rightBarWidth: CGFloat = 32
    static let bottomBarHeight: CGFloat = 20
    static let filenameMaxLength = 42

    private let snapMargin: CGFloat = 8
    private let borderWidth: CGFloat = 1.5
    private let borderColor = NSColor.black
    private let settings = AppSettings.shared
    // The two icon clusters (hamburger/capture/resolution-cycle, and
    // settings/minimize/close) always sit on this fixed grey, independent
    // of the user-configurable Panel Color (chromeColor). Inset from the
    // window's outer edge by leftBarWidth/rightBarWidth, so the margin
    // reads as deliberate rather than the icons just sitting flush
    // against the edge.
    private let fixedControlBackground = NSColor(calibratedWhite: 0.4, alpha: 1)
    private let iconClusterInset: CGFloat = CaptureFrameView.leftBarWidth
    private let iconClusterWidth: CGFloat = 78

    private enum DragMode {
        case none
        case move(offset: CGPoint)
    }
    private var dragMode: DragMode = .none

    var currentTool: AnnotationTool = .arrow {
        didSet {
            needsDisplay = true
            updateToolButtonHighlight()
        }
    }
    var annotations: [Annotation] = [] { didSet { needsDisplay = true } }
    private var nextNumber = 1
    private var pendingStart: CGPoint? // frame drag start
    private var pendingCurrent: CGPoint? // frame drag current / arrow drag current
    private var arrowAnchor: CGPoint? // arrow's fixed end point (the click location)
    private var lastArrowDirection = 1 // 1=↗ 2=↘ 3=↙ 4=↖, persists as the default for plain clicks

    // Alt+1..4 apply these (settings.presetSizes, editable in Settings >
    // Sizes), Alt+5 is fullscreen, Ctrl+Right cycles them.
    private var presets: [CGSize] { settings.presetSizes }
    private var currentPresetIndex = 0
    private var preMaxFrame: CGRect?

    var onCaptureRequested: (() -> Void)?
    var onSettingsRequested: (() -> Void)?
    var onOpenFolderRequested: (() -> Void)?
    private var filenameField: NSTextField!
    var filenameOverride: String { filenameField.stringValue }

    private var hamburgerButton: IconButton!
    private var toolButtons: [AnnotationTool: IconButton] = [:]
    private var saveToDiskButton: IconButton!

    override var acceptsFirstResponder: Bool { true }

    var captureRect: CGRect {
        CGRect(
            x: Self.leftBarWidth,
            y: Self.bottomBarHeight,
            width: max(0, bounds.width - Self.leftBarWidth - Self.rightBarWidth),
            height: max(0, bounds.height - Self.topBarHeight - Self.bottomBarHeight)
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupChrome()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Bottom bar is intentionally NOT filled across its full width:
        // only the left segment (under the left toolbar) is opaque
        // chrome; the rest stays fully transparent (shows through to
        // whatever's beneath), with the status text floating on top of
        // that transparent area when Show Info is on.
        settings.chromeColor.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: bounds.height - Self.topBarHeight, width: bounds.width, height: Self.topBarHeight)).fill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: Self.leftBarWidth, height: bounds.height)).fill()
        NSBezierPath(rect: CGRect(x: bounds.width - Self.rightBarWidth, y: 0, width: Self.rightBarWidth, height: bounds.height)).fill()

        // Both icon clusters (hamburger/capture/resolution-cycle on the
        // left, settings/minimize/close on the right) always sit on
        // fixed grey, unaffected by Panel Color — painted over the
        // chrome fill in just those two top-bar slices.
        fixedControlBackground.setFill()
        NSBezierPath(rect: CGRect(x: iconClusterInset, y: bounds.height - Self.topBarHeight, width: iconClusterWidth, height: Self.topBarHeight)).fill()
        NSBezierPath(rect: CGRect(x: bounds.width - iconClusterInset - iconClusterWidth, y: bounds.height - Self.topBarHeight, width: iconClusterWidth, height: Self.topBarHeight)).fill()

        for annotation in annotations {
            drawAnnotation(annotation)
        }
        drawPendingPreview()

        let rect = captureRect
        let borderPath = NSBezierPath(rect: rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
        borderPath.lineWidth = borderWidth
        borderColor.setStroke()
        borderPath.stroke()

        drawStatusText()
    }

    private func drawAnnotation(_ annotation: Annotation) {
        switch annotation {
        case .arrow:
            annotation.draw(color: settings.arrowColor, lineWidth: settings.arrowWidth)
        case .frame:
            annotation.draw(color: settings.frameColor, lineWidth: settings.frameStrokeWidth)
        case .number:
            annotation.draw(color: settings.numberColor, fontSize: settings.numberFontSize, fontFamily: settings.numberFontFamily)
        }
    }

    private func drawPendingPreview() {
        if let anchor = arrowAnchor, let current = pendingCurrent, currentTool == .arrow {
            let direction = snappedArrowDirection(from: anchor, to: current)
            let (start, end) = arrowPoints(anchor: anchor, direction: direction, length: settings.arrowLength)
            Annotation.arrow(start: start, end: end).draw(color: settings.arrowColor.withAlphaComponent(0.6), lineWidth: settings.arrowWidth)
        }
        if let start = pendingStart, let current = pendingCurrent, currentTool == .frame {
            let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
            Annotation.frame(rect: rect).draw(color: settings.frameColor.withAlphaComponent(0.6), lineWidth: settings.frameStrokeWidth)
        }
    }

    private func drawStatusText() {
        guard settings.showInfoLabel else { return }
        let origin = window?.frame.origin ?? .zero
        let rect = captureRect
        // Matches the original's "Size W: 975 (650)" format: the native
        // display pixels the capture is actually grabbed at (real, before
        // any DPI correction) with the target point size — what the file
        // will actually be once DPI Scale downsamples it — in parens.
        // Always shows the real scale factor's effect, regardless of
        // whether DPI Scale is currently on or off.
        let scale = window?.backingScaleFactor ?? 1
        let nativeW = Int((rect.width * scale).rounded())
        let nativeH = Int((rect.height * scale).rounded())
        let text = "Pos:(\(Int(origin.x)),\(Int(origin.y)))  Size W: \(nativeW) (\(Int(rect.width))), H: \(nativeH) (\(Int(rect.height)))  Elements:\(annotations.count)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1),
            .backgroundColor: NSColor.black.withAlphaComponent(0.55),
        ]
        // Centered within the transparent middle segment of the bottom
        // bar (between the left toolbar and the right bar), not
        // left-aligned right after the left bar.
        let size = text.size(withAttributes: attrs)
        let zoneMinX = Self.leftBarWidth
        let zoneMaxX = bounds.width - Self.rightBarWidth
        let x = zoneMinX + (zoneMaxX - zoneMinX - size.width) / 2
        text.draw(at: CGPoint(x: x, y: 4), withAttributes: attrs)
    }

    // MARK: - Chrome setup

    private func setupChrome() {
        let topY = bounds.height - Self.topBarHeight

        // Left-to-right: hamburger, capture, resolution-cycle, filename,
        // [gap], settings, minimize, close. The two icon clusters sit
        // inside their fixed-grey zones (iconClusterInset/Width above),
        // not flush against the window edge.
        let leftZoneX = iconClusterInset
        hamburgerButton = IconButton(icon: IconLoader.load("menu_icon"), frame: CGRect(x: leftZoneX, y: topY + 3, width: 22, height: 22))
        hamburgerButton.autoresizingMask = [.minYMargin]
        hamburgerButton.onClick = { [weak self] in self?.showMenu() }
        addSubview(hamburgerButton)

        let captureButton = IconButton(icon: IconLoader.load("screen_icon"), frame: CGRect(x: leftZoneX + 26, y: topY + 3, width: 22, height: 22))
        captureButton.autoresizingMask = [.minYMargin]
        captureButton.onClick = { [weak self] in self?.onCaptureRequested?() }
        addSubview(captureButton)

        let resCycleButton = IconButton(icon: IconLoader.load("res_cycle_icon"), frame: CGRect(x: leftZoneX + 52, y: topY + 3, width: 22, height: 22))
        resCycleButton.autoresizingMask = [.minYMargin]
        resCycleButton.onClick = { [weak self] in self?.cyclePreset() }
        addSubview(resCycleButton)

        // Fixed width sized to comfortably hold filenameMaxLength (42)
        // characters at this font — genuinely fixed, not derived from
        // bounds.width at setup time: since the window's initial size
        // can now be a restored (possibly large, e.g. Max Size) frame
        // via setFrameAutosaveName, a width computed from bounds.width
        // here would permanently bake in whatever that happened to be.
        let filenameX = leftZoneX + iconClusterWidth + 4
        let rightZoneX = bounds.width - iconClusterInset - iconClusterWidth
        filenameField = NSTextField(frame: CGRect(x: filenameX, y: topY + 4, width: 260, height: 20))
        filenameField.placeholderString = "File name (\(Self.filenameMaxLength) symbols, optional)"
        filenameField.font = .systemFont(ofSize: 11)
        filenameField.autoresizingMask = [.minYMargin]
        filenameField.usesSingleLineMode = true
        filenameField.delegate = self
        addSubview(filenameField)

        let settingsButton = IconButton(icon: IconLoader.load("settings_icon"), frame: CGRect(x: rightZoneX, y: topY + 3, width: 22, height: 22))
        settingsButton.autoresizingMask = [.minXMargin, .minYMargin]
        settingsButton.onClick = { [weak self] in self?.onSettingsRequested?() }
        addSubview(settingsButton)

        let minimizeButton = IconButton(icon: IconLoader.load("minimize_icon"), frame: CGRect(x: rightZoneX + 26, y: topY + 3, width: 22, height: 22))
        minimizeButton.autoresizingMask = [.minXMargin, .minYMargin]
        minimizeButton.onClick = { [weak self] in self?.window?.miniaturize(nil) }
        addSubview(minimizeButton)

        let closeButton = IconButton(icon: IconLoader.load("close_icon"), frame: CGRect(x: rightZoneX + 52, y: topY + 3, width: 22, height: 22))
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.onClick = { NSApplication.shared.terminate(nil) }
        addSubview(closeButton)

        // Anchored to the bottom of the left bar (just above the status
        // bar), not the top: .maxYMargin in autoresizingMask leaves the
        // margin *above* the button flexible and the margin *below* it
        // fixed, which pins it to the bottom as the window resizes.
        // Each button always shows its grey chip, not just when active.
        let toolIcons: [(AnnotationTool, String)] = [
            (.arrow, "arrow_icon"),
            (.frame, "frame_icon"),
            (.number, "number_icon"),
        ]
        let totalSlots = toolIcons.count + 1 // +1 for the Save-to-Disk toggle below
        let groupBottom = Self.bottomBarHeight + 8
        for (index, pair) in toolIcons.enumerated() {
            let (tool, iconName) = pair
            let reverseIndex = totalSlots - 1 - index
            let y = groupBottom + CGFloat(reverseIndex) * 30
            let button = IconButton(icon: IconLoader.load(iconName), frame: CGRect(x: 4, y: y, width: Self.leftBarWidth - 8, height: 24), showsBackgroundWhenInactive: true)
            button.autoresizingMask = [.maxYMargin]
            button.onClick = { [weak self] in self?.currentTool = tool }
            addSubview(button)
            toolButtons[tool] = button
        }

        // Save-to-Disk toggle: same on/off flag as the hamburger menu's
        // "Save to File" item — active (blue) means F4 also writes a
        // PNG to disk, inactive means clipboard only.
        saveToDiskButton = IconButton(icon: IconLoader.load("save_icon"), frame: CGRect(x: 4, y: groupBottom, width: Self.leftBarWidth - 8, height: 24), showsBackgroundWhenInactive: true)
        saveToDiskButton.autoresizingMask = [.maxYMargin]
        saveToDiskButton.isActive = settings.saveToFile
        saveToDiskButton.onClick = { [weak self] in
            guard let self else { return }
            self.settings.saveToFile.toggle()
            self.saveToDiskButton.isActive = self.settings.saveToFile
        }
        addSubview(saveToDiskButton)

        updateToolButtonHighlight()
    }

    private func updateToolButtonHighlight() {
        for (tool, button) in toolButtons {
            button.isActive = (tool == currentTool)
        }
    }

    // MARK: - Menu

    // Mirrors the original's hamburger menu structure/order exactly.
    // Everything wired to a working feature is live; everything else
    // (Text, Watermark, Guidelines, Help) is a disabled stub, since
    // those tools aren't built yet.
    private func showMenu() {
        let menu = NSMenu()

        for i in 0..<presets.count {
            let size = presets[i]
            menu.addItem(ClosureMenuItem(title: "\(Int(size.width))×\(Int(size.height))  (⌥\(i + 1))") { [weak self] in self?.applyPreset(i) })
        }
        menu.addItem(ClosureMenuItem(title: "Max Size  (⌃⇧M)") { [weak self] in self?.toggleMax() })
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem(title: "Screenshot  (F4)") { [weak self] in self?.onCaptureRequested?() })
        menu.addItem(ClosureMenuItem(title: "Fullscreen  (⌥5)") { [weak self] in self?.applyFullscreen() })
        menu.addItem(ClosureMenuItem(title: "Clear  (⌘⇧Z)") { [weak self] in self?.clearAll() })
        let undoItem = ClosureMenuItem(title: "Undo  (⌘Z)") { [weak self] in self?.undo() }
        undoItem.isEnabled = !annotations.isEmpty
        menu.addItem(undoItem)
        menu.addItem(.separator())

        for (title, tool) in [("Arrow", AnnotationTool.arrow), ("Frame", .frame), ("Number", .number)] {
            let item = ClosureMenuItem(title: title) { [weak self] in self?.currentTool = tool }
            item.state = (tool == currentTool) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(Self.stub("Text"))
        menu.addItem(Self.stub("Watermark"))
        menu.addItem(.separator())

        menu.addItem(Self.stub("Guidelines"))
        let saveToFileItem = ClosureMenuItem(title: "Save to File") { [weak self] in
            guard let self else { return }
            self.settings.saveToFile.toggle()
            self.saveToDiskButton.isActive = self.settings.saveToFile
        }
        saveToFileItem.state = settings.saveToFile ? .on : .off
        menu.addItem(saveToFileItem)
        menu.addItem(ClosureMenuItem(title: "Open Folder with Files") { [weak self] in self?.onOpenFolderRequested?() })
        menu.addItem(.separator())

        let showInfoItem = ClosureMenuItem(title: "Show Info") { [weak self] in
            self?.settings.showInfoLabel.toggle()
            self?.needsDisplay = true
        }
        showInfoItem.state = settings.showInfoLabel ? .on : .off
        menu.addItem(showInfoItem)
        menu.addItem(ClosureMenuItem(title: "Settings") { [weak self] in self?.onSettingsRequested?() })
        menu.addItem(Self.stub("Help  (F1)"))
        menu.addItem(ClosureMenuItem(title: "Exit") { NSApplication.shared.terminate(nil) })

        menu.popUp(positioning: nil, at: CGPoint(x: hamburgerButton.frame.minX, y: hamburgerButton.frame.minY), in: self)
    }

    private static func stub(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Left button: resize / move

    // Size only ever changes via menu/hotkey/resolution-cycle button —
    // dragging the frame just moves it, no edge/corner resize handles.
    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        let winOrigin = window.frame.origin
        let mouseLoc = NSEvent.mouseLocation
        dragMode = .move(offset: CGPoint(x: mouseLoc.x - winOrigin.x, y: mouseLoc.y - winOrigin.y))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window, case .move(let offset) = dragMode else { return }
        let mouseLoc = NSEvent.mouseLocation
        let newOrigin = snappedOrigin(
            CGPoint(x: mouseLoc.x - offset.x, y: mouseLoc.y - offset.y),
            size: window.frame.size
        )
        window.setFrameOrigin(newOrigin)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
    }

    // MARK: - Middle button: annotations (only within the capture rect)
    //
    // Arrow: length is always the fixed configured length — dragging only
    // picks which of the 4 diagonal directions it points, snapped to the
    // nearest, matching the original's fixed-length/4-direction arrows.
    // Frame: a plain click (drag below frameClickThreshold) places a
    // fixed-size box (from settings) centered on the click; dragging
    // beyond that draws a free-size box instead.

    private let frameClickThreshold: CGFloat = 24

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard captureRect.contains(p) else { return }

        switch currentTool {
        case .arrow:
            arrowAnchor = p
            pendingCurrent = p
        case .frame:
            pendingStart = p
            pendingCurrent = p
        case .number:
            annotations.append(.number(point: p, value: nextNumber))
            nextNumber += 1
        case .none:
            break
        }
        needsDisplay = true
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard pendingStart != nil || arrowAnchor != nil else { return }
        pendingCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func otherMouseUp(with event: NSEvent) {
        defer {
            pendingStart = nil
            pendingCurrent = nil
            arrowAnchor = nil
            needsDisplay = true
        }
        let end = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .arrow:
            guard let anchor = arrowAnchor else { return }
            let direction = snappedArrowDirection(from: anchor, to: end)
            let (start, arrowEnd) = arrowPoints(anchor: anchor, direction: direction, length: settings.arrowLength)
            lastArrowDirection = direction
            annotations.append(.arrow(start: start, end: arrowEnd))

        case .frame:
            guard let start = pendingStart else { return }
            if hypot(end.x - start.x, end.y - start.y) < frameClickThreshold {
                let w = settings.frameFixedWidth
                let h = settings.frameFixedHeight
                annotations.append(.frame(rect: CGRect(x: start.x - w / 2, y: start.y - h / 2, width: w, height: h)))
            } else {
                let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                annotations.append(.frame(rect: rect))
            }

        case .none, .number:
            break
        }
    }

    // 1=↗ 2=↘ 3=↙ 4=↖, snapped to the nearest of these 4 diagonals.
    private func snappedArrowDirection(from anchor: CGPoint, to current: CGPoint) -> Int {
        let dx = current.x - anchor.x
        let dy = current.y - anchor.y
        guard hypot(dx, dy) > 6 else { return lastArrowDirection }

        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }

        let candidates: [(angle: Double, direction: Int)] = [(45, 1), (135, 4), (225, 3), (315, 2)]
        return candidates.min { angleDelta($0.angle, angle) < angleDelta($1.angle, angle) }!.direction
    }

    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return d
    }

    private func arrowPoints(anchor: CGPoint, direction: Int, length: CGFloat) -> (start: CGPoint, end: CGPoint) {
        let start: CGPoint
        switch direction {
        case 1: start = CGPoint(x: anchor.x - length, y: anchor.y - length) // ↗
        case 2: start = CGPoint(x: anchor.x - length, y: anchor.y + length) // ↘
        case 3: start = CGPoint(x: anchor.x + length, y: anchor.y + length) // ↙
        default: start = CGPoint(x: anchor.x + length, y: anchor.y - length) // ↖
        }
        return (start, anchor)
    }

    // MARK: - Keyboard: tool switching, undo/clear, size presets

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers

        if mods == [.command], chars == "z" { undo(); return }
        if mods == [.command, .shift], chars == "z" { clearAll(); return }

        if mods == [.option] {
            switch Int(event.keyCode) {
            case kVK_ANSI_1: applyPreset(0); return
            case kVK_ANSI_2: applyPreset(1); return
            case kVK_ANSI_3: applyPreset(2); return
            case kVK_ANSI_4: applyPreset(3); return
            case kVK_ANSI_5: applyFullscreen(); return
            default: break
            }
        }
        if mods == [.control], Int(event.keyCode) == kVK_RightArrow {
            cyclePreset()
            return
        }
        if mods == [.control, .shift], chars?.lowercased() == "m" {
            toggleMax()
            return
        }
        if mods.isEmpty {
            switch chars {
            case "1": currentTool = .arrow; return
            case "2": currentTool = .frame; return
            case "3": currentTool = .number; return
            case "0": currentTool = .none; return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    private func undo() {
        _ = annotations.popLast()
    }

    private func clearAll() {
        annotations.removeAll()
        nextNumber = 1
    }

    func clearAnnotations() {
        clearAll()
    }

    // MARK: - Size presets / fullscreen

    private func applyPreset(_ index: Int) {
        guard let window else { return }
        currentPresetIndex = index
        // presets[index] is the desired CAPTURE size (captureRect), not
        // the whole window — the window itself needs the chrome added
        // back on top, or the interior ends up smaller than requested.
        let captureSize = presets[index]
        let size = CGSize(
            width: captureSize.width + Self.leftBarWidth + Self.rightBarWidth,
            height: captureSize.height + Self.topBarHeight + Self.bottomBarHeight
        )
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        window.setFrame(clampToVirtualScreen(frame), display: true)
        preMaxFrame = nil
    }

    private func applyFullscreen() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        preMaxFrame = window.frame
        window.setFrame(screen.frame, display: true)
    }

    private func toggleMax() {
        guard let window else { return }
        if let prev = preMaxFrame {
            window.setFrame(prev, display: true)
            preMaxFrame = nil
        } else {
            applyFullscreen()
        }
    }

    private func cyclePreset() {
        currentPresetIndex = (currentPresetIndex + 1) % presets.count
        applyPreset(currentPresetIndex)
    }

    private func clampToVirtualScreen(_ frame: CGRect) -> CGRect {
        let screenFrame = virtualScreenFrame()
        var f = frame
        if f.width > screenFrame.width { f.size.width = screenFrame.width }
        if f.height > screenFrame.height { f.size.height = screenFrame.height }
        if f.minX < screenFrame.minX { f.origin.x = screenFrame.minX }
        if f.maxX > screenFrame.maxX { f.origin.x = screenFrame.maxX - f.width }
        if f.minY < screenFrame.minY { f.origin.y = screenFrame.minY }
        if f.maxY > screenFrame.maxY { f.origin.y = screenFrame.maxY - f.height }
        return f
    }

    // MARK: - Snapping (simplified: snaps to the union of all screens' bounds)

    private func virtualScreenFrame() -> CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    private func snappedOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let screenFrame = virtualScreenFrame()
        var o = origin
        if abs(o.x - screenFrame.minX) < snapMargin { o.x = screenFrame.minX }
        if abs((o.x + size.width) - screenFrame.maxX) < snapMargin { o.x = screenFrame.maxX - size.width }
        if abs(o.y - screenFrame.minY) < snapMargin { o.y = screenFrame.minY }
        if abs((o.y + size.height) - screenFrame.maxY) < snapMargin { o.y = screenFrame.maxY - size.height }
        return o
    }
}

extension CaptureFrameView: NSTextFieldDelegate {
    func controlTextDidChange(_ obligatory: Notification) {
        if filenameField.stringValue.count > Self.filenameMaxLength {
            filenameField.stringValue = String(filenameField.stringValue.prefix(Self.filenameMaxLength))
        }
    }
}
