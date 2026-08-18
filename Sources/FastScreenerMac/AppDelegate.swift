import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: CaptureWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main!.frame
        let captureSize = CGSize(width: 800, height: 450)
        let windowSize = CGSize(
            width: captureSize.width + CaptureFrameView.leftBarWidth,
            height: captureSize.height + CaptureFrameView.topBarHeight + CaptureFrameView.bottomBarHeight
        )
        let origin = CGPoint(x: screen.midX - windowSize.width / 2, y: screen.midY - windowSize.height / 2)

        window = CaptureWindow(contentRect: CGRect(origin: origin, size: windowSize))
        if let frameView = window.contentView as? CaptureFrameView {
            frameView.onCaptureRequested = { [weak self] in self?.captureAndSave() }
        }
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

                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([finalImage])

                if let tiff = finalImage.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                    let trimmed = filenameOverride.trimmingCharacters(in: .whitespaces)
                    let name: String
                    if trimmed.isEmpty {
                        name = "FastScreener_\(Self.timestamp()).png"
                    } else {
                        name = trimmed.hasSuffix(".png") ? trimmed : "\(trimmed).png"
                    }
                    let url = dir.appendingPathComponent(name)
                    try png.write(to: url)
                    print("Captured + copied to clipboard -> \(url.path)")
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
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
            context.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: -offset.x, yBy: -offset.y)
            transform.concat()
            for annotation in annotations {
                annotation.draw()
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
