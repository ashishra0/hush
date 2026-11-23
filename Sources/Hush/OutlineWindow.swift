import AppKit
import HushCore
import SwiftUI

/// Window and model are built on first `show()` so launch stays fast.
@MainActor
final class OutlineWindowController: NSObject {
    private let store: TaskStore
    private var model: OutlineModel?
    private var window: NSWindow?
    private var monitor: Any?

    init(store: TaskStore) { self.store = store; super.init() }

    private func build() -> (OutlineModel, NSWindow) {
        if let model, let window { return (model, window) }
        let m = OutlineModel(store: store)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 780),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: true)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.toolbar = NSToolbar(identifier: "outline") // unified 52pt titlebar, traffic lights centred
        w.toolbarStyle = .unified
        w.minSize = NSSize(width: 640, height: 400)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: OutlineView(model: m))
        w.center()
        w.setFrameAutosaveName("OutlineWindow")
        m.onFocusChange = { [weak w] on in   // Focus Mode dims the traffic lights
            for b: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                w?.standardWindowButton(b)?.alphaValue = on ? 0.35 : 1
            }
        }
        // Local monitor: outline keys must work whether or not a field has focus; the model decides.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak w, weak m] e in
            guard let w, e.window === w, let m, self != nil else { return e }
            let f = e.modifierFlags
            let k = KeyPress(code: e.keyCode, cmd: f.contains(.command), opt: f.contains(.option),
                             shift: f.contains(.shift), ctrl: f.contains(.control), typed: e.characters ?? "")
            return m.handle(k) ? nil : e
        }
        model = m; window = w
        return (m, w)
    }

    func show() {
        let (_, w) = build()
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    /// Test hook for HUSH_OPEN=focus|shortcuts.
    func showDebug(_ token: String) {
        show()
        guard let m = model else { return }
        if token == "focus" { m.focusFirstTask() } else if token == "shortcuts" { m.showShortcuts = true }
    }

    /// Undo/redo menu items go to the store when the outline is key and no row is being edited.
    var handlesUndo: Bool { (window?.isKeyWindow ?? false) && model?.editing == nil }
    func undo() { model?.undo() }
    func redo() { model?.redo() }
    /// ⌘D while the outline is key and the Quiet Momentum marks are showing: anchor the card to them.
    func showClosureFromMarks() -> Bool { (window?.isKeyWindow ?? false) && (model?.showClosureFromMarks() ?? false) }
}
