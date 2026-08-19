import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: CaptureWindow!
    var settingsWindow: SettingsWindow!

    static var capturesDirectory: URL { AppSettings.shared.saveFolderURL }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main!.frame
        let captureSize = CGSize(width: 800, height: 450)
        let windowSize = CGSize(
            width: captureSize.width + CaptureFrameView.leftBarWidth + CaptureFrameView.rightBarWidth,
            height: captureSize.height + CaptureFrameView.topBarHeight + CaptureFrameView.bottomBarHeight
        )
        let origin = CGPoint(x: screen.midX - windowSize.width / 2, y: screen.midY - windowSize.height / 2)

        window = CaptureWindow(contentRect: CGRect(origin: origin, size: windowSize))
        if let frameView = window.contentView as? CaptureFrameView {
            frameView.onCaptureRequested = { [weak self] in self?.captureAndSave() }
            frameView.onSettingsRequested = { [weak self] in self?.showSettings() }
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

        Task {
            do {
                let rawImage = try await ScreenCapture.captureRect(screenRect, excludingWindowNumbers: excludedWindowNumbers)
                let finalImage = Self.composite(annotations: annotations, onto: rawImage, size: interior.size, offset: interior.origin)

                // DPI Scale (on by default, matches the original): the
                // raw capture is at the display's native pixel density
                // (e.g. 2x on Retina), so a 650x366 capture would
                // otherwise save as a 1300x732px file. This resamples
                // down to exactly interior.size in actual pixels, so
                // the size you set is always the size you get,
                // regardless of the display's scale factor.
                let pasteboardImage: NSImage
                let pngRep: NSBitmapImageRep?
                if AppSettings.shared.dpiScale, let exactRep = Self.pixelExactBitmap(from: finalImage, pixelSize: interior.size) {
                    let exactImage = NSImage(size: interior.size)
                    exactImage.addRepresentation(exactRep)
                    pasteboardImage = exactImage
                    pngRep = exactRep
                } else {
                    pasteboardImage = finalImage
                    pngRep = finalImage.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }
                }

                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([pasteboardImage])

                if AppSettings.shared.saveToFile,
                   let rep = pngRep,
                   let png = rep.representation(using: .png, properties: [:]) {
                    let trimmed = filenameOverride.trimmingCharacters(in: .whitespaces)
                    let name: String
                    if trimmed.isEmpty {
                        name = "FastScreener_\(Self.timestamp()).png"
                    } else {
                        name = trimmed.hasSuffix(".png") ? trimmed : "\(trimmed).png"
                    }
                    let dir = Self.capturesDirectory
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(name)
                    try png.write(to: url)
                    print("Captured (\(rep.pixelsWide)x\(rep.pixelsHigh)px) + copied to clipboard -> \(url.path)")
                } else {
                    print("Captured + copied to clipboard (file save off)")
                }

                if AppSettings.shared.clearElementsAfterCapture {
                    frameView.clearAnnotations()
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    // Renders `image` into a bitmap whose pixel dimensions exactly equal
    // `pixelSize` (rep.size set to match, so it's 1 point == 1 pixel),
    // downsampling from whatever native resolution `image` actually
    // carries.
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

        output.unlockFocus()
        return output
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}
