import AppKit
import HushCore
import SwiftUI

private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
private func ease(_ f: Double) -> Double { f * f * (3 - 2 * f) }

struct RowFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct OutlineView: View {
    let model: OutlineModel
    @AppStorage("showMomentum") private var showMomentum = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(Theme.hairline).frame(height: 1)
                if model.focus != nil {
                    FocusView(model: model).transition(.opacity)
                } else {
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
                    .transition(.opacity)
                }
                Rectangle().fill(Theme.hairline).frame(height: 1)
                hintBar
            }
            if model.showShortcuts { ShortcutsSheet(model: model).transition(.opacity) }
        }
        .background(Theme.surface)
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: Toolbar (52h)

    @ViewBuilder private var toolbar: some View {
        if model.focus != nil {
            Text("FOCUS").font(.geist(size: 11, design: .monospaced)).tracking(2.2)
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity).frame(height: 52)
        } else {
            HStack(spacing: 6) {
                let crumbs = model.crumbs
                ForEach(Array(crumbs.enumerated()), id: \.offset) { i, name in
                    if i > 0 { Text("/").foregroundStyle(Theme.inkFaint) }
                    let last = i == crumbs.count - 1
                    Button { if !last { model.zoom(toLevel: i) } } label: {
                        Text(name).fontWeight(last ? .medium : .regular)
                            .foregroundStyle(last ? Theme.ink : Theme.inkMute).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(last ? "Current level, \(name)" : "Go to \(name)")
                }
                Spacer(minLength: Theme.s4)
                FindField(model: model)
                if showMomentum && model.todayCount > 0 { MomentumMarks(model: model).padding(.leading, Theme.s3) }
            }
            .font(Theme.bodyFont)
            .padding(.leading, 84).padding(.trailing, Theme.s6)
            .frame(height: 52)
        }
    }

    // MARK: Content column

    private var column: some View {
        let rows = model.displayRows
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.title).font(.geist(size: 36, weight: .semibold)).tracking(-0.7)
                    .foregroundStyle(Theme.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("\(model.openCount) open").font(Theme.captionFont).foregroundStyle(Theme.inkFaint)
            }
            .padding(.leading, 32).padding(.trailing, Theme.s2).padding(.top, 45).padding(.bottom, 25)

            VStack(spacing: 0) {
                ForEach(rows) { d in
                    if d.ghost != nil {
                        GhostRowView(display: d, model: model)
                    } else {
                        RowView(row: d.row, model: model).id(d.id)
                            .background(GeometryReader { g in
                                Color.clear.preference(key: RowFramesKey.self, value: [d.id: g.frame(in: .named("rows"))])
                            })
                    }
                }
            }
            .coordinateSpace(name: "rows")
            .onPreferenceChange(RowFramesKey.self) { model.rowFrames = $0 }
            .overlay(alignment: .topLeading) { dragOverlay }

            if !model.isFinding && model.draft == nil { AddRow(model: model) }
            if model.isFinding && model.realRows.isEmpty {
                Text("No open tasks match “\(model.findQuery)”.")
                    .font(Theme.bodyFont).foregroundStyle(Theme.inkFaint)
                    .padding(.horizontal, Theme.s2).padding(.top, Theme.s3)
            } else if !model.isFinding && model.openCount == 0 && model.draft == nil {
                EmptyState(name: model.title).id(model.zoomPath)
            }
            Color.clear.frame(height: 64)
        }
    }

    /// Lifted row (white, hairline, shadow) and the 2px accent drop line with a 6px ring (D15 target).
    @ViewBuilder private var dragOverlay: some View {
        if let d = model.drag, let row = model.realRows.first(where: { $0.id == .task(d.id) }) {
            RowView(row: row, model: model, lifted: true)
                .offset(y: d.originY + d.dy)
                .allowsHitTesting(false)
            if let t = d.target {
                HStack(spacing: 0) {
                    Circle().strokeBorder(Theme.accent, lineWidth: 2).frame(width: 6, height: 6)
                    Rectangle().fill(Theme.accent).frame(height: 2)
                }
                .padding(.leading, 8 + 24 * CGFloat(t.depth))
                .offset(y: t.y - 3)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Hint bar (44h)

    private var hintBar: some View {
        let items: [(String, String)] = model.focus != nil
            ? [("⌘↵", "Done, show next"), ("↓", "Skip for now"), ("esc", "Back to outline")]
            : [("⇥", "Indent"), ("⇧⇥", "Outdent"), ("⌘↵", "Complete"), ("⌘.", "Collapse"),
               ("⌥⌘↑↓", "Move"), ("⌘]", "Zoom in"), ("⌘/", "All shortcuts")]
        return HStack(spacing: 22) {
            Spacer()
            ForEach(items, id: \.0) { key, label in
                HStack(spacing: 6) {
                    Keycap(text: key)
                    Text(label).font(.geist(size: 12.5)).foregroundStyle(Theme.inkMute)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.s6)
        .frame(height: 44)
    }
}

// MARK: Toolbar pieces

/// ⌘F: 200x26 field. Typing filters the outline; ↑↓ ↵ Esc are handled by the model's key monitor.
struct FindField: View {
    let model: OutlineModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.geist(size: 11)).foregroundStyle(Theme.inkFaint)
            TextField("", text: Binding(get: { model.find }, set: { model.setFind($0) }),
                      prompt: Text("Find").foregroundColor(Theme.inkFaint))
                .textFieldStyle(.plain).font(.geist(size: 13)).foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .focused($focused)
                .accessibilityLabel("Find in outline")
            if model.find.isEmpty {
                Text("⌘F").font(.geist(size: 11)).foregroundStyle(Theme.inkFaint)
            } else {
                Button { model.clearFind() } label: {
                    Image(systemName: "xmark.circle.fill").font(.geist(size: 11)).foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain).accessibilityLabel("Clear find")
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 200, height: 26)
        .background(Theme.surfaceSunk, in: RoundedRectangle(cornerRadius: Theme.rRow))
        .overlay(RoundedRectangle(cornerRadius: Theme.rRow).strokeBorder(focused ? Theme.accent : Theme.hairline, lineWidth: 1))
        .onChange(of: model.findFocusTick) { focused = true }
        .onChange(of: model.findBlurTick) { focused = false }
        .onChange(of: focused) { _, f in model.findActive = f }
    }
}

/// Quiet Momentum: up to 8 bars + "N today". The newest bar grows in at +90ms of Strike & Fold, accent -> ink-mute over 600ms.
struct MomentumMarks: View {
    let model: OutlineModel

    var body: some View {
        let n = model.todayCount
        HStack(spacing: Theme.s2) {
            HStack(spacing: 3) {
                ForEach(0..<min(n, 8), id: \.self) { i in
                    Mark(pulse: i == min(n, 8) - 1 ? model.momentumPulse : nil)
                }
            }
            Text("\(n) today").font(Theme.captionFont).foregroundStyle(Theme.inkMute)
        }
        .contentShape(Rectangle())
        .background(ViewAnchor { model.marksAnchor = $0 })
        .onTapGesture { _ = model.showClosureFromMarks() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n) finished today")
        .accessibilityAddTraits(.isButton)
    }

    private struct Mark: View {
        let pulse: Date?
        var body: some View {
            if let pulse, Date().timeIntervalSince(pulse) < 1.2, !Theme.reduceMotion {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSince(pulse) - 0.09
                    bar(grow: clamp(t / 0.16), accent: 1 - clamp(t / 0.6))
                }
            } else { bar(grow: 1, accent: 0) }
        }
        private func bar(grow: Double, accent: Double) -> some View {
            ZStack {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.inkMute)
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent).opacity(accent)
            }
            .frame(width: 3, height: 11)
            .scaleEffect(y: grow, anchor: .bottom)
        }
    }
}

struct ViewAnchor: NSViewRepresentable {
    let onView: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onView(v) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: Rows

struct RowAnim { var fill = 0.0, scale = 1.0, fade = 0.0, strike = 0.0 }

/// Strike & Fold, DESIGN "Completion": fill 0-90ms (scale 1>1.12>1), strike 30-150, ink-faint 90-160,
/// fold 160-280 (height, opacity, x+6). Children offset 40ms each; the branch folds together.
/// Reduce Motion: instant fill + strike, 400ms hold, 120ms opacity fade, one-frame reflow.
struct GhostRowView: View {
    let display: DisplayRow
    let model: OutlineModel

    var body: some View {
        let g = display.ghost!
        let natural = display.index < g.heights.count ? g.heights[display.index] : Theme.rowHeight
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
                let e = ease(clamp((t - g.foldStart) / 120))
                height = 1 - e; opacity = 1 - e; dx = 6 * e
            }
            return RowView(row: display.row, model: model, anim: a)
                .frame(height: natural * height, alignment: .top)
                .clipped()
                .opacity(opacity)
                .offset(x: dx)
        }
    }
}

struct RowView: View {
    let row: FlatRow
    let model: OutlineModel
    var anim: RowAnim? = nil
    var lifted = false
    @State private var hover = false

    private var dragging: Bool { model.drag?.id == row.task?.id && !lifted }
    private var isDraft: Bool { row.task == nil }
    private var editingMe: Bool {
        anim == nil && !lifted && model.editing == (isDraft ? .draft : .task(row.task!.id))
    }
    /// The single selected row. Never while editing (the edited row is plain), never an ancestor.
    private var selected: Bool {
        anim == nil && !lifted && !isDraft && model.editing == nil && model.selection == row.task?.id
    }
    private var interactive: Bool { anim == nil && !lifted && !model.isFinding }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 24 * CGFloat(row.depth))   // indent sits outside the wash
                rowBody
            }
            if !lifted { guides }
        }
        .opacity(dragging ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if let id = row.task?.id { model.click(id) } }
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// [chevron 16][circle 16][text flex][trailing]
    private var rowBody: some View {
        HStack(alignment: .top, spacing: 0) {
            chevron.frame(width: 16, height: 22)
            Color.clear.frame(width: 8)
            marker.frame(width: 16, height: 22)
            Color.clear.frame(width: 8)
            label.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: Theme.s2)
            if let t = row.task, t.collapsed, row.childCount > 0, anim == nil {
                Text(selected || hover ? "\(row.descendantCount) inside" : "\(row.descendantCount)")
                    .font(Theme.captionFont).foregroundStyle(Theme.inkFaint)
                    .frame(height: 22)
            }
            if let t = row.task, !t.isInbox, interactive { handle(t.id) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: Theme.rowHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: Theme.rRow)
                .fill(lifted ? Theme.surface : selected ? Theme.selection : hover && !editingMe && anim == nil ? Theme.hover : .clear)
                .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: 12, y: 6)   // shadow on the shape only, never the text
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.rRow).strokeBorder(lifted ? Theme.hairline : .clear, lineWidth: 1))
    }

    private var a11yLabel: String {
        guard let t = row.task else { return "New task" }
        var s = "\(t.title), level \(row.depth + 1)"
        if row.descendantCount > 0 { s += ", \(row.descendantCount) open inside" }
        if t.collapsed && row.childCount > 0 { s += ", collapsed" }
        return s
    }

    /// 6-dot grip, visible on hover; drags the row (D15). Stays hit-testable while hidden so a drag survives leaving the row.
    private func handle(_ id: TaskID) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2) { Circle().frame(width: 2.5, height: 2.5); Circle().frame(width: 2.5, height: 2.5) }
            }
        }
        .foregroundStyle(Theme.inkFaint)
        .frame(width: 16, height: 22)
        .contentShape(Rectangle())
        .opacity(hover || dragging ? 1 : 0)
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("rows"))
            .onChanged { model.dragChanged(id, location: $0.location, translation: $0.translation) }
            .onEnded { _ in model.dragEnded() })
        .accessibilityHidden(true)
    }

    /// 1px hairline through each ancestor's chevron centre (neutral always: an accent branch read as a stray blue bar).
    private var guides: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(row.ancestors.enumerated()), id: \.offset) { k, a in
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1)
                    .offset(x: 8 + 24 * CGFloat(k) + 8 - 0.5)
            }
        }
    }

    @ViewBuilder private var chevron: some View {
        if let t = row.task, row.childCount > 0, anim == nil, !lifted {
            Button { model.toggleCollapse(t.id) } label: {
                Image(systemName: t.collapsed ? "chevron.right" : "chevron.down")
                    .font(.geist(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(width: 16, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.collapsed ? "Expand \(t.title)" : "Collapse \(t.title)")
        } else { Color.clear }
    }

    @ViewBuilder private var marker: some View {
        if row.task?.isInbox == true {
            Image(systemName: "folder").font(.geist(size: 13)).foregroundStyle(selected ? Theme.ink : Theme.inkMute)
                .frame(height: 22)
        } else if isDraft {
            DashedCircle().frame(width: 16, height: 22)
        } else {
            let circle = ZStack {
                Circle().strokeBorder(selected ? Theme.inkMute : Theme.inkFaint, lineWidth: 1.5)
                if let a = anim {
                    Circle().fill(Theme.accent).opacity(a.fill * (1 - a.fade))
                    Circle().fill(Theme.inkFaint).opacity(a.fill * a.fade)
                }
            }
            .frame(width: 16, height: 16)
            .scaleEffect(anim?.scale ?? 1)
            .frame(height: 22)
            if let t = row.task, anim == nil, !lifted {
                Button { model.complete(t.id) } label: { circle.contentShape(Circle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Complete \(t.title)")
            } else { circle }
        }
    }

    @ViewBuilder private var label: some View {
        if editingMe {
            EditField(model: model, editing: isDraft ? .draft : .task(row.task!.id), text: model.editText)
        } else {
            let title = row.task?.title ?? ""
            let a = anim ?? RowAnim()
            let dimmed = row.findState == .ancestor
            ZStack(alignment: .leading) {
                text(title).foregroundStyle(dimmed ? Theme.inkFaint : Theme.ink).opacity(1 - a.fade)
                if a.fade > 0 { text(title).foregroundStyle(Theme.inkFaint).opacity(a.fade) }
            }
            .font(Theme.rowFont)
            .lineSpacing(0)
            .fixedSize(horizontal: false, vertical: true)       // wrap; the row grows in 22pt steps
            .frame(minHeight: 22)                               // centre a single line on the 16pt circle
            .overlay(alignment: .leading) {
                if a.strike > 0 {
                    GeometryReader { g in
                        Rectangle().fill(a.fade > 0.5 ? Theme.inkFaint : Theme.ink)
                            .frame(width: g.size.width * a.strike, height: 1.5)
                            .position(x: g.size.width * a.strike / 2, y: 11)
                    }
                }
            }
        }
    }

    /// Match substring in bold while finding.
    private func text(_ title: String) -> Text {
        guard row.findState == .match,
              let r = title.range(of: model.findQuery, options: [.caseInsensitive, .diacriticInsensitive]) else { return Text(title) }
        return Text(title[..<r.lowerBound]) + Text(title[r]).fontWeight(.semibold) + Text(title[r.upperBound...])
    }
}

struct DashedCircle: View {
    var body: some View {
        Circle().strokeBorder(Theme.inkFaint.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
            .frame(width: 16, height: 16).frame(height: 22)
    }
}

/// Persistent ghost row at the end of a level: click to start a new task there.
struct AddRow: View {
    let model: OutlineModel
    @State private var hover = false
    var body: some View {
        Button { model.addAtEnd() } label: {
            HStack(spacing: 8) {
                Color.clear.frame(width: 16)
                DashedCircle().frame(width: 16)
                Text("New task").font(Theme.rowFont).foregroundStyle(Theme.inkFaint.opacity(hover ? 1 : 0.8))
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: Theme.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("New task")
    }
}

struct ToastView: View {
    let toast: Toast
    let model: OutlineModel
    @State private var hover = false
    @State private var shown = false

    var body: some View {
        HStack(spacing: 12) {
            (Text("Done").fontWeight(.medium) + Text(" · \(toast.title)").foregroundColor(Theme.surface.opacity(0.6)))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("⌘Z").font(.geist(size: 11)).padding(.horizontal, 5).frame(height: 18)
                    .background(Theme.surface.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                Text("Undo")
            }
        }
        .font(Theme.bodyFont)
        .foregroundStyle(Theme.surface)
        .padding(.leading, Theme.s4).padding(.trailing, Theme.s3).padding(.vertical, 8)
        .background { Capsule().fill(Theme.ink).shadow(color: .black.opacity(0.2), radius: 12, y: 6) }
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
        .accessibilityLabel("Done, \(toast.title). Press Command Z to undo.")
    }
}

struct EmptyState: View {
    let name: String
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(spacing: Theme.s3) {
                Text("All clear.").font(.geist(size: 32, weight: .semibold)).foregroundStyle(Theme.ink)
                Image(systemName: "checkmark.circle").font(.geist(size: 24, ))
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

// MARK: Focus Mode

struct FocusView: View {
    let model: OutlineModel

    var body: some View {
        let f = model.focus ?? FocusSession()
        let motion = !Theme.reduceMotion
        TimelineView(.animation(paused: f.outgoing == nil)) { ctx in
            let t = f.outgoing == nil ? 10_000 : ctx.date.timeIntervalSince(f.start) * 1000
            let out = f.outgoing
            // outgoing: fill + strike 0-160, then lifts -24px / fades 160-360; incoming rises +24px from 280-480.
            // Reduce Motion: crossfade only.
            let lift = motion ? ease(clamp((t - 160) / 200)) : clamp(t / 200)
            let rise = motion ? ease(clamp((t - 280) / 200)) : clamp(t / 200)
            let strike = motion ? clamp(t / 160) : 0
            ZStack {
                if let out {
                    FocusBlock(snap: out, fill: strike, strike: strike)
                        .offset(y: motion ? -24 * lift : 0).opacity(1 - lift)
                }
                if let c = f.current, let s = model.snap(c) {
                    FocusBlock(snap: s, fill: 0, strike: 0)
                        .offset(y: motion ? 24 * (1 - rise) : 0).opacity(rise)
                } else {
                    VStack(spacing: Theme.s2) {
                        Text("That's everything.").font(.geist(size: 24, )).foregroundStyle(Theme.ink)
                        Text("\(f.finished) finished in this focus session").font(Theme.captionFont)
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .opacity(rise)
                }
            }
            .frame(width: 640)
            .overlay(alignment: .top) { context(model.focusContext().above, above: true) }
            .overlay(alignment: .bottom) { context(model.focusContext().below, above: false) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { upNext(f) }
        }
        .clipped()
    }

    /// Ghost outline rows at 10% opacity above / below the focused task.
    private func context(_ rows: [(String, Int)], above: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                Text(r.0).font(Theme.rowFont).foregroundStyle(Theme.ink).lineLimit(1)
                    .padding(.leading, 24 * CGFloat(r.1)).frame(height: Theme.rowHeight, alignment: .leading)
            }
        }
        .frame(width: 640, alignment: .leading)
        .opacity(0.10)
        .alignmentGuide(above ? .top : .bottom) { above ? $0[.bottom] + 56 : $0[.top] - 56 }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func upNext(_ f: FocusSession) -> some View {
        if f.current != nil, let q = f.queued, let s = model.snap(q) {
            HStack(spacing: 8) {
                Text("Up next").foregroundStyle(Theme.inkFaint)
                Text(s.title).foregroundStyle(Theme.inkMute).lineLimit(1)
            }
            .font(Theme.captionFont)
            .frame(width: 640, alignment: .leading)
            .padding(.bottom, Theme.s6)
        }
    }
}

struct FocusBlock: View {
    let snap: FocusSnap
    let fill: Double
    let strike: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text(snap.crumb).font(Theme.captionFont).foregroundStyle(Theme.inkFaint).lineLimit(1)
            HStack(alignment: .top, spacing: Theme.s4) {
                ZStack {
                    Circle().strokeBorder(Theme.accent, lineWidth: 2)
                    Circle().fill(Theme.accent).opacity(fill)
                }
                .frame(width: 28, height: 28).padding(.top, 13)
                Text(snap.title).font(.geist(size: 44, weight: .semibold)).tracking(-1.1)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay(alignment: .leading) {
                        if strike > 0 {
                            Text(snap.title).font(.geist(size: 44, weight: .semibold)).tracking(-1.1)
                                .strikethrough(true, color: Theme.ink).foregroundColor(.clear)
                                .fixedSize(horizontal: false, vertical: true)
                                .mask(alignment: .leading) {
                                    GeometryReader { g in Rectangle().frame(width: g.size.width * strike) }
                                }
                        }
                    }
            }
            if !snap.note.isEmpty {
                Text(snap.note).font(.geist(size: 15)).lineSpacing(4).foregroundStyle(Theme.inkMute)
                    .padding(.leading, 48)
            }
        }
        .frame(width: 640, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focused: \(snap.title)")
    }
}

// MARK: Shortcuts sheet (⌘/)

struct ShortcutsSheet: View {
    let model: OutlineModel
    @State private var listHeight: CGFloat = 520

    private var groups: [(String, [(String, String)])] {
        [("Capture", [(HotKey.shared.display, "Capture from anywhere"), ("↵", "Save to Inbox"), ("⇥", "Details"),
                      ("⌥↵", "Save and keep open"), ("esc", "Dismiss")]),
         ("Outline", [("↑ ↓", "Select"), ("↵", "New task below"), ("⇥ / ⇧⇥", "Indent / outdent"), ("⌘↵", "Complete"),
                      ("⌘.", "Collapse"), ("⌘→", "Expand"), ("⌥⌘↑ ↓", "Move"), ("⌘⌫", "Delete"),
                      ("⌘] / ⌘[", "Zoom in / out"), ("⌘Z / ⇧⌘Z", "Undo / redo")]),
         ("Views", [("⌘F", "Find"), ("⌘Y", "History"), ("⌘D", "Today"), ("⌘⇧F", "Focus"), ("⌘/", "This sheet")])]
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            ForEach(groups, id: \.0) { name, rows in
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.uppercased()).font(.geist(size: 10, design: .monospaced)).tracking(1)
                        .foregroundStyle(Theme.inkFaint)
                    ForEach(rows, id: \.0) { key, action in
                        HStack(spacing: Theme.s3) {
                            HStack { Spacer(minLength: 0); Keycap(text: key) }.frame(width: 120)
                            Text(action).font(Theme.bodyFont).foregroundStyle(Theme.ink)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
                .onTapGesture { model.showShortcuts = false }
            VStack(alignment: .leading, spacing: Theme.s4) {
                Text("Keyboard").font(.geist(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                ScrollView {   // sized to its content; scrolls only when the window is too short
                    list.background(GeometryReader { g in Color.clear.onAppear { listHeight = g.size.height } })
                }
                .frame(height: min(listHeight, max(200, geo.size.height - 200)))
            }
            .padding(Theme.s6)
            .frame(width: 480)
            .background {
                RoundedRectangle(cornerRadius: Theme.rModal).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.28), radius: 32, y: 16)
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.rModal).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        }
    }
}

// MARK: Inline editor

/// Field editor whose caret is only as tall as the text (a slim accent caret, not a full-row bar).
final class CaretTextView: NSTextView {
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var r = rect
        let h = min(rect.height, ceil((font ?? Theme.nsSans(14)).boundingRectForFont.height))
        r.origin.y += (rect.height - h) / 2
        r.size.height = h
        super.drawInsertionPoint(in: r, color: color, turnedOn: flag)
    }
}

final class CaretCell: NSTextFieldCell {
    private let editor: CaretTextView = { let t = CaretTextView(); t.isFieldEditor = true; return t }()
    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

final class EditTextField: NSTextField {
    override class var cellClass: AnyClass? { get { CaretCell.self } set {} }
}

/// Wrapping NSTextField: gives us caret position (split at caret), accent caret and exact key commands.
struct EditField: NSViewRepresentable {
    let model: OutlineModel
    let editing: Editing
    let text: String   // read by RowView so SwiftUI re-measures as the title grows

    func makeCoordinator() -> Coordinator { Coordinator(model: model, editing: editing) }

    func makeNSView(context: Context) -> NSTextField {
        let f = EditTextField(string: model.editText)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = Theme.nsSans(14)
        f.textColor = Theme.nsInk
        f.lineBreakMode = .byWordWrapping
        f.cell?.wraps = true
        f.cell?.isScrollable = false
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

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        let w = proposal.width ?? 400
        guard w.isFinite, w > 0, let cell = nsView.cell else { return nil }
        let h = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: w, height: 10_000)).height
        return CGSize(width: w, height: max(22, ceil(h)))
    }

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
