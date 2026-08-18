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
    static let bottomBarHeight: CGFloat = 20

    private let edgeMargin: CGFloat = 8
    // Must stay large enough that the left toolbar's 3 stacked buttons
    // (28pt top-bar gap + 3×30pt) never collide with the bottom bar.
    private let minSize: CGFloat = 200
    private let snapMargin: CGFloat = 8
    private let borderWidth: CGFloat = 1.5
    private let borderColor = NSColor.black
    private let annotationColor = NSColor.systemYellow
    private let chromeColor = NSColor(calibratedWhite: 0.1, alpha: 0.92)

    private enum DragMode {
        case none
        case move(offset: CGPoint)
        case resize(left: Bool, right: Bool, top: Bool, bottom: Bool, startFrame: CGRect, startPoint: CGPoint)
    }
    private var dragMode: DragMode = .none

    var currentTool: AnnotationTool = .arrow {
        didSet {
            needsDisplay = true
            onToolChanged?(currentTool)
        }
    }
    var onToolChanged: ((AnnotationTool) -> Void)?
    var annotations: [Annotation] = [] { didSet { needsDisplay = true } }
    private var nextNumber = 1
    private var pendingStart: CGPoint?
    private var pendingCurrent: CGPoint?

    // Alt+1..4 apply these, Alt+5 is fullscreen, Ctrl+Right cycles them.
    private let presets: [CGSize] = [
        CGSize(width: 800, height: 450),
        CGSize(width: 1280, height: 720),
        CGSize(width: 1920, height: 1080),
        CGSize(width: 640, height: 480),
    ]
    private var currentPresetIndex = 0
    private var preMaxFrame: CGRect?

    var onCaptureRequested: (() -> Void)?
    private var filenameField: NSTextField!
    var filenameOverride: String { filenameField.stringValue }

    private var hamburgerButton: IconButton!

    override var acceptsFirstResponder: Bool { true }

    var captureRect: CGRect {
        CGRect(
            x: Self.leftBarWidth,
            y: Self.bottomBarHeight,
            width: max(0, bounds.width - Self.leftBarWidth),
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
        chromeColor.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: bounds.height - Self.topBarHeight, width: bounds.width, height: Self.topBarHeight)).fill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: Self.leftBarWidth, height: bounds.height)).fill()
        NSBezierPath(rect: CGRect(x: Self.leftBarWidth, y: 0, width: bounds.width - Self.leftBarWidth, height: Self.bottomBarHeight)).fill()

        for annotation in annotations {
            annotation.draw(color: annotationColor)
        }
        drawPendingPreview()

        let rect = captureRect
        let borderPath = NSBezierPath(rect: rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
        borderPath.lineWidth = borderWidth
        borderColor.setStroke()
        borderPath.stroke()

        drawStatusText()
    }

    private func drawPendingPreview() {
        guard let start = pendingStart, let current = pendingCurrent else { return }
        let previewColor = annotationColor.withAlphaComponent(0.6)
        switch currentTool {
        case .arrow:
            Annotation.arrow(start: start, end: current).draw(color: previewColor)
        case .frame:
            let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
            Annotation.frame(rect: rect).draw(color: previewColor)
        case .none, .number:
            break
        }
    }

    private func drawStatusText() {
        let origin = window?.frame.origin ?? .zero
        let rect = captureRect
        let text = "Pos:(\(Int(origin.x)),\(Int(origin.y)))  Size:\(Int(rect.width))×\(Int(rect.height))  Elements:\(annotations.count)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1),
        ]
        text.draw(at: CGPoint(x: Self.leftBarWidth + 6, y: 4), withAttributes: attrs)
    }

    // MARK: - Chrome setup

    private func setupChrome() {
        let topY = bounds.height - Self.topBarHeight

        // Left-to-right: hamburger, capture, resolution-cycle, filename,
        // [gap], settings, minimize, close.
        hamburgerButton = IconButton(icon: IconLoader.load("menu_icon"), frame: CGRect(x: 3, y: topY + 3, width: 22, height: 22))
        hamburgerButton.autoresizingMask = [.minYMargin]
        hamburgerButton.onClick = { [weak self] in self?.showMenu() }
        addSubview(hamburgerButton)

        let captureButton = IconButton(icon: IconLoader.load("screen_icon"), frame: CGRect(x: 29, y: topY + 3, width: 22, height: 22))
        captureButton.autoresizingMask = [.minYMargin]
        captureButton.onClick = { [weak self] in self?.onCaptureRequested?() }
        addSubview(captureButton)

        let resCycleButton = IconButton(icon: IconLoader.load("res_cycle_icon"), frame: CGRect(x: 55, y: topY + 3, width: 22, height: 22))
        resCycleButton.autoresizingMask = [.minYMargin]
        resCycleButton.onClick = { [weak self] in self?.cyclePreset() }
        addSubview(resCycleButton)

        filenameField = NSTextField(frame: CGRect(x: 81, y: topY + 4, width: bounds.width - 81 - 81, height: 20))
        filenameField.placeholderString = "File name (optional)"
        filenameField.font = .systemFont(ofSize: 11)
        filenameField.autoresizingMask = [.width, .minYMargin]
        filenameField.usesSingleLineMode = true
        addSubview(filenameField)

        let closeButton = IconButton(icon: IconLoader.load("close_icon"), frame: CGRect(x: bounds.width - 25, y: topY + 3, width: 22, height: 22))
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.onClick = { NSApplication.shared.terminate(nil) }
        addSubview(closeButton)

        let minimizeButton = IconButton(icon: IconLoader.load("minimize_icon"), frame: CGRect(x: bounds.width - 51, y: topY + 3, width: 22, height: 22))
        minimizeButton.autoresizingMask = [.minXMargin, .minYMargin]
        minimizeButton.onClick = { [weak self] in self?.window?.miniaturize(nil) }
        addSubview(minimizeButton)

        let settingsButton = IconButton(icon: IconLoader.load("settings_icon"), frame: CGRect(x: bounds.width - 77, y: topY + 3, width: 22, height: 22))
        settingsButton.autoresizingMask = [.minXMargin, .minYMargin]
        settingsButton.onClick = { print("Settings: not built yet") }
        addSubview(settingsButton)
    }

    // MARK: - Menu

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
        menu.addItem(ClosureMenuItem(title: "Undo  (⌘Z)") { [weak self] in self?.undo() })
        menu.addItem(.separator())

        for (title, tool) in [("Arrow", AnnotationTool.arrow), ("Frame", .frame), ("Number", .number), ("None", .none)] {
            let item = ClosureMenuItem(title: title) { [weak self] in self?.currentTool = tool }
            item.state = (tool == currentTool) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem(title: "Quit") { NSApplication.shared.terminate(nil) })

        menu.popUp(positioning: nil, at: CGPoint(x: hamburgerButton.frame.minX, y: hamburgerButton.frame.minY), in: self)
    }

    // MARK: - Left button: resize / move

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        let p = convert(event.locationInWindow, from: nil)
        let rect = captureRect

        // Hit-test against the capture rect's own edges, not the outer
        // window bounds — the outer edges sit under the chrome buttons
        // (close, filename field, etc.), which intercept the click
        // before it ever reaches here.
        let nearLeft = abs(p.x - rect.minX) <= edgeMargin
        let nearRight = abs(p.x - rect.maxX) <= edgeMargin
        let nearTop = abs(p.y - rect.maxY) <= edgeMargin
        let nearBottom = abs(p.y - rect.minY) <= edgeMargin
        let inVerticalRange = p.y >= rect.minY - edgeMargin && p.y <= rect.maxY + edgeMargin
        let inHorizontalRange = p.x >= rect.minX - edgeMargin && p.x <= rect.maxX + edgeMargin

        let left = nearLeft && inVerticalRange
        let right = nearRight && inVerticalRange
        let top = nearTop && inHorizontalRange
        let bottom = nearBottom && inHorizontalRange

        if left || right || top || bottom {
            dragMode = .resize(left: left, right: right, top: top, bottom: bottom, startFrame: window.frame, startPoint: NSEvent.mouseLocation)
        } else {
            let winOrigin = window.frame.origin
            let mouseLoc = NSEvent.mouseLocation
            dragMode = .move(offset: CGPoint(x: mouseLoc.x - winOrigin.x, y: mouseLoc.y - winOrigin.y))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let mouseLoc = NSEvent.mouseLocation

        switch dragMode {
        case .move(let offset):
            let newOrigin = snappedOrigin(
                CGPoint(x: mouseLoc.x - offset.x, y: mouseLoc.y - offset.y),
                size: window.frame.size
            )
            window.setFrameOrigin(newOrigin)
            needsDisplay = true

        case .resize(let left, let right, let top, let bottom, let startFrame, let startPoint):
            let dx = mouseLoc.x - startPoint.x
            let dy = mouseLoc.y - startPoint.y
            var f = startFrame

            if left {
                let newX = min(startFrame.origin.x + dx, startFrame.maxX - minSize)
                f.size.width = startFrame.maxX - newX
                f.origin.x = newX
            } else if right {
                f.size.width = max(minSize, startFrame.width + dx)
            }

            if bottom {
                let newY = min(startFrame.origin.y + dy, startFrame.maxY - minSize)
                f.size.height = startFrame.maxY - newY
                f.origin.y = newY
            } else if top {
                f.size.height = max(minSize, startFrame.height + dy)
            }

            f = snappedResizeFrame(f, left: left, right: right, top: top, bottom: bottom)
            window.setFrame(f, display: true)

        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
    }

    override func resetCursorRects() {
        let rect = captureRect
        addCursorRect(NSRect(x: rect.minX, y: rect.maxY - edgeMargin, width: rect.width, height: edgeMargin * 2), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: rect.minX, y: rect.minY - edgeMargin, width: rect.width, height: edgeMargin * 2), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: rect.minX - edgeMargin, y: rect.minY, width: edgeMargin * 2, height: rect.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: rect.maxX - edgeMargin, y: rect.minY, width: edgeMargin * 2, height: rect.height), cursor: .resizeLeftRight)
    }

    // MARK: - Middle button: annotations (only within the capture rect)

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard captureRect.contains(p) else { return }

        switch currentTool {
        case .arrow, .frame:
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
        guard pendingStart != nil else { return }
        pendingCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func otherMouseUp(with event: NSEvent) {
        defer {
            pendingStart = nil
            pendingCurrent = nil
            needsDisplay = true
        }
        guard let start = pendingStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        guard hypot(end.x - start.x, end.y - start.y) > 4 else { return }

        switch currentTool {
        case .arrow:
            annotations.append(.arrow(start: start, end: end))
        case .frame:
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            annotations.append(.frame(rect: rect))
        case .none, .number:
            break
        }
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

    // MARK: - Size presets / fullscreen

    private func applyPreset(_ index: Int) {
        guard let window else { return }
        currentPresetIndex = index
        let size = presets[index]
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

    private func snappedResizeFrame(_ frame: CGRect, left: Bool, right: Bool, top: Bool, bottom: Bool) -> CGRect {
        let screenFrame = virtualScreenFrame()
        var f = frame
        if right, abs(f.maxX - screenFrame.maxX) < snapMargin {
            f.size.width = screenFrame.maxX - f.origin.x
        }
        if left, abs(f.minX - screenFrame.minX) < snapMargin {
            let delta = f.origin.x - screenFrame.minX
            f.origin.x -= delta
            f.size.width += delta
        }
        if top, abs(f.maxY - screenFrame.maxY) < snapMargin {
            f.size.height = screenFrame.maxY - f.origin.y
        }
        if bottom, abs(f.minY - screenFrame.minY) < snapMargin {
            let delta = f.origin.y - screenFrame.minY
            f.origin.y -= delta
            f.size.height += delta
        }
        return f
    }
}
