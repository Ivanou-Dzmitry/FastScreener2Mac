import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: CaptureWindow!
    var settingsWindow: SettingsWindow!
    var helpWindow: HelpWindow!

    static var capturesDirectory: URL { AppSettings.shared.saveFolderURL }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main!.frame
        // Only used when no autosaved window frame exists yet (first
        // launch, or after resetting) — setFrameUsingName below restores
        // whatever size/position was there when the app last closed, and
        // takes priority over this.
        let captureSize = AppSettings.shared.presetSizes.first ?? CGSize(width: 650, height: 366)
        let windowSize = CGSize(
            width: captureSize.width + CaptureFrameView.leftBarWidth + CaptureFrameView.rightBarWidth,
            height: captureSize.height + CaptureFrameView.topBarHeight + CaptureFrameView.bottomBarHeight
        )
        let origin = CGPoint(x: screen.midX - windowSize.width / 2, y: screen.midY - windowSize.height / 2)

        window = CaptureWindow(contentRect: CGRect(origin: origin, size: windowSize))
        if let frameView = window.contentView as? CaptureFrameView {
            frameView.onCaptureRequested = { [weak self] in self?.captureAndSave() }
            frameView.onSettingsRequested = { [weak self] in self?.showSettings() }
            frameView.onHelpRequested = { [weak self] in self?.showHelp() }
            frameView.onOpenFolderRequested = {
                let dir = AppDelegate.capturesDirectory
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                NSWorkspace.shared.open(dir)
            }
        }
        // Restores the last session's size + position if one was saved;
        // setFrameAutosaveName then keeps saving on every future move/resize.
        _ = window.setFrameUsingName("MainCaptureWindow")
        window.setFrameAutosaveName("MainCaptureWindow")
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        NSApp.activate(ignoringOtherApps: true)

        HotkeyManager.shared.register(keyCode: kVK_F4) { [weak self] in
            self?.captureAndSave()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showHelp() {
        if helpWindow == nil {
            helpWindow = HelpWindow()
        }
        helpWindow.center()
        helpWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func captureAndSave() {
        guard let window, let frameView = window.contentView as? CaptureFrameView else { return }
        let interior = frameView.captureRect
        let screenRect = CGRect(
            x: window.frame.origin.x + interior.origin.x,
            y: window.frame.origin.y + interior.origin.y,
            width: interior.width,
            height: interior.height
        )
        let excludedWindowNumbers = [window.windowNumber]
        let annotations = frameView.annotations
        let filenameOverride = frameView.filenameOverride
        let backingScale = window.backingScaleFactor

        Task {
            do {
                let rawImage = try await ScreenCapture.captureRect(screenRect, excludingWindowNumbers: excludedWindowNumbers)
                let finalImage = Self.composite(annotations: annotations, onto: rawImage, size: interior.size, offset: interior.origin)

                let settings = AppSettings.shared
                // DPI Scale (on by default, matches the original): the
                // raw capture is at the display's native pixel density
                // (e.g. 2x on Retina), so a 650x366 capture would
                // otherwise save as a 1300x732px file. This resamples
                // down to exactly interior.size in actual pixels when on,
                // so the size you set is always the size you get; off
                // keeps the display's native pixel density.
                let outputPixelSize = settings.dpiScale
                    ? interior.size
                    : CGSize(width: interior.width * backingScale, height: interior.height * backingScale)

                // Always render into an RGBA (alpha) context — Core
                // Graphics doesn't reliably support a live drawing
                // context backed by a tightly-packed no-alpha RGB
                // bitmap (a 3-byte-per-pixel target isn't a supported
                // CGBitmapContext pixel format), which is why 24bpp/JPEG
                // failed outright when rendered directly into one.
                guard let rgbaRep = Self.pixelExactBitmap(from: finalImage, pixelSize: outputPixelSize) else {
                    print("Capture failed: could not render output bitmap")
                    return
                }
                let exactImage = NSImage(size: outputPixelSize)
                exactImage.addRepresentation(rgbaRep)

                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([exactImage])

                // PNG 32bpp keeps alpha; 24bpp/8bpp both drop it (macOS
                // has no simple indexed-palette API to match Windows'
                // true 8bpp/256-color PNGs, so both fall back to plain
                // RGB). JPEG has no alpha channel either way. Alpha is
                // stripped as a separate raw-buffer copy afterward,
                // never by rendering directly into a no-alpha context.
                let isJPEG = settings.fileFormat == "jpg"
                let wantsAlpha = !isJPEG && settings.pngDepth == "32bpp"
                let outputRep = wantsAlpha ? rgbaRep : (Self.stripAlpha(from: rgbaRep) ?? rgbaRep)

                let fileData: Data?
                let ext: String
                if isJPEG {
                    let quality = Float(settings.jpegQuality) / 100
                    fileData = outputRep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: quality)])
                    ext = "jpg"
                } else {
                    fileData = outputRep.representation(using: .png, properties: [:])
                    ext = "png"
                }

                if settings.saveToFile, let data = fileData {
                    let trimmed = filenameOverride.trimmingCharacters(in: .whitespaces)
                    let name: String
                    if trimmed.isEmpty {
                        name = "FastScreener_\(Self.timestamp()).\(ext)"
                    } else {
                        name = trimmed.hasSuffix(".\(ext)") ? trimmed : "\(trimmed).\(ext)"
                    }
                    let dir = Self.capturesDirectory
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(name)
                    try data.write(to: url)
                    print("Captured (\(outputRep.pixelsWide)x\(outputRep.pixelsHigh)px, \(ext)) + copied to clipboard -> \(url.path)")
                } else {
                    print("Captured + copied to clipboard (file save off)")
                }

                if settings.clearElementsAfterCapture {
                    frameView.clearAnnotations()
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    // Renders `image` into an RGBA bitmap whose pixel dimensions exactly
    // equal `pixelSize` (rep.size set to match, so it's 1 point == 1
    // pixel), downsampling from whatever native resolution `image`
    // actually carries. Always alpha — see the no-alpha-context note
    // where this is called.
    private static func pixelExactBitmap(from image: NSImage, pixelSize: CGSize) -> NSBitmapImageRep? {
        let width = max(1, Int(pixelSize.width.rounded()))
        let height = max(1, Int(pixelSize.height.rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = CGSize(width: width, height: height)

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // Converts an RGBA rep to plain RGB by copying the raw pixel bytes
    // and dropping the alpha byte per pixel — a memory copy, not a
    // drawing operation, so it doesn't hit the no-alpha-context
    // limitation that made rendering directly into an alpha-less
    // bitmap fail.
    private static func stripAlpha(from rgba: NSBitmapImageRep) -> NSBitmapImageRep? {
        let width = rgba.pixelsWide
        let height = rgba.pixelsHigh
        guard let src = rgba.bitmapData else { return nil }
        let srcStride = rgba.bytesPerRow

        guard let rgbRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let dst = rgbRep.bitmapData else { return nil }
        rgbRep.size = rgba.size
        let dstStride = rgbRep.bytesPerRow

        for y in 0..<height {
            let srcRow = src + y * srcStride
            let dstRow = dst + y * dstStride
            for x in 0..<width {
                dstRow[x * 3 + 0] = srcRow[x * 4 + 0]
                dstRow[x * 3 + 1] = srcRow[x * 4 + 1]
                dstRow[x * 3 + 2] = srcRow[x * 4 + 2]
            }
        }
        return rgbRep
    }

    // Bakes the drawn annotations into the captured pixels, shifting them
    // from window-local coordinates (where the capture rect starts at
    // `offset`, not the origin) into the captured image's own coordinate
    // space (which starts at 0,0). The chrome bars are never included,
    // since the window itself is excluded from the raw capture.
    private static func composite(annotations: [Annotation], onto image: NSImage, size: CGSize, offset: CGPoint) -> NSImage {
        let output = NSImage(size: size)
        output.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: size))

        if !annotations.isEmpty, let context = NSGraphicsContext.current {
            let settings = AppSettings.shared
            context.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: -offset.x, yBy: -offset.y)
            transform.concat()
            for annotation in annotations {
                switch annotation {
                case .arrow:
                    annotation.draw(color: settings.arrowColor, lineWidth: settings.arrowWidth)
                case .frame:
                    annotation.draw(color: settings.frameColor, lineWidth: settings.frameStrokeWidth)
                case .number:
                    annotation.draw(color: settings.numberColor, fontSize: settings.numberFontSize, fontFamily: settings.numberFontFamily)
                }
            }
            context.restoreGraphicsState()
        }

        // Bars: real mask rectangles baked into the output (unlike
        // Guides), matching the original's opaque pnlBarTop/pnlBarBottom
        // panels that sat over the capture area.
        let settings = AppSettings.shared
        let topHeight = size.height * settings.barTopFraction
        let bottomHeight = size.height * settings.barBottomFraction
        if topHeight > 0 || bottomHeight > 0 {
            settings.barColor.setFill()
            if topHeight > 0 {
                NSBezierPath(rect: CGRect(x: 0, y: size.height - topHeight, width: size.width, height: topHeight)).fill()
            }
            if bottomHeight > 0 {
                NSBezierPath(rect: CGRect(x: 0, y: 0, width: size.width, height: bottomHeight)).fill()
            }
        }

        output.unlockFocus()
        return output
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}
