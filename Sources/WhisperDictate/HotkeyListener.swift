import AppKit
import Carbon

// Registers a global hotkey (⌘⌥D) using the Carbon Event Manager.
// This does NOT require the Accessibility or Input Monitoring permission.
// The trade-off: Carbon hotkeys see the key only when no other registered handler
// claims it first — if registration returns an error we surface that to the user.
//
// kVK_ANSI_D = 0x02 (from Carbon's Events.h / HIToolbox)
// cmdKey | optionKey = (1 << 8) | (1 << 11) = 2304
final class HotkeyListener {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    // Bridging Carbon (C) callbacks back into Swift:
    //   - Carbon's InstallEventHandler takes a function-pointer closure with NO captured
    //     context, so we cannot use a normal Swift closure that references `self`.
    //   - Instead, we store an unretained opaque pointer to `self` in this static, and
    //     the C callback reaches back into Swift via Unmanaged.fromOpaque(...).takeUnretainedValue().
    //   - "Unretained" is safe here because HotkeyListener outlives the event handler
    //     for the entire app lifetime (it's owned by AppDelegate) and we clear the
    //     pointer in unregister()/deinit before the C callback can fire again.
    // Only one HotkeyListener instance exists at a time, so a single static slot is enough.
    private static var instancePointer: UnsafeMutableRawPointer?

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    // Returns the OSStatus from RegisterEventHotKey. noErr (0) means success.
    @discardableResult
    func register() -> OSStatus {
        let keyID = EventHotKeyID(signature: fourCharCode("WDic"), id: 1)

        // Install the Carbon event handler on the application event target.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        // Store self so the C handler can call back.
        Self.instancePointer = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                // This is a C callback — no Swift context. Reach back via the stored pointer.
                guard let ptr = HotkeyListener.instancePointer else { return noErr }
                let listener = Unmanaged<HotkeyListener>.fromOpaque(ptr).takeUnretainedValue()
                DispatchQueue.main.async { listener.callback() }
                return noErr
            },
            1, &eventType, nil, &handlerRef
        )
        guard status == noErr else { return status }

        // kVK_ANSI_D = 0x02, cmdKey | optionKey = 256 | 2048 = 2304
        return RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(cmdKey | optionKey),
                                   keyID, GetApplicationEventTarget(),
                                   0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
        Self.instancePointer = nil
    }

    deinit { unregister() }
}

// Converts a 4-character ASCII string to an OSType (UInt32).
private func fourCharCode(_ s: String) -> OSType {
    let chars = Array(s.utf8)
    precondition(chars.count == 4, "fourCharCode requires exactly 4 ASCII characters")
    return OSType(chars[0]) << 24 | OSType(chars[1]) << 16 | OSType(chars[2]) << 8 | OSType(chars[3])
}
