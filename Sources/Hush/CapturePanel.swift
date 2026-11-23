import AppKit
import SwiftUI

@Observable
final class CaptureModel {
    var title = ""
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}
}

struct CaptureView: View {
    @Bindable var model: CaptureModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("", text: $model.title,
                      prompt: Text("What's on your mind?").foregroundColor(Theme.inkFaint))
                .textFieldStyle(.plain)
                .font(Theme.captureFont)
                .tracking(-0.48) // -2% of 24pt
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .focused($focused)
                .padding(Theme.s6)
                .onSubmit { model.onSubmit() }
                .onExitCommand { model.onCancel() }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: Theme.s4) {
                Label("Inbox", systemImage: "folder")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.inkMute)
                Spacer()
                hint("↵", "Save")
            }
            .padding(.horizontal, Theme.s6)
            .padding(.vertical, 10)
        }
        .frame(width: 640)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rModal))
        .overlay(RoundedRectangle(cornerRadius: Theme.rModal).strokeBorder(Theme.hairline, lineWidth: 1))
        .onAppear { focused = true }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Keycap(text: key)
            Text(label).font(Theme.captionFont).foregroundStyle(Theme.inkMute)
        }
    }
}

struct PillView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Theme.accent, in: Circle())
            (Text("Saved to ") + Text("Inbox").fontWeight(.semibold))
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, 10)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(Theme.s2)
    }
}

final class CapturePanel: NSPanel {
    var onCancel: (() -> Void)?
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func resignKey() { super.resignKey(); onResign?() }

    static func floating(styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]) -> Self {
        let p = Self(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }
}

@MainActor
final class CaptureController {
    /// Wire to persistence. Receives the trimmed, non-empty title; return false to keep the panel open.
    var onSave: (String) -> Bool = { _ in true }

    private let model = CaptureModel()
    private let panel = CapturePanel.floating()
    private let pill = CapturePanel.floating()
    private var previousApp: NSRunningApplication?
    private var pillHide: DispatchWorkItem?

    init() {
        model.onSubmit = { [weak self] in self?.save() }
        model.onCancel = { [weak self] in self?.dismiss(restoreFocus: true) }
        panel.onCancel = { [weak self] in self?.dismiss(restoreFocus: true) }
        panel.onResign = { [weak self] in self?.dismiss(restoreFocus: false) } // clicked elsewhere
        pill.ignoresMouseEvents = true
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? dismiss(restoreFocus: true) : show() }

    func show() {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            previousApp = front
        }
        pill.orderOut(nil)
        let host = NSHostingView(rootView: CaptureView(model: model))
        panel.contentView = host
        place(panel, size: host.fittingSize)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss(restoreFocus: Bool) {
        guard panel.isVisible else { return }
        model.title = "" // P0: dismiss discards (draft retention is P1-14)
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate() }
    }

    private func save() {
        let title = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard onSave(title) else { NSSound.beep(); return }
        model.title = ""
        let screen = panel.screen
        dismiss(restoreFocus: true)
        showPill(on: screen)
    }

    private func showPill(on screen: NSScreen?) {
        pillHide?.cancel()
        let host = NSHostingView(rootView: PillView())
        pill.contentView = host
        place(pill, size: host.fittingSize, on: screen)
        pill.alphaValue = 1
        pill.orderFrontRegardless()
        let hide = DispatchWorkItem { [pill] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Theme.reduceMotion ? 0 : 0.15
                pill.animator().alphaValue = 0
            }, completionHandler: { pill.orderOut(nil) })
        }
        pillHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: hide)
    }

    /// Centered horizontally, top edge at 23% down the (mouse's) screen.
    private func place(_ w: NSWindow, size: NSSize, on screen: NSScreen? = nil) {
        let mouse = NSEvent.mouseLocation
        let s = screen ?? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let f = s?.frame else { return }
        let top = f.maxY - f.height * 0.23
        w.setFrame(NSRect(x: f.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height),
                   display: true)
    }
}
