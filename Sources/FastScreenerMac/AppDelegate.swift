import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: CaptureWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main!.frame
        let size = CGSize(width: 800, height: 450)
        let origin = CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)

        window = CaptureWindow(contentRect: CGRect(origin: origin, size: size))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        HotkeyManager.shared.register(keyCode: kVK_F4) { [weak self] in
            self?.captureAndSave()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func captureAndSave() {
        guard let window else { return }
        let rect = window.frame
        let windowNumber = window.windowNumber

        Task {
            do {
                let image = try await ScreenCapture.captureRect(rect, excludingWindowNumber: windowNumber)

                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])

                if let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                    let url = dir.appendingPathComponent("FastScreener_\(Self.timestamp()).png")
                    try png.write(to: url)
                    print("Captured + copied to clipboard -> \(url.path)")
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}
