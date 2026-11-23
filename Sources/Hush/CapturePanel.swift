import AppKit
import HushCore
import SwiftUI

enum CaptureField { case title, note, under }

@Observable
final class CaptureModel {
    var title = ""
    var note = ""
    var expanded = false
    var field: CaptureField = .title
    /// Chosen destination; nil = Inbox.
    var parent: ParentMatch?
    /// Text in the "Under" field (the chosen parent's path once accepted).
    var underQuery = ""
    var suggestions: [ParentMatch] = []
    var selected = 0

    var search: (String) -> [ParentMatch] = { _ in [] }
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}

    static let noteLimit = 10_000

    var destinationName: String { parent?.task.title ?? "Inbox" }
    static func label(_ m: ParentMatch) -> String { (m.path + [m.task.title]).joined(separator: " › ") }

    /// D7: `/` at the start or after a space, running to the end of the input.
    var slashToken: (range: Range<String.Index>, prefix: String)? {
        guard let slash = title.lastIndex(of: "/") else { return nil }
        if slash != title.startIndex, title[title.index(before: slash)] != " " { return nil }
        return (slash..<title.endIndex, String(title[title.index(after: slash)...]))
    }

    func refresh() {
        let q: String
        switch field {
        case .title: q = slashToken?.prefix ?? ""
        case .under: q = underQuery == parent.map(Self.label) ? "" : underQuery
        case .note: q = ""
        }
        suggestions = q.isEmpty ? [] : search(q)
        selected = 0
    }

    func move(_ d: Int) { if !suggestions.isEmpty { selected = (selected + d + suggestions.count) % suggestions.count } }

    /// Accept the highlighted suggestion; returns false when there was none.
    @discardableResult func accept() -> Bool {
        guard suggestions.indices.contains(selected) else { return false }
        let m = suggestions[selected]
        parent = m
        if field == .title, let t = slashToken {
            title.removeSubrange(t.range)
            while title.last == " " { title.removeLast() }
        } else { underQuery = Self.label(m); field = .title }
        suggestions = []
        return true
    }

    func underEdited() {
        if underQuery.isEmpty { parent = nil }
        refresh()
    }

    var isBlank: Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func reset(keepParent: Bool = false) {
        title = ""; note = ""; suggestions = []; field = .title
        if !keepParent { parent = nil; underQuery = ""; expanded = false }
    }
}

struct CaptureView: View {
    @Bindable var model: CaptureModel
    var onHeight: (CGFloat) -> Void = { _ in }
    @FocusState private var focus: CaptureField?

    var body: some View {
        VStack(spacing: 0) {
            TextField("", text: $model.title,
                      prompt: Text("What's on your mind?").foregroundColor(Theme.inkFaint))
                .textFieldStyle(.plain)
                .font(Theme.captureFont)
                .tracking(-0.48) // -2% of 24pt
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .focused($focus, equals: .title)
                .padding(Theme.s6)
                .onChange(of: model.title) { _, _ in model.refresh() }
            if model.field == .title { suggestionList }
            if model.expanded {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                details
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: Theme.s4) {
                Label(model.destinationName, systemImage: "folder")
                    .font(.geist(size: 13))
                    .foregroundStyle(Theme.inkMute)
                Spacer()
                if model.expanded { hint("⇧⇥", "Title"); hint("⌘↵", "Save", primary: true) } else { hint("⇥", "Details"); hint("↵", "Save", primary: true) }
            }
            .padding(.horizontal, Theme.s6)
            .padding(.vertical, 10)
        }
        .frame(width: 640)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rModal))
        .overlay(RoundedRectangle(cornerRadius: Theme.rModal).strokeBorder(Theme.hairline, lineWidth: 1))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { onHeight($0) }
        .onAppear { focus = model.field }
        .onChange(of: model.field) { _, f in focus = f }
        .onChange(of: focus) { _, f in if let f { model.field = f; model.refresh() } }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            ZStack(alignment: .topLeading) {
                if model.note.isEmpty {
                    Text("Add a note").font(Theme.bodyFont).foregroundStyle(Theme.inkFaint).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $model.note)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.accent)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .note)
                    .frame(height: 88)
                    .onChange(of: model.note) { _, n in
                        if n.count > CaptureModel.noteLimit { model.note = String(n.prefix(CaptureModel.noteLimit)) }
                    }
            }
            HStack(spacing: Theme.s2) {
                Text("Under").font(Theme.captionFont).foregroundStyle(Theme.inkMute)
                TextField("", text: $model.underQuery, prompt: Text("Inbox").foregroundColor(Theme.inkFaint))
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.accent)
                    .focused($focus, equals: .under)
                    .onChange(of: model.underQuery) { _, _ in model.underEdited() }
            }
            if model.field == .under { suggestionList }
        }
        .padding(.horizontal, Theme.s6)
        .padding(.vertical, Theme.s3)
    }

    @ViewBuilder private var suggestionList: some View {
        if !model.suggestions.isEmpty {
            VStack(spacing: 0) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { i, m in
                    HStack(spacing: Theme.s2) {
                        Image(systemName: "folder").font(Theme.captionFont).foregroundStyle(Theme.inkFaint)
                        Text(m.task.title).font(Theme.bodyFont).foregroundStyle(Theme.ink).lineLimit(1)
                        if !m.path.isEmpty {
                            Text(m.path.joined(separator: " › ")).font(Theme.captionFont).foregroundStyle(Theme.inkFaint).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Theme.s3)
                    .frame(height: Theme.rowHeight)
                    .background(i == model.selected ? Theme.accentWash : .clear, in: RoundedRectangle(cornerRadius: Theme.rRow))
                    .padding(.horizontal, Theme.s2)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selected = i; model.accept() }
                }
            }
            .padding(.bottom, Theme.s2)
        }
    }

    private func hint(_ key: String, _ label: String, primary: Bool = false) -> some View {
        HStack(spacing: 8) {
            Keycap(text: key)
            Text(label).font(.geist(size: 13, weight: primary ? .medium : .regular))
                .foregroundStyle(primary ? Theme.ink : Theme.inkMute)
        }
    }
}

struct PillView: View {
    var destination = "Inbox"
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.geist(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Theme.accent, in: Circle())
            (Text("Saved to ") + Text(destination).fontWeight(.semibold))
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
    /// Preferred: set this and the controller saves (title, note, chosen parent) and searches parents itself.
    var store: TaskStore? { didSet { model.search = { [weak self] in (try? self?.store?.searchParents(prefix: $0, limit: 5)) ?? [] } } }
    /// Fallback when `store` is nil: receives the trimmed title; return false to keep the panel open.
    var onSave: (String) -> Bool = { _ in true }

    private let model = CaptureModel()
    private let panel = CapturePanel.floating()
    private let pill = CapturePanel.floating()
    private var previousApp: NSRunningApplication?
    private var pillHide: DispatchWorkItem?
    private var monitor: Any?
    private var draftAt: Date?
    private static let draftTTL: TimeInterval = 60

    init() {
        model.onSubmit = { [weak self] in self?.save(keepOpen: false) }
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
        // D9: a draft survives 60 s after Esc.
        if let at = draftAt, Date().timeIntervalSince(at) > Self.draftTTL { model.reset() }
        draftAt = nil
        model.field = .title
        let host = NSHostingView(rootView: CaptureView(model: model, onHeight: { [weak self] h in self?.resize(height: h) }))
        panel.contentView = host
        place(panel, size: host.fittingSize)
        // No NSApp.activate(): a .nonactivatingPanel takes keystrokes without activating
        // Hush, and activating would raise the outline window too (user-reported bug).
        panel.makeKeyAndOrderFront(nil)
        monitor = monitor ?? NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            nonisolated(unsafe) let ev = e
            return MainActor.assumeIsolated { self?.swallows(ev) ?? false } ? nil : e
        }
    }

    func dismiss(restoreFocus: Bool) {
        guard panel.isVisible else { return }
        draftAt = model.isBlank ? nil : Date()
        if model.isBlank { model.reset() }
        closePanel(restoreFocus: restoreFocus)
    }

    private func closePanel(restoreFocus: Bool) {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate() }
    }

    /// True to swallow the event.
    private func swallows(_ e: NSEvent) -> Bool {
        guard panel.isKeyWindow else { return false }
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        switch e.keyCode {
        case 48: // tab
            guard mods.isEmpty || mods == .shift else { return false }
            if mods == .shift {
                switch model.field {
                case .title: break
                case .note: model.field = .title
                case .under: model.field = .note
                }
            } else {
                switch model.field {
                case .title: model.expanded = true; model.field = .note
                case .note: model.field = .under
                case .under: model.field = .note
                }
            }
            model.refresh()
            return true
        case 126, 125: // up, down
            guard mods.isEmpty, !model.suggestions.isEmpty else { return false }
            model.move(e.keyCode == 125 ? 1 : -1)
            return true
        case 36, 76: // return
            if mods == .option { save(keepOpen: true); return true }
            if mods == .command { save(keepOpen: false); return true }
            guard mods.isEmpty else { return false }
            if model.accept() { model.refresh(); return true }
            if model.field == .note { return false } // newline
            if model.field == .under { return true }
            save(keepOpen: false)
            return true
        default: return false
        }
    }

    private func save(keepOpen: Bool) {
        let title = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let dest = model.destinationName
        if let store {
            do {
                _ = try store.create(title: title, note: model.note, parent: try model.parent?.task.id ?? store.inbox().id)
            } catch { NSLog("Hush: capture failed: \(error)"); return }
        } else if !onSave(title) { return }
        draftAt = nil
        if keepOpen { model.reset(keepParent: true); model.field = .title; return } // D9: no pill
        model.reset()
        let screen = panel.screen
        closePanel(restoreFocus: true)
        showPill(destination: dest, on: screen)
    }

    private func showPill(destination: String, on screen: NSScreen?) {
        pillHide?.cancel()
        let host = NSHostingView(rootView: PillView(destination: destination))
        pill.contentView = host
        place(pill, size: host.fittingSize, on: screen)
        // 180ms morph in: scale ~0.96 -> 1 plus opacity (opacity only with Reduce Motion).
        let end = pill.frame
        if !Theme.reduceMotion {
            pill.setFrame(end.insetBy(dx: end.width * 0.02, dy: end.height * 0.02), display: false)
        }
        pill.alphaValue = 0
        pill.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            pill.animator().alphaValue = 1
            pill.animator().setFrame(end, display: true)
        }
        let hide = DispatchWorkItem { [pill] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Theme.reduceMotion ? 0 : 0.15
                pill.animator().alphaValue = 0
            }, completionHandler: { pill.orderOut(nil) })
        }
        pillHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 + 0.9, execute: hide)
    }

    /// Grow/shrink the panel downward, keeping the top edge fixed.
    private func resize(height: CGFloat) {
        guard panel.isVisible, height > 0, abs(panel.frame.height - height) > 0.5 else { return }
        var f = panel.frame
        f.origin.y += f.height - height
        f.size.height = height
        panel.setFrame(f, display: true)
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
