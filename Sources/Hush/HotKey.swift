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
        let letters: [Int: String] = [0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
            38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
            32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z"]
        return s + (Int(keyCode) == kVK_Space ? "Space" : letters[Int(keyCode)] ?? "Key \(keyCode)")
    }
}
