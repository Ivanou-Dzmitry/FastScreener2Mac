import AppKit
import Carbon.HIToolbox

// Thin wrapper around the Carbon global-hotkey API (RegisterEventHotKey).
// Works even when the app isn't focused and needs no special permission,
// unlike a CGEventTap.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    private init() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData -> OSStatus in
            guard let eventRef, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let handler = manager.handlers[hkID.id] {
                DispatchQueue.main.async { handler() }
            }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @discardableResult
    func register(keyCode: Int, modifiers: UInt32 = 0, action: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1
        handlers[id] = action

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4653_4d41 /* "FSMA" */), id: id)
        RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        return id
    }
}
