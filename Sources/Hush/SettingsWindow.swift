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
            row("Capture shortcut") {
                VStack(alignment: .trailing, spacing: Theme.s1) {
                    HStack(spacing: Theme.s2) {
                        Button(action: model.toggleRecording) {
                            Text(model.recording ? "Type shortcut…" : model.shortcut)
                                .font(Theme.keycapFont)
                                .foregroundStyle(model.recording ? Theme.accent : Theme.ink)
                                .padding(.horizontal, Theme.s3).frame(height: 26)
                                .background(Theme.surfaceSunk, in: RoundedRectangle(cornerRadius: Theme.rKeycap))
                                .overlay(RoundedRectangle(cornerRadius: Theme.rKeycap)
                                    .strokeBorder(model.recording ? Theme.accent : Theme.hairline, lineWidth: 1))
                        }.buttonStyle(.plain)
                        Button(action: model.resetShortcut) {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                        }.buttonStyle(.plain).help("Reset to ⌘⇧Space")
                    }
                    if let e = model.shortcutError { Text(e).font(Theme.captionFont).foregroundStyle(Theme.inkMute) }
                }
            }
            divider
            row("Launch at login") {
                VStack(alignment: .trailing, spacing: Theme.s1) {
                    AccentSwitch(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunch($0) }))
                    if let e = model.launchError { Text(e).font(Theme.captionFont).foregroundStyle(Theme.inkMute) }
                }
            }
            divider
            VStack(alignment: .leading, spacing: Theme.s3) {
                Text("Appearance").font(Theme.bodyFont).foregroundStyle(Theme.ink)
                HStack(spacing: Theme.s3) {
                    tile("system", "System")
                    tile("light", "Light")
                    tile("dark", "Dark")
                }
            }
            divider
            row("Show today's progress in the toolbar") {
                AccentSwitch(isOn: $model.showMomentum)
            }
            divider
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text("Your tasks live on this Mac").font(Theme.bodyFont).foregroundStyle(Theme.ink)
                Text(model.dbPath).font(Theme.keycapFont).foregroundStyle(Theme.inkMute)
                    .textSelection(.enabled).lineLimit(2)
                Button("Show in Finder", action: model.showInFinder).buttonStyle(.link).font(Theme.captionFont)
            }
        }
        .padding(.horizontal, Theme.s6).padding(.bottom, Theme.s6).padding(.top, 52)
        .frame(width: 560, alignment: .leading)
        .background(Theme.surface)
    }

    private func tile(_ tag: String, _ label: String) -> some View {
        let light = Color(white: 0.97), dark = Color(white: 0.12)
        let on = model.appearance == tag
        return Button { model.setAppearance(tag) } label: {
            VStack(spacing: Theme.s1) {
                ZStack {
                    if tag == "system" {
                        HStack(spacing: 0) { light; dark }
                    } else { tag == "light" ? light : dark }
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().frame(width: 40, height: 4); Capsule().frame(width: 28, height: 4)
                    }
                    .foregroundStyle(tag == "dark" ? Color.white.opacity(0.5) : tag == "light" ? Color.black.opacity(0.3) : Color.gray)
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rRow))
                .overlay(RoundedRectangle(cornerRadius: Theme.rRow).strokeBorder(on ? Theme.ink : Theme.hairline, lineWidth: on ? 2 : 1))
                Text(label).font(Theme.captionFont).foregroundStyle(on ? Theme.ink : Theme.inkMute)
            }
        }.buttonStyle(.plain).frame(maxWidth: .infinity)
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top) {
            Text(label).font(Theme.bodyFont).foregroundStyle(Theme.ink)
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
