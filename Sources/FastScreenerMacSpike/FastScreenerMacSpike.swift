import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

// Spike app: proves out the three riskiest native pieces needed to port
// FastScreener2 (Windows) to macOS, before investing in the real UI:
//   1. Global hotkey (F4) that fires even when the app isn't focused.
//   2. Screen capture of an arbitrary rect, saved to disk.
//   3. A CGEventTap that can intercept AND swallow the middle mouse button
//      globally (needed because MMB places annotations and must not leak
//      through to whatever app is under the cursor).

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var eventTap: CFMachPort?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "FS🔧"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Press F4 to capture main screen", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Middle-click anywhere: should be swallowed (check console)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        registerF4Hotkey()
        installMiddleClickTap()

        print("Spike running. Grant Screen Recording + Accessibility permission when prompted, then press F4 or middle-click.")
    }

    // MARK: - 1. Global hotkey via Carbon (no special permission needed)

    func registerF4Hotkey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4653_5350 /* "FSSP" */), id: 1)
        let eventSpec = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))]

        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if hkID.id == 1 {
                DispatchQueue.main.async { AppDelegate.captureMainScreen() }
            }
            return noErr
        }, 1, eventSpec, nil, nil)

        RegisterEventHotKey(UInt32(kVK_F4), 0, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - 2. Screen capture via ScreenCaptureKit (needs Screen Recording permission)

    static func captureMainScreen() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                let rep = NSBitmapImageRep(cgImage: image)
                guard let png = rep.representation(using: .png, properties: [:]) else { return }
                let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("fs_spike_capture.png")
                try png.write(to: url)
                print("Captured screen -> \(url.path)")
            } catch {
                print("Capture failed (likely missing Screen Recording permission): \(error)")
            }
        }
    }

    // MARK: - 3. CGEventTap to intercept + swallow middle mouse button (needs Accessibility permission)

    func installMiddleClickTap() {
        let mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
                guard event.getIntegerValueField(.mouseEventButtonNumber) == 2 else {
                    return Unmanaged.passRetained(event)
                }
                print("Middle click \(type == .otherMouseDown ? "down" : "up") intercepted + swallowed")
                return nil // swallow: don't let it reach other apps
            },
            userInfo: nil
        ) else {
            print("Failed to create event tap - grant Accessibility permission in System Settings > Privacy & Security, then relaunch.")
            return
        }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
