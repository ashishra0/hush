import AppKit
import Carbon.HIToolbox
import HushCore
import ServiceManagement
import SwiftUI

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
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 10),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Settings"
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
    private var monitor: Any?

    var dbPath: String { (try? TaskStore.defaultURL().path) ?? "Unavailable" }

    func refresh() {
        shortcut = HotKey.shared.display
        launchAtLogin = SMAppService.mainApp.status == .enabled // real state, not a stored copy
        launchError = nil
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
        // Probe: can this combination be registered at all? (HotKey.rebind doesn't report failure.)
        var probe: EventHotKeyRef?
        let st = RegisterEventHotKey(keyCode, mods, EventHotKeyID(signature: OSType(0x48555350), id: 2),
                                     GetApplicationEventTarget(), 0, &probe)
        guard st == noErr else { shortcutError = "That shortcut is already taken. Try another."; return }
        if let probe { UnregisterEventHotKey(probe) }
        hk.rebind(keyCode: keyCode, modifiers: mods)
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
            Text("Settings").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.ink)
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
                    Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunch($0) }))
                        .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                    if let e = model.launchError { Text(e).font(Theme.captionFont).foregroundStyle(Theme.inkMute) }
                }
            }
            divider
            row("Appearance") {
                Picker("", selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            divider
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text("Your tasks live on this Mac").font(Theme.bodyFont).foregroundStyle(Theme.ink)
                Text(model.dbPath).font(Theme.keycapFont).foregroundStyle(Theme.inkMute)
                    .textSelection(.enabled).lineLimit(2)
                Button("Show in Finder", action: model.showInFinder).buttonStyle(.link).font(Theme.captionFont)
            }
        }
        .padding(Theme.s6)
        .frame(width: 560, alignment: .leading)
        .background(Theme.surface)
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
