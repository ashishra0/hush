import AppKit
import HushCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let capture = CaptureController()
    private let popoverModel = PopoverModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var store: TaskStore!
    private var menuBarSub: Subscription?
    private var outline: OutlineWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["HUSH_DB_PATH"] == nil, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil) // a copy is already running: one menu bar item only
            return
        }
        do {
            let env = ProcessInfo.processInfo.environment
            store = try TaskStore(path: env["HUSH_DB_PATH"] ?? TaskStore.defaultURL().path) // override: throwaway DBs for testing
        } catch {
            let alert = NSAlert()
            alert.messageText = "Hush can't open its task database"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        SettingsWindowController.applyStoredAppearance()
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Hush")
        }

        popoverModel.shortcut = HotKey.shared.display
        popoverModel.onCapture = { [weak self] in self?.popover.performClose(nil); self?.capture.show() }
        popoverModel.onQuit = { NSApp.terminate(nil) }
        popoverModel.onComplete = { [weak self] t in
            do { _ = try self?.store.complete(TaskID(t.id)) } catch { NSLog("Hush: complete failed: \(error)") }
        }

        let host = NSHostingController(rootView: PopoverView(model: popoverModel))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = !Theme.reduceMotion

        capture.store = store
        outline = OutlineWindowController(store: store)
        popoverModel.onHistory = { [weak self] in self?.popover.performClose(nil); self?.openHistory() }
        popoverModel.onSettings = { [weak self] in self?.popover.performClose(nil); SettingsWindowController.shared.show() }
        ClosureCard.onHistory = { [weak self] in self?.openHistory() }
        popoverModel.onOpenOutline = { [weak self] in self?.popover.performClose(nil); self?.outline.show() }
        HistoryWindowController.shared.onHome = { [weak self] in self?.outline.show() }
        if ProcessInfo.processInfo.environment["HUSH_OPEN_OUTLINE"] == "1" { outline.show() }
        menuBarSub = store.observeMenuBar(limit: 5) { [popoverModel] snap in
            popoverModel.recent = snap.recent.map { RecentTask(id: $0.id.raw, title: $0.title, createdAt: $0.createdAt) }
            popoverModel.openCount = snap.openCount
        }
        HotKey.shared.handler = { [capture] in capture.toggle() }
        HotKey.shared.register()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func openOutline() { outline.show() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func openClosure() {
        guard let b = statusItem.button else { return }
        NSApp.activate()
        ClosureCard.show(relativeTo: b, store: store)
    }
    @objc private func menuUndo(_ sender: Any?) {
        if outline.handlesUndo { outline.undo() } else { NSApp.sendAction(Selector(("undo:")), to: nil, from: sender) }
    }
    @objc private func menuRedo(_ sender: Any?) {
        if outline.handlesUndo { outline.redo() } else { NSApp.sendAction(Selector(("redo:")), to: nil, from: sender) }
    }
    @objc private func openHistory() { HistoryWindowController.shared.show(store: store) }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popoverModel.shortcut = HotKey.shared.display
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Accessory apps have no visible menu, but Edit/Quit key equivalents (⌘V, ⌘Z, ⌘Q) need one.
    private func installMainMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [(String, Selector, String)]) {
            let item = NSMenuItem(); main.addItem(item)
            let menu = NSMenu(title: title); item.submenu = menu
            for (t, sel, key) in items { menu.addItem(withTitle: t, action: sel, keyEquivalent: key) }
        }
        add("Hush", [("Open Outline", #selector(openOutline), "o"), ("History", #selector(openHistory), "y"),
                     ("Today", #selector(openClosure), "d"), ("Settings…", #selector(openSettings), ","),
                     ("Close Window", #selector(NSWindow.performClose(_:)), "w"),
                     ("Quit Hush", #selector(NSApplication.terminate(_:)), "q")])
        add("Edit", [("Undo", #selector(menuUndo), "z"), ("Redo", #selector(menuRedo), "Z"),
                     ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")])
        NSApp.mainMenu = main
    }

    /// 14px circle outline + center dot, template image.
    private static func menuBarIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            NSColor.black.set()
            let ring = NSBezierPath(ovalIn: NSRect(x: r.midX - 6.25, y: r.midY - 6.25, width: 12.5, height: 12.5))
            ring.lineWidth = 1.5
            ring.stroke()
            NSBezierPath(ovalIn: NSRect(x: r.midX - 2, y: r.midY - 2, width: 4, height: 4)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
