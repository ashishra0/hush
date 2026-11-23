import AppKit
import Carbon.HIToolbox
import HushCore
import ServiceManagement
import SwiftUI

/// Esc and ⌘W close, consistently across Hush windows.
final class KeyedWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(nil) }
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, e.charactersIgnoringModifiers == "w" { performClose(nil); return true }
        return super.performKeyEquivalent(with: e)
    }
}

/// Entry point: `SettingsWindowController.shared.show()` (⌘, and popover "Settings…").
/// Call `applyStoredAppearance()` once at launch.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let model = SettingsModel()

    static let appearanceKey = "appearance" // "system" | "light" | "dark"

    static func applyStoredAppearance() {
        switch UserDefaults.standard.string(forKey: appearanceKey) {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func show() {
        model.refresh()
        if window == nil {
            let w = KeyedWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 10),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Settings"
            w.setFrameAutosaveName("HushSettings")
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: SettingsView(model: model))
            w.contentView = host
            w.setContentSize(host.fittingSize)
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@Observable
@MainActor
final class SettingsModel {
    var shortcut = HotKey.shared.display
    var shortcutError: String?
    var recording = false
    var launchAtLogin = false
    var launchError: String?
    var appearance = UserDefaults.standard.string(forKey: SettingsWindowController.appearanceKey) ?? "system"
    var showMomentum = UserDefaults.standard.bool(forKey: "showMomentum") {
        didSet { UserDefaults.standard.set(showMomentum, forKey: "showMomentum") }
    }
    private var monitor: Any?

    var dbPath: String { ((try? TaskStore.defaultURL().path) as NSString?)?.abbreviatingWithTildeInPath ?? "Unavailable" }

    func refresh() {
        shortcut = HotKey.shared.display
        launchAtLogin = SMAppService.mainApp.status == .enabled // real state, not a stored copy
        launchError = nil
        showMomentum = UserDefaults.standard.bool(forKey: "showMomentum")
    }

    func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = "Only works from the installed Hush app."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setAppearance(_ a: String) {
        appearance = a
        UserDefaults.standard.set(a, forKey: SettingsWindowController.appearanceKey)
        SettingsWindowController.applyStoredAppearance()
    }

    func showInFinder() {
        guard let url = try? TaskStore.defaultURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: shortcut recorder (P2-04)

    func toggleRecording() { recording ? stopRecording() : startRecording() }

    private func startRecording() {
        shortcutError = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            nonisolated(unsafe) let ev = e
            let kc = UInt32(ev.keyCode), flags = ev.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            MainActor.assumeIsolated { self?.captured(keyCode: kc, flags: NSEvent.ModifierFlags(rawValue: flags)) }
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func captured(keyCode: UInt32, flags: NSEvent.ModifierFlags) {
        if keyCode == UInt32(kVK_Escape) { stopRecording(); return }
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        stopRecording()
        guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            shortcutError = "Include ⌘, ⌥ or ⌃ in the shortcut."; return
        }
        let hk = HotKey.shared
        if keyCode == hk.keyCode, mods == hk.modifiers { shortcutError = nil; return }
        guard hk.rebind(keyCode: keyCode, modifiers: mods) else {
            shortcutError = "That shortcut is already taken. Try another."; return
        }
        shortcut = hk.display
        shortcutError = nil
    }

    func resetShortcut() {
        stopRecording()
        HotKey.shared.reset()
        shortcut = HotKey.shared.display
        shortcutError = nil
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s6) {
            row("Capture shortcut", "Works from any app") {
                VStack(alignment: .trailing, spacing: Theme.s1) {
                    HStack(spacing: Theme.s2) {
                        Button(action: model.toggleRecording) {
                            Text(model.recording ? "Type shortcut…" : Self.spaced(model.shortcut))
                                .font(.geist(size: 14, design: .monospaced))
                                .foregroundStyle(model.recording ? Theme.accent : Theme.ink)
                                .padding(.horizontal, Theme.s4).frame(height: 30)
                                .background(Theme.surfaceSunk, in: RoundedRectangle(cornerRadius: Theme.rKeycap))
                                .overlay(RoundedRectangle(cornerRadius: Theme.rKeycap)
                                    .strokeBorder(model.recording ? Theme.accent : Theme.hairline, lineWidth: 1))
                        }.buttonStyle(.plain)
                        Button(action: model.resetShortcut) {
                            Image(systemName: "xmark").font(.geist(size: 10, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                        }.buttonStyle(.plain).help("Reset to ⌘⇧Space")
                    }
                    if let e = model.shortcutError { Text(e).font(Theme.captionFont).foregroundStyle(Theme.inkMute) }
                }
            }
            divider
            row("Launch at login", "Starts quietly in the menu bar") {
                VStack(alignment: .trailing, spacing: Theme.s1) {
                    AccentSwitch(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunch($0) }))
                    if let e = model.launchError { Text(e).font(Theme.captionFont).foregroundStyle(Theme.inkMute) }
                }
            }
            divider
            VStack(alignment: .leading, spacing: Theme.s3) {
                Text("Appearance").font(.geist(size: 15)).foregroundStyle(Theme.ink)
                HStack(spacing: Theme.s3) {
                    tile("system", "System")
                    tile("light", "Light")
                    tile("dark", "Dark")
                }
            }
            divider
            row("Show today's progress in the toolbar", "A few marks and a count, next to Find") {
                AccentSwitch(isOn: $model.showMomentum)
            }
            divider
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your tasks live on this Mac").font(.geist(size: 15)).foregroundStyle(Theme.ink)
                    Text(model.dbPath).font(Theme.keycapFont).foregroundStyle(Theme.inkMute).textSelection(.enabled).lineLimit(2)
                }
                Spacer()
                Button(action: model.showInFinder) {
                    Text("Show in Finder").font(.geist(size: 13)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.s3).frame(height: 28)
                        .background(Theme.surfaceSunk, in: RoundedRectangle(cornerRadius: Theme.rRow))
                        .overlay(RoundedRectangle(cornerRadius: Theme.rRow).strokeBorder(Theme.hairline, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.s6).padding(.bottom, Theme.s6).padding(.top, 52)
        .frame(width: 560, alignment: .leading)
        .background(Theme.surface)
    }

    /// "⇧⌘Space" -> "⌘  ⇧  Space" (modifiers spaced, ⌘ first, as in the design).
    private static func spaced(_ d: String) -> String {
        let mods = "⌃⌥⇧⌘"
        let m = d.filter { mods.contains($0) }, key = String(d.drop { mods.contains($0) })
        return (["⌘", "⇧", "⌥", "⌃"].filter { m.contains($0) } + [key]).joined(separator: "  ")
    }

    private func tile(_ tag: String, _ label: String) -> some View {
        // Fixed preview colours (grounds/surfaces of each mode), independent of the current appearance.
        let lg = Color(red: 0xEB / 255, green: 0xEB / 255, blue: 0xEB / 255), ls = Color.white
        let dg = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255), ds = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1C / 255)
        let le = Color(red: 0xDC / 255, green: 0xDC / 255, blue: 0xDF / 255), de = Color(red: 0x2E / 255, green: 0x2E / 255, blue: 0x32 / 255)
        let on = model.appearance == tag
        func field(_ surface: Color, _ edge: Color, caret: Bool, scale: CGFloat = 1) -> some View {
            RoundedRectangle(cornerRadius: 5).fill(surface).frame(width: 80 * scale, height: 20 * scale)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(edge, lineWidth: 1))
                .overlay(alignment: .leading) { if caret { Capsule().fill(Theme.accent).frame(width: 1.5, height: 10).padding(.leading, 6) } }
        }
        return Button { model.setAppearance(tag) } label: {
            VStack(spacing: Theme.s3) {
                ZStack {
                    switch tag {
                    case "system":
                        HStack(spacing: 0) {
                            ZStack { lg; field(ls, le, caret: false, scale: 0.55) }
                            ZStack { dg; field(ds, de, caret: false, scale: 0.55) }
                        }
                    case "light": ZStack { lg; field(ls, le, caret: true) }
                    default: ZStack { dg; field(ds, de, caret: true) }
                    }
                }
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rPopover))
                .overlay(RoundedRectangle(cornerRadius: Theme.rPopover).strokeBorder(on ? Theme.ink : Theme.hairline, lineWidth: on ? 2 : 1))
                Text(label).font(.geist(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.ink : Theme.inkFaint)
            }
        }
        .buttonStyle(.plain).frame(maxWidth: .infinity)
        .accessibilityLabel("\(label) appearance").accessibilityAddTraits(on ? .isSelected : [])
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }

    private func row<C: View>(_ label: String, _ sub: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.geist(size: 15)).foregroundStyle(Theme.ink)
                if let sub { Text(sub).font(.geist(size: 13)).foregroundStyle(Theme.inkFaint) }
            }
            Spacer()
            content()
        }
    }
}

/// Native switches ignore tint when ON on some macOS versions; draw our own (accent = the only blue).
struct AccentSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(Theme.reduceMotion ? nil : .easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            Capsule().fill(isOn ? Theme.accent : Theme.hairline).frame(width: 38, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) { Circle().fill(.white).frame(width: 18, height: 18).padding(2) }
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle("", isOn: $isOn) }
    }
}
