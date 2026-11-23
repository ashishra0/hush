import AppKit
import HushCore
import SwiftUI

/// Entry point: `HistoryWindowController.shared.show(store:)` (⌘Y). One window; reopening focuses it.
@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()
    /// ⌘[ / "Home" crumb. The window closes first; set this to bring the outline forward.
    var onHome: () -> Void = {}

    private var window: NSWindow?
    private var sub: Subscription?
    private let model = HistoryModel()

    func show(store: TaskStore) {
        model.onRestore = { id in
            do { _ = try store.restore(fromHistory: id) } catch { NSLog("Hush: restore failed: \(error)") }
        }
        model.onClose = { [weak self] in self?.window?.performClose(nil) }
        model.onHome = { [weak self] in self?.window?.performClose(nil); self?.onHome() }
        if sub == nil {
            sub = store.observeHistory { [model] days in Task { @MainActor in model.days = days } }
        }
        if window == nil {
            let w = KeyedWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 780),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.contentMinSize = NSSize(width: 640, height: 400)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HistoryView(model: model))
            w.setFrameAutosaveName("HushHistory")
            w.center()
            window = w
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sub?.cancel(); self?.sub = nil } // live updates only while open
            }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
