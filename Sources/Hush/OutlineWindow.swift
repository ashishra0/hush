import AppKit
import HushCore
import SwiftUI

@MainActor
final class OutlineWindowController: NSObject {
    private let model: OutlineModel
    private let window: NSWindow
    private var monitor: Any?

    init(store: TaskStore) {
        model = OutlineModel(store: store)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "outline") // unified 52pt titlebar, traffic lights centred
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OutlineView(model: model))
        window.center()
        window.setFrameAutosaveName("OutlineWindow")
        // Local monitor: outline keys must work whether or not a field has focus; the model decides.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            let f = e.modifierFlags
            let k = KeyPress(code: e.keyCode, cmd: f.contains(.command), opt: f.contains(.option),
                             shift: f.contains(.shift), ctrl: f.contains(.control), typed: e.characters ?? "")
            return self.model.handle(k) ? nil : e
        }
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Undo/redo menu items go to the store when the outline is key and no row is being edited.
    var handlesUndo: Bool { window.isKeyWindow && model.editing == nil }
    func undo() { model.undo() }
    func redo() { model.redo() }
}
