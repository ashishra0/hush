import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon RegisterEventHotKey (no Accessibility permission needed).
/// (keyCode, modifiers) persist in UserDefaults; modifiers use Carbon masks (cmdKey, shiftKey, ...).
@MainActor
final class HotKey {
    static let shared = HotKey()
    var handler: (@MainActor () -> Void)?

    private(set) var keyCode: UInt32
    private(set) var modifiers: UInt32
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    private let defaults = UserDefaults.standard

    private init() {
        keyCode = (defaults.object(forKey: "hotkey.keyCode") as? Int).map(UInt32.init) ?? UInt32(kVK_Space)
        modifiers = (defaults.object(forKey: "hotkey.modifiers") as? Int).map(UInt32.init) ?? UInt32(cmdKey | shiftKey)
    }

    func register() {
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                MainActor.assumeIsolated { HotKey.shared.handler?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        _ = tryRegister(keyCode, modifiers)
    }

    private func tryRegister(_ code: UInt32, _ mods: UInt32) -> Bool {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        let id = EventHotKeyID(signature: OSType(0x48555348) /* 'HUSH' */, id: 1)
        let status = RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("Hush: RegisterEventHotKey failed (\(status)); shortcut may be taken") }
        return status == noErr
    }

    /// Rebind and persist (used by Settings). Returns false, keeping the old shortcut, if the combination can't be registered.
    @discardableResult
    func rebind(keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard tryRegister(keyCode, modifiers) else { _ = tryRegister(self.keyCode, self.modifiers); return false }
        self.keyCode = keyCode
        self.modifiers = modifiers
        defaults.set(Int(keyCode), forKey: "hotkey.keyCode")
        defaults.set(Int(modifiers), forKey: "hotkey.modifiers")
        return true
    }

    func reset() {
        defaults.removeObject(forKey: "hotkey.keyCode")
        defaults.removeObject(forKey: "hotkey.modifiers")
        keyCode = UInt32(kVK_Space)
        modifiers = UInt32(cmdKey | shiftKey)
        register()
    }

    /// e.g. "⌘⇧Space"
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    private static let specials: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Escape: "Esc", kVK_Delete: "Delete",
        kVK_ForwardDelete: "Fwd Delete", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Specials from a table; printable keys via the current keyboard layout (so ";" or "ö" show correctly).
    private static func keyName(_ code: UInt32) -> String {
        if let n = specials[Int(code)] { return n }
        if let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let p = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(p).takeUnretainedValue()
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let ok = CFDataGetBytePtr(data).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
                UCKeyTranslate($0, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
            }
            if ok == noErr, len > 0 { return String(utf16CodeUnits: chars, count: len).uppercased() }
        }
        return "Key \(code)"
    }
}
