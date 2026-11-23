import AppKit
import HushCore
import SwiftUI

struct OutlineView: View {
    let model: OutlineModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    column
                        .frame(maxWidth: 720)
                        .padding(.horizontal, Theme.s6)
                        .frame(maxWidth: .infinity)
                }
                .onChange(of: model.selection) { _, s in
                    if let s { proxy.scrollTo(DisplayRow.key(.task(s))) }
                }
            }
            .overlay(alignment: .bottom) {
                if let t = model.toast { ToastView(toast: t, model: model).id(t.id).padding(.bottom, Theme.s4) }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            hintBar
        }
        .background(Theme.surface)
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: Toolbar (52h)

    private var toolbar: some View {
        HStack(spacing: 6) {
            let crumbs = model.crumbs
            ForEach(Array(crumbs.enumerated()), id: \.offset) { i, name in
                if i > 0 { Text("/").foregroundStyle(Theme.inkFaint) }
                let last = i == crumbs.count - 1
                Button { if !last { model.zoom(toLevel: i) } } label: {
                    Text(name).foregroundStyle(last ? Theme.ink : Theme.inkMute)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .font(Theme.bodyFont)
        .padding(.leading, 84).padding(.trailing, Theme.s6)
        .frame(height: 52)
    }

    // MARK: Content column

    private var column: some View {
        let rows = model.displayRows
        let branch = model.selectedBranch
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.title).font(.system(size: 36, weight: .light)).tracking(-0.7)
                    .foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                Text("\(model.openCount) open").font(Theme.captionFont).foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, Theme.s2).padding(.top, 40).padding(.bottom, Theme.s4)

            VStack(spacing: 0) {
                ForEach(rows) { d in
                    if d.ghost != nil {
                        GhostRowView(display: d, model: model)
                    } else {
                        RowView(row: d.row, model: model, branch: branch).id(d.id)
                    }
                }
            }
            .coordinateSpace(name: "rows")
            .overlay(alignment: .topLeading) { dragOverlay }

            if model.openCount == 0 && model.draft == nil { EmptyState(name: model.title).id(model.zoomPath) }
            Color.clear.frame(height: 64)
        }
    }

    /// Lifted row (white, hairline, shadow) and the 2px accent drop line with a 6px ring (D15 target).
    @ViewBuilder private var dragOverlay: some View {
        if let d = model.drag, let i = model.realRows.firstIndex(where: { $0.id == .task(d.id) }) {
            let row = model.realRows[i]
            RowView(row: row, model: model, branch: [], lifted: true)
                .offset(y: CGFloat(i) * Theme.rowHeight + d.dy)
                .allowsHitTesting(false)
            if let t = d.target {
                HStack(spacing: 0) {
                    Circle().strokeBorder(Theme.accent, lineWidth: 2).frame(width: 6, height: 6)
                    Rectangle().fill(Theme.accent).frame(height: 2)
                }
                .padding(.leading, 8 + 24 * CGFloat(t.depth))
                .offset(y: CGFloat(t.gap) * Theme.rowHeight - 3)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Hint bar (44h)

    private var hintBar: some View {
        HStack(spacing: Theme.s4) {
            Spacer()
            ForEach([("⇥", "Indent"), ("⇧⇥", "Outdent"), ("⌘↵", "Complete"), ("⌘.", "Collapse"),
                     ("⌥⌘↑↓", "Move"), ("⌘]", "Zoom in")], id: \.0) { key, label in
                HStack(spacing: 6) {
                    Keycap(text: key)
                    Text(label).font(Theme.captionFont).foregroundStyle(Theme.inkMute)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.s6)
        .frame(height: 44)
    }
}

// MARK: Rows

struct RowAnim { var fill = 0.0, scale = 1.0, fade = 0.0, strike = 0.0 }

private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

/// Strike & Fold, DESIGN "Completion": fill 0-90ms (scale 1>1.12>1), strike 30-150, ink-faint 90-160,
/// fold 160-280 (height, opacity, x+6). Children offset 40ms each; the branch folds together.
/// Reduce Motion: instant fill + strike, 400ms hold, 120ms opacity fade, one-frame reflow.
struct GhostRowView: View {
    let display: DisplayRow
    let model: OutlineModel

    var body: some View {
        let g = display.ghost!
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(g.start) * 1000
            var a = RowAnim(), height = 1.0, opacity = 1.0, dx = 0.0
            if g.reduceMotion {
                a = RowAnim(fill: 1, scale: 1, fade: 0, strike: 1)
                opacity = 1 - clamp((t - 400) / 120)
                height = t >= 520 ? 0 : 1
            } else {
                let tt = t - 40 * Double(display.index)
                a.fill = clamp(tt / 90)
                a.scale = 1 + 0.12 * sin(Double.pi * clamp(tt / 90))
                a.strike = clamp((tt - 30) / 120)
                a.fade = clamp((tt - 90) / 70)
                let f = clamp((t - g.foldStart) / 120)
                let e = f * f * (3 - 2 * f)
                height = 1 - e; opacity = 1 - e; dx = 6 * e
            }
            return RowView(row: display.row, model: model, branch: [], anim: a)
                .frame(height: Theme.rowHeight * height, alignment: .top)
                .clipped()
                .opacity(opacity)
                .offset(x: dx)
        }
    }
}

struct RowView: View {
    let row: FlatRow
    let model: OutlineModel
    let branch: Set<TaskID>
    var anim: RowAnim? = nil
    var lifted = false
    @State private var hover = false

    private var dragging: Bool { model.drag?.id == row.task?.id && !lifted }
    private var isDraft: Bool { row.task == nil }
    private var selected: Bool { anim == nil && !lifted && !isDraft && model.selection == row.task?.id }
    private var editingMe: Bool {
        anim == nil && !lifted && model.editing == (isDraft ? .draft : .task(row.task!.id))
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 24 * CGFloat(row.depth))
            chevron.frame(width: 16, height: 16)
            Color.clear.frame(width: 8)
            marker.frame(width: 16, height: 16)
            Color.clear.frame(width: 8)
            label
            Spacer(minLength: Theme.s2)
            if let t = row.task, t.collapsed, row.childCount > 0, anim == nil {
                Text("\(row.descendantCount)").font(Theme.captionFont).foregroundStyle(Theme.inkFaint)
            }
            if let t = row.task, !t.isInbox, anim == nil, !lifted { handle(t.id) }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.rowHeight)
        .background(lifted ? Theme.surface : selected || editingMe ? Theme.accentWash : hover ? Theme.surfaceSunk : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.rRow))
        .overlay(RoundedRectangle(cornerRadius: Theme.rRow).strokeBorder(lifted ? Theme.hairline : .clear, lineWidth: 1))
        .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: 12, y: 6)
        .overlay(alignment: .leading) { if !lifted { guides } }
        .opacity(dragging ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if let id = row.task?.id { model.click(id) } }
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.task?.title ?? "New task")
    }

    /// 6-dot grip, visible on hover; drags the row (D15). Stays hit-testable while hidden so a drag survives leaving the row.
    private func handle(_ id: TaskID) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2) { Circle().frame(width: 2.5, height: 2.5); Circle().frame(width: 2.5, height: 2.5) }
            }
        }
        .foregroundStyle(Theme.inkFaint)
        .frame(width: 16, height: 24)
        .contentShape(Rectangle())
        .opacity(hover || dragging ? 1 : 0)
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("rows"))
            .onChanged { model.dragChanged(id, location: $0.location, translation: $0.translation) }
            .onEnded { _ in model.dragEnded() })
        .accessibilityHidden(true)
    }

    /// 1px hairline through each ancestor's chevron centre; accent on the selection's branch.
    private var guides: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(row.ancestors.enumerated()), id: \.offset) { k, a in
                Rectangle()
                    .fill(branch.contains(a) ? Theme.accent : Theme.hairline)
                    .frame(width: 1)
                    .offset(x: 8 + 24 * CGFloat(k) + 8 - 0.5)
            }
        }
    }

    @ViewBuilder private var chevron: some View {
        if let t = row.task, row.childCount > 0, anim == nil {
            Button { model.toggleCollapse(t.id) } label: {
                Image(systemName: t.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(width: 16, height: 16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.collapsed ? "Expand" : "Collapse")
        } else { Color.clear }
    }

    @ViewBuilder private var marker: some View {
        if row.task?.isInbox == true {
            Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(selected ? Theme.accent : Theme.inkMute)
        } else {
            let circle = ZStack {
                Circle().strokeBorder(selected || editingMe ? Theme.accent : Theme.inkFaint, lineWidth: 1.5)
                if let a = anim {
                    Circle().fill(Theme.accent).opacity(a.fill * (1 - a.fade))
                    Circle().fill(Theme.inkFaint).opacity(a.fill * a.fade)
                }
            }
            .frame(width: 16, height: 16)
            .scaleEffect(anim?.scale ?? 1)
            if let id = row.task?.id, anim == nil {
                Button { model.complete(id) } label: { circle.contentShape(Circle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Complete")
            } else { circle }
        }
    }

    @ViewBuilder private var label: some View {
        if editingMe {
            EditField(model: model, editing: isDraft ? .draft : .task(row.task!.id))
                .frame(maxWidth: .infinity, minHeight: 22)
        } else {
            let title = row.task?.title ?? ""
            let a = anim ?? RowAnim()
            ZStack(alignment: .leading) {
                Text(title).foregroundStyle(Theme.ink).opacity(1 - a.fade)
                if a.fade > 0 { Text(title).foregroundStyle(Theme.inkFaint).opacity(a.fade) }
            }
            .font(Theme.rowFont)
            .lineLimit(1)
            .overlay(alignment: .leading) {
                if a.strike > 0 {
                    GeometryReader { g in
                        Rectangle().fill(a.fade > 0.5 ? Theme.inkFaint : Theme.ink)
                            .frame(width: g.size.width * a.strike, height: 1.5)
                            .position(x: g.size.width * a.strike / 2, y: g.size.height / 2)
                    }
                }
            }
        }
    }
}

struct ToastView: View {
    let toast: Toast
    let model: OutlineModel
    @State private var hover = false
    @State private var shown = false

    var body: some View {
        HStack(spacing: 12) {
            Text("Done · \(toast.title)").lineLimit(1)
            Text("⌘Z Undo").font(Theme.keycapFont).opacity(0.6)
        }
        .font(Theme.bodyFont)
        .foregroundStyle(Theme.surface)
        .padding(.horizontal, Theme.s4).padding(.vertical, 10)
        .background(Theme.ink, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .offset(y: shown || Theme.reduceMotion ? 0 : 8)   // rise 8px / 160ms; opacity only with Reduce Motion
        .opacity(shown ? 1 : 0)
        .onHover { hover = $0 }
        .onAppear { withAnimation(.easeOut(duration: 0.16)) { shown = true } }
        .task {  // holds 4s, paused while hovered
            var left = 4.0
            while left > 0 {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                if !hover { left -= 0.1 }
            }
            model.dismissToast(toast.id)
        }
    }
}

struct EmptyState: View {
    let name: String
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(spacing: Theme.s3) {
                Text("All clear.").font(.system(size: 32, weight: .light)).foregroundStyle(Theme.ink)
                Image(systemName: "checkmark.circle").font(.system(size: 24, weight: .light))
                    .foregroundStyle(Theme.inkFaint)
            }
            Text("Nothing in \(name) is waiting on you. Enjoy it, or press ↵ to add the next thing.")
                .font(Theme.bodyFont).foregroundStyle(Theme.inkMute)
        }
        .padding(.horizontal, Theme.s2).padding(.top, 48)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.3).delay(0.4)) { shown = true } }
    }
}

// MARK: Inline editor

/// Single-line NSTextField: gives us caret position (split at caret), accent caret and exact key commands.
struct EditField: NSViewRepresentable {
    let model: OutlineModel
    let editing: Editing

    func makeCoordinator() -> Coordinator { Coordinator(model: model, editing: editing) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: model.editText)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 15)
        f.textColor = Theme.nsInk
        f.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        f.placeholderString = "New task"
        f.delegate = context.coordinator
        DispatchQueue.main.async { [model] in
            guard let w = f.window else { return }
            w.makeFirstResponder(f)
            guard let ed = f.currentEditor() as? NSTextView else { return }
            ed.insertionPointColor = Theme.nsAccent
            let end = model.editCaretAtStart ? 0 : (f.stringValue as NSString).length
            ed.setSelectedRange(NSRange(location: end, length: 0))
            if let p = model.pendingInsert {
                ed.insertText(p, replacementRange: ed.selectedRange())
                model.pendingInsert = nil
            }
        }
        return f
    }

    func updateNSView(_ nsView: NSTextField, context: Context) { context.coordinator.editing = editing }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: OutlineModel
        var editing: Editing
        init(model: OutlineModel, editing: Editing) { self.model = model; self.editing = editing }

        func controlTextDidChange(_ n: Notification) {
            if let f = n.object as? NSTextField { model.editText = f.stringValue }
        }
        func controlTextDidEndEditing(_ n: Notification) { model.fieldDidEnd(editing) }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)): model.splitEditing(caret: textView.selectedRange().location)
            case #selector(NSResponder.insertTab(_:)): model.indentCurrent()
            case #selector(NSResponder.insertBacktab(_:)): model.outdentCurrent()
            case #selector(NSResponder.cancelOperation(_:)): model.commitEditing()
            case #selector(NSResponder.moveUp(_:)): model.moveSelection(-1)
            case #selector(NSResponder.moveDown(_:)): model.moveSelection(1)
            default: return false
            }
            return true
        }
    }
}
