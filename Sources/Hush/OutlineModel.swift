import AppKit
import HushCore
import Observation

enum RowID: Hashable { case task(TaskID), draft }
enum Editing: Equatable { case task(TaskID), draft }

/// An uncommitted new row (D12: empty new rows are never persisted).
struct Draft: Equatable { var parent: TaskID?; var after: TaskID? }

struct KeyPress {
    let code: UInt16
    let cmd, opt, shift, ctrl: Bool
    let typed: String
}

struct FlatRow: Identifiable {
    let id: RowID
    let task: TaskItem?          // nil = draft
    let depth: Int
    let ancestors: [TaskID]      // outermost first; ancestors[k] owns guide k
    let childCount: Int
    let descendantCount: Int
}

/// A row group that has already been completed in the store but is still animating out (Strike & Fold).
struct Ghost: Identifiable {
    let id = UUID()
    let start = Date()
    let rows: [FlatRow]
    let anchor: RowID?           // display row it sits right after
    let reduceMotion: Bool
    /// ms. Children strike +40ms apart, then the whole branch folds as one.
    var foldStart: Double { reduceMotion ? 520 : 160 + 40 * Double(rows.count - 1) }
    var duration: Double { reduceMotion ? 520 : foldStart + 120 }
}

struct Toast: Identifiable { let id = UUID(); let title: String }

/// D15 drop target: a gap between visible rows plus the depth chosen by horizontal drag.
struct DropTarget: Equatable {
    let gap: Int, depth: Int
    let parent: TaskID?, index: Int
}
struct DragState { let id: TaskID; var dy: CGFloat; var target: DropTarget? }

struct DisplayRow: Identifiable {
    let row: FlatRow
    let ghost: Ghost?
    let index: Int
    var id: String {
        if let ghost { return "g\(ghost.id)-\(index)" }
        return Self.key(row.id)
    }
    static func key(_ id: RowID) -> String {
        switch id { case .task(let t): "t\(t.raw)"; case .draft: "draft" }
    }
}

@MainActor @Observable
final class OutlineModel {
    @ObservationIgnored let store: TaskStore
    @ObservationIgnored private var sub: Subscription?

    private(set) var tree: [OutlineNode] = []
    private(set) var homeOpenCount = 0
    private(set) var zoomPath: [TaskID] = []
    var selection: TaskID?
    private(set) var editing: Editing?
    var editText = ""
    private(set) var draft: Draft?
    var editCaretAtStart = false
    var pendingInsert: String?
    private(set) var ghosts: [Ghost] = []
    private(set) var toast: Toast?
    private(set) var drag: DragState?
    @ObservationIgnored private var dragCancelled = false

    init(store: TaskStore) {
        self.store = store
        reload()
        selection = navRows.first?.task?.id
        sub = store.observeOutline { [weak self] _ in MainActor.assumeIsolated { self?.reload() } }
    }

    // MARK: Derived

    var zoomRoot: TaskID? { zoomPath.last }
    var zoomNode: OutlineNode? { zoomRoot.flatMap(node) }
    var title: String { zoomNode?.task.title ?? "Home" }
    var openCount: Int { zoomNode?.openDescendantCount ?? homeOpenCount }
    var crumbs: [String] { ["Home"] + zoomPath.map { node($0)?.task.title ?? "" } }

    private var zoomNodes: [OutlineNode] {
        var level = tree
        for id in zoomPath { level = level.first { $0.id == id }?.children ?? [] }
        return level
    }

    func node(_ id: TaskID) -> OutlineNode? {
        func find(_ nodes: [OutlineNode]) -> OutlineNode? {
            for n in nodes { if n.id == id { return n }; if let f = find(n.children) { return f } }
            return nil
        }
        return find(tree)
    }

    /// Visible rows of the current zoom level (no ghosts), incl. the draft row.
    var realRows: [FlatRow] {
        var out: [FlatRow] = []
        walk(zoomNodes, parent: zoomRoot, depth: 0, anc: [], &out)
        return out
    }
    private var navRows: [FlatRow] { realRows.filter { $0.task != nil } }

    private func walk(_ nodes: [OutlineNode], parent: TaskID?, depth: Int, anc: [TaskID], _ out: inout [FlatRow]) {
        func draftRow() -> FlatRow {
            FlatRow(id: .draft, task: nil, depth: depth, ancestors: anc, childCount: 0, descendantCount: 0)
        }
        if let d = draft, d.parent == parent, d.after == nil { out.append(draftRow()) }
        for n in nodes {
            out.append(FlatRow(id: .task(n.id), task: n.task, depth: depth, ancestors: anc,
                               childCount: n.children.count, descendantCount: n.openDescendantCount))
            if !n.task.collapsed { walk(n.children, parent: n.id, depth: depth + 1, anc: anc + [n.id], &out) }
            if let d = draft, d.parent == parent, d.after == n.id { out.append(draftRow()) }
        }
    }

    /// Real rows with animating ghosts spliced back in after their anchor.
    var displayRows: [DisplayRow] {
        var out = realRows.map { DisplayRow(row: $0, ghost: nil, index: 0) }
        var remaining = ghosts
        var progress = true
        while progress && !remaining.isEmpty {
            progress = false
            for g in remaining {
                let at: Int
                if let a = g.anchor {
                    guard let i = out.firstIndex(where: { $0.row.id == a }) else { continue }
                    at = i + 1
                } else { at = 0 }
                out.insert(contentsOf: g.rows.enumerated().map { DisplayRow(row: $0.element, ghost: g, index: $0.offset) }, at: at)
                remaining.removeAll { $0.id == g.id }
                progress = true
            }
        }
        return out
    }

    /// The selection and its ancestors: guides of these branches draw in accent.
    var selectedBranch: Set<TaskID> {
        guard let s = selection, let r = realRows.first(where: { $0.id == .task(s) }) else { return [] }
        return Set(r.ancestors + [s])
    }

    // MARK: Loading

    func reload() {
        let oldIndex = selection.flatMap { s in navRows.firstIndex { $0.id == .task(s) } }
        guard let t = try? store.outline(), let n = try? store.openCount() else { return }
        tree = t
        homeOpenCount = n
        var valid: [TaskID] = []
        var level = tree
        for id in zoomPath {
            guard let nd = level.first(where: { $0.id == id }) else { break }
            valid.append(id); level = nd.children
        }
        if valid != zoomPath { zoomPath = valid }
        let rows = navRows
        if let s = selection, !rows.contains(where: { $0.id == .task(s) }) {
            selection = rows.isEmpty ? nil : rows[min(oldIndex ?? 0, rows.count - 1)].task?.id
        }
        if case .task(let e) = editing, node(e) == nil { editing = nil }
    }

    private func siblings(of id: TaskID) -> (parent: TaskID?, list: [OutlineNode])? {
        func find(_ nodes: [OutlineNode], parent: TaskID?) -> (TaskID?, [OutlineNode])? {
            if nodes.contains(where: { $0.id == id }) { return (parent, nodes) }
            for n in nodes { if let f = find(n.children, parent: n.id) { return f } }
            return nil
        }
        return find(tree, parent: nil)
    }

    /// Next sibling, else previous, else parent (nil when that is the zoom root).
    private func successor(of id: TaskID) -> TaskID? {
        guard let (parent, sibs) = siblings(of: id), let i = sibs.firstIndex(where: { $0.id == id }) else { return nil }
        if i + 1 < sibs.count { return sibs[i + 1].id }
        if i > 0 { return sibs[i - 1].id }
        return parent == zoomRoot ? nil : parent
    }

    // MARK: Selection and editing

    private var current: TaskID? {
        if case .task(let id) = editing { return id }
        return selection
    }

    func click(_ id: TaskID) {
        if selection == id, editing == nil { beginEdit(id); return }
        if editing != .task(id) { commitEditing() }
        selection = id
    }

    func beginEdit(_ id: TaskID, caretAtStart: Bool = false, insert: String? = nil) {
        guard let t = node(id)?.task, !t.isInbox else { selection = id; return }
        if editing != .task(id) { commitEditing() }
        selection = id
        editing = .task(id)
        editText = t.title
        editCaretAtStart = caretAtStart
        pendingInsert = insert
    }

    /// Saves the row being edited (blur, Esc, navigation). Empty title reverts (D12); empty draft is discarded.
    func commitEditing() {
        guard let e = editing else { return }
        editing = nil
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch e {
        case .task(let id):
            guard !text.isEmpty, let old = node(id)?.task, old.title != text else { return }
            do { _ = try store.update(id, title: text) } catch {}
        case .draft:
            guard let d = draft else { return }
            draft = nil
            if text.isEmpty {
                selection = (d.after ?? d.parent).flatMap { node($0) != nil ? $0 : nil } ?? navRows.first?.task?.id
            } else if let t = try? store.create(title: text, parent: d.parent, after: d.after) {
                selection = t.id
            }
        }
        reload()
    }

    /// Field-end notification; ignored if editing has already moved on.
    func fieldDidEnd(_ e: Editing) { if editing == e { commitEditing() } }

    func moveSelection(_ delta: Int) {
        let wasEditing = editing != nil
        commitEditing()
        let rows = navRows
        guard !rows.isEmpty else { return }
        let i = selection.flatMap { s in rows.firstIndex { $0.id == .task(s) } }
        let n = i.map { min(max($0 + delta, 0), rows.count - 1) } ?? (delta > 0 ? 0 : rows.count - 1)
        guard let id = rows[n].task?.id else { return }
        if wasEditing { beginEdit(id) } else { selection = id }
    }

    private func startDraft(parent: TaskID?, after: TaskID?) {
        commitEditing()
        draft = Draft(parent: parent, after: after)
        editing = .draft
        editText = ""
        editCaretAtStart = false
        pendingInsert = nil
        selection = nil
    }

    private func newSiblingBelow() {
        if let id = selection, let (parent, _) = siblings(of: id) { startDraft(parent: parent, after: id) }
        else if zoomRoot != nil || navRows.isEmpty { startDraft(parent: zoomRoot, after: nil) }
        else { selection = navRows.first?.task?.id }
    }

    /// ↵ while editing: text after the caret moves to a new sibling below; children stay.
    func splitEditing(caret: Int) {
        guard let e = editing else { return }
        let ns = editText as NSString
        let c = min(max(caret, 0), ns.length)
        let before = ns.substring(to: c), after = ns.substring(from: c)
        let hasBefore = !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var anchor: TaskID, parent: TaskID?
        switch e {
        case .draft:
            guard hasBefore, let d = draft else { return }
            guard let t = try? store.create(title: before, parent: d.parent, after: d.after) else { return }
            (anchor, parent) = (t.id, d.parent)
            draft = nil
        case .task(let id):
            guard let t = node(id)?.task else { return }
            if !hasBefore { commitEditing(); startDraft(parent: t.parentID, after: id); return }
            do { _ = try store.update(id, title: before) } catch { return }
            (anchor, parent) = (id, t.parentID)
        }
        editing = nil
        if !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let n = try? store.create(title: after, parent: parent, after: anchor) {
            reload()
            beginEdit(n.id, caretAtStart: true)
        } else {
            reload()
            startDraft(parent: parent, after: anchor)
        }
    }

    // MARK: Structure ops (no-ops on HushError, e.g. Inbox protection)

    /// Runs `body` against the current row, keeping edit mode if it was active.
    private func mutate(_ id: TaskID, _ body: () throws -> Void) {
        let wasEditing = editing == .task(id)
        commitEditing()
        try? body()
        reload()
        if wasEditing { beginEdit(id) }
    }

    func indentCurrent() {
        if editing == .draft, var d = draft {   // ⇥ on a new empty row: nest under the previous sibling
            guard let prev = d.after, let n = node(prev) else { return }
            if n.task.collapsed { try? store.setCollapsed(prev, false) }
            d = Draft(parent: prev, after: n.children.last?.id)
            draft = d; reload(); return
        }
        guard let id = current else { return }
        mutate(id) {
            try store.indent(id)
            if let p = try store.task(id).parentID, node(p)?.task.collapsed == true { try store.setCollapsed(p, false) }
        }
    }

    func outdentCurrent() {
        if editing == .draft, let d = draft {
            guard let p = d.parent, p != zoomRoot, let (gp, _) = siblings(of: p) else { return }
            draft = Draft(parent: gp, after: p); reload(); return
        }
        guard let id = current, siblings(of: id)?.parent != zoomRoot else { return }
        mutate(id) { try store.outdent(id) }
    }

    func reorder(_ up: Bool) {
        guard let id = current else { return }
        mutate(id) { _ = up ? try store.moveUp(id) : try store.moveDown(id) }
    }

    func toggleCollapse(_ id: TaskID? = nil, expandOnly: Bool = false) {
        guard let id = id ?? current, let n = node(id), n.children.count > 0 else { return }
        let collapse = !n.task.collapsed
        if expandOnly && collapse { return }
        if collapse, let s = selection, s != id, realRows.first(where: { $0.id == .task(s) })?.ancestors.contains(id) == true {
            selection = id
        }
        try? store.setCollapsed(id, collapse)
        reload()
    }

    func deleteSelected() {
        guard editing == nil, let id = selection, node(id)?.task.isInbox == false else { return }
        let next = successor(of: id)
        guard (try? store.delete(id)) != nil else { return }
        selection = next
        reload()
    }

    // MARK: Zoom

    func zoomIn() {
        guard let id = current else { return }
        commitEditing()
        zoomPath.append(id)
        selection = navRows.first?.task?.id
    }

    func zoomOut() {
        commitEditing()
        guard let last = zoomPath.popLast() else { return }
        selection = last
    }

    /// Crumb click: level 0 = Home.
    func zoom(toLevel level: Int) {
        commitEditing()
        guard level < zoomPath.count else { return }
        let leaving = zoomPath[level]
        zoomPath.removeSubrange(level...)
        selection = leaving
    }

    // MARK: Strike & Fold

    func complete(_ id: TaskID? = nil) {
        guard let id = id ?? current else { return }
        commitEditing()
        let rows = displayRows
        guard let i = rows.firstIndex(where: { $0.ghost == nil && $0.row.id == .task(id) }),
              let t = rows[i].row.task, !t.isInbox else { return }
        let top = rows[i].row
        var slice = [top]
        var j = i + 1
        while j < rows.count, rows[j].row.depth > top.depth {
            if rows[j].ghost == nil, rows[j].row.task != nil { slice.append(rows[j].row) }
            j += 1
        }
        let anchor = i > 0 ? rows[i - 1].row.id : nil
        let next = successor(of: id)
        guard (try? store.complete(id)) != nil else { return }
        let g = Ghost(rows: slice, anchor: anchor, reduceMotion: Theme.reduceMotion)
        ghosts.append(g)
        toast = Toast(title: t.title)
        selection = next
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + (g.duration + 80) / 1000) { [weak self] in
            self?.ghosts.removeAll { $0.id == g.id }
        }
    }

    func dismissToast(_ id: UUID) { if toast?.id == id { toast = nil } }

    // MARK: Undo / redo (Core owns the stack; we reselect what it touched)

    func undo() { replay { try store.undo() } }
    func redo() { replay { try store.redo() } }

    private func replay(_ f: () throws -> [TaskID]) {
        commitEditing()
        guard let ids = try? f(), !ids.isEmpty else { return }
        toast = nil
        ghosts.removeAll { g in g.rows.contains { r in r.task.map { ids.contains($0.id) } ?? false } }
        reload()
        // Bring the first restored row into view: leave a zoom it isn't under, expand collapsed ancestors.
        if let id = ids.first(where: { node($0) != nil }), let anc = ancestors(of: id) {
            if let z = zoomRoot, !anc.contains(z) { zoomPath = [] }
            for a in anc where node(a)?.task.collapsed == true { try? store.setCollapsed(a, false) }
            reload()
            selection = id
        } else if let id = ids.first(where: { i in navRows.contains { $0.id == .task(i) } }) {
            selection = id
        }
    }

    private func ancestors(of id: TaskID) -> [TaskID]? {
        func find(_ nodes: [OutlineNode], _ path: [TaskID]) -> [TaskID]? {
            for n in nodes {
                if n.id == id { return path }
                if let f = find(n.children, path + [n.id]) { return f }
            }
            return nil
        }
        return find(tree, [])
    }

    // MARK: Drag reorder (D15)

    func dragChanged(_ id: TaskID, location: CGPoint, translation: CGSize) {
        if dragCancelled { return }
        if drag == nil { commitEditing(); selection = id }
        drag = DragState(id: id, dy: translation.height,
                         target: dropTarget(id, y: location.y, dx: translation.width))
    }

    func dragEnded() {
        defer { drag = nil; dragCancelled = false }
        guard !dragCancelled, let d = drag, let t = d.target else { return }
        let cur = siblings(of: d.id)
        if cur?.parent == t.parent, cur?.list.firstIndex(where: { $0.id == d.id }) == t.index { return } // same place
        if let p = t.parent, node(p)?.task.collapsed == true { try? store.setCollapsed(p, false) }
        try? store.move(d.id, newParent: t.parent, index: t.index)
        selection = d.id
        reload()
    }

    func cancelDrag() { if drag != nil { dragCancelled = true; drag = nil } }

    /// `y` is the pointer in rows space (row height 32, first row at 0); `dx` picks depth in 24pt steps.
    private func dropTarget(_ id: TaskID, y: CGFloat, dx: CGFloat) -> DropTarget? {
        let rows = navRows
        guard let i = rows.firstIndex(where: { $0.id == .task(id) }) else { return nil }
        var j = i
        while j + 1 < rows.count, rows[j + 1].depth > rows[i].depth { j += 1 }
        let g = min(max(Int(floor(y / Theme.rowHeight + 0.5)), 0), rows.count)
        if g > i && g <= j { return nil }                                   // inside its own subtree
        if g == 0, rows.first?.task?.isInbox == true { return nil }         // never above Inbox
        var p = g - 1; if p >= i && p <= j { p = i - 1 }
        var n = g; if n >= i && n <= j { n = j + 1 }
        let prev = p >= 0 ? rows[p] : nil
        let next = n < rows.count ? rows[n] : nil
        let maxD = prev.map { $0.depth + 1 } ?? 0
        let minD = min(next?.depth ?? 0, maxD)
        let d = min(max(rows[i].depth + Int((dx / 24).rounded()), minD), maxD)

        var parent: TaskID? = zoomRoot
        var parentIsCollapsedPrev = false
        if d > 0, let prev {
            if prev.depth == d - 1 {
                parent = prev.task?.id
                parentIsCollapsedPrev = prev.task?.collapsed == true && prev.childCount > 0
            } else { parent = prev.ancestors[d - 1] }
        }
        let sibs = (parent.flatMap(node)?.children ?? tree).filter { $0.id != id }
        let index = parentIsCollapsedPrev ? sibs.count : sibs.filter { s in
            rows.firstIndex { $0.id == .task(s.id) }.map { $0 < g } ?? false
        }.count
        return DropTarget(gap: g, depth: d, parent: parent, index: index)
    }

    // MARK: Keys

    /// Returns true if handled. While editing, plain keys (typing, ↵, ⇥, Esc, arrows) belong to the text field.
    func handle(_ k: KeyPress) -> Bool {
        let isEditing = editing != nil
        switch k.code {
        case 53 where drag != nil:                    // Esc cancels a drag
            cancelDrag(); return true
        case 6 where k.cmd && !k.opt && !isEditing:   // ⌘Z / ⇧⌘Z
            k.shift ? redo() : undo(); return true
        case 36, 76:                                  // ↵
            if k.cmd { complete(); return true }
            if isEditing { return false }
            newSiblingBelow(); return true
        case 48:                                      // ⇥
            if isEditing || k.cmd || k.opt { return false }
            k.shift ? outdentCurrent() : indentCurrent(); return true
        case 126, 125:                                // ↑ ↓
            if k.cmd && k.opt { reorder(k.code == 126); return true }
            if isEditing || k.cmd || k.opt { return false }
            moveSelection(k.code == 126 ? -1 : 1); return true
        case 47 where k.cmd:                          // ⌘.
            toggleCollapse(); return true
        case 124 where k.cmd && !k.opt && !isEditing: // ⌘→
            toggleCollapse(selection, expandOnly: true); return true
        case 51 where k.cmd && !isEditing:            // ⌘⌫
            deleteSelected(); return true
        case 30 where k.cmd:                          // ⌘]
            zoomIn(); return true
        case 33 where k.cmd:                          // ⌘[
            zoomOut(); return true
        case 49 where !isEditing && !k.cmd && !k.ctrl && !k.opt:   // Space
            if let s = selection { beginEdit(s) }
            return true
        default:
            guard !isEditing, !k.cmd, !k.ctrl, let s = selection, !k.typed.isEmpty,
                  k.typed.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) })
            else { return false }
            beginEdit(s, insert: k.typed)
            return true
        }
    }
}
