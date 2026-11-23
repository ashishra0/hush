import AppKit
import HushCore
import Observation
import SwiftUI

enum RowID: Hashable { case task(TaskID), draft }
enum Editing: Equatable { case task(TaskID), draft }

/// An uncommitted new row (D12: empty new rows are never persisted).
struct Draft: Equatable { var parent: TaskID?; var after: TaskID? }

struct KeyPress {
    let code: UInt16
    let cmd, opt, shift, ctrl: Bool
    let typed: String
}

enum FindState { case none, ancestor, match }

struct FlatRow: Identifiable {
    let id: RowID
    let task: TaskItem?          // nil = draft
    let depth: Int
    let ancestors: [TaskID]      // outermost first; ancestors[k] owns guide k
    let childCount: Int
    let descendantCount: Int
    var findState: FindState = .none
}

struct FocusSnap { let title: String; let note: String; let crumb: String }

/// Focus Mode session: one task at a time, "next" = pre-order successor.
struct FocusSession {
    var current: TaskID?          // nil = nothing left
    var queued: TaskID?
    var finished = 0
    var outgoing: FocusSnap?      // task that was just completed, animating out
    var start = Date()
    var last: TaskID?             // selected on exit when current is nil
}

/// A row group that has already been completed in the store but is still animating out (Strike & Fold).
struct Ghost: Identifiable {
    let id = UUID()
    let start = Date()
    let rows: [FlatRow]
    let anchor: RowID?           // display row it sits right after
    let heights: [CGFloat]       // natural row heights (rows can wrap)
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
    let y: CGFloat               // drop line position in rows space
}
struct DragState { let id: TaskID; var dy: CGFloat; var originY: CGFloat; var target: DropTarget? }

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
    private(set) var find = ""
    var findActive = false                      // find field has keyboard focus
    private(set) var findFocusTick = 0
    private(set) var findBlurTick = 0
    @ObservationIgnored private var preFindSelection: TaskID?
    private(set) var focus: FocusSession?
    var showShortcuts = false
    private(set) var todayCount = 0
    private(set) var momentumPulse: Date?
    @ObservationIgnored var rowFrames: [String: CGRect] = [:]
    @ObservationIgnored weak var marksAnchor: NSView?
    @ObservationIgnored var onFocusChange: (Bool) -> Void = { _ in }
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
        if isFinding { walkFind(zoomNodes, depth: 0, anc: [], &out) }
        else { walk(zoomNodes, parent: zoomRoot, depth: 0, anc: [], &out) }
        return out
    }
    /// Rows the selection can land on (only matches while finding).
    private var navRows: [FlatRow] {
        realRows.filter { $0.task != nil && (!isFinding || $0.findState == .match) }
    }

    var findQuery: String { find.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isFinding: Bool { !findQuery.isEmpty }
    var momentumVisible: Bool { UserDefaults.standard.bool(forKey: "showMomentum") && todayCount > 0 }

    /// Matches (case-insensitive substring, Inbox node itself excluded) with their ancestors, all expanded.
    private func walkFind(_ nodes: [OutlineNode], depth: Int, anc: [TaskID], _ out: inout [FlatRow]) {
        for n in nodes {
            let m = !n.task.isInbox && n.task.title.range(of: findQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            var sub: [FlatRow] = []
            walkFind(n.children, depth: depth + 1, anc: anc + [n.id], &sub)
            if m || !sub.isEmpty {
                out.append(FlatRow(id: .task(n.id), task: n.task, depth: depth, ancestors: anc, childCount: 0,
                                   descendantCount: 0, findState: m ? .match : .ancestor))
                out += sub
            }
        }
    }

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
        todayCount = (try? store.todaySummary().doneCount) ?? 0
        if var f = focus, f.outgoing == nil, let c = f.current, node(c) == nil {   // changed elsewhere
            f.current = f.queued.flatMap { node($0) != nil ? $0 : nil }
            f.queued = f.current.flatMap { focusNext(after: $0, skipSubtree: false) }
            focus = f
        }
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
        let heights = slice.map { rowFrames[DisplayRow.key($0.id)]?.height ?? Theme.rowHeight }
        let g = Ghost(rows: slice, anchor: anchor, heights: heights, reduceMotion: Theme.reduceMotion)
        ghosts.append(g)
        momentumPulse = Date()
        toast = Toast(title: t.title)
        selection = next
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + (g.duration + 80) / 1000) { [weak self] in
            self?.ghosts.removeAll { $0.id == g.id }
        }
    }

    /// Anchors the Daily Closure card to the toolbar marks (click or ⌘D).
    func showClosureFromMarks() -> Bool {
        guard momentumVisible, let v = marksAnchor, v.window != nil else { return false }
        ClosureCard.show(relativeTo: v, store: store)
        return true
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
        if let id = ids.first(where: { node($0) != nil }) { reveal(id) }
        else if let id = ids.first(where: { i in navRows.contains { $0.id == .task(i) } }) { selection = id }
    }

    /// Select `id`, leaving a zoom it isn't under and expanding collapsed ancestors so it is visible.
    func reveal(_ id: TaskID) {
        guard let anc = ancestors(of: id) else { return }
        if let z = zoomRoot, !anc.contains(z), id != z { zoomPath = [] }
        for a in anc where node(a)?.task.collapsed == true { try? store.setCollapsed(a, false) }
        reload()
        selection = id
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
        let origin = rowFrames[DisplayRow.key(.task(id))]?.minY ?? 0
        drag = DragState(id: id, dy: translation.height, originY: origin,
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

    /// `y` is the pointer in rows space; the gap is chosen against real row frames (rows can wrap); `dx` picks depth in 24pt steps.
    private func dropTarget(_ id: TaskID, y: CGFloat, dx: CGFloat) -> DropTarget? {
        let rows = navRows
        guard let i = rows.firstIndex(where: { $0.id == .task(id) }) else { return nil }
        func frame(_ k: Int) -> CGRect {
            rowFrames[DisplayRow.key(rows[k].id)] ?? CGRect(x: 0, y: CGFloat(k) * Theme.rowHeight, width: 0, height: Theme.rowHeight)
        }
        var j = i
        while j + 1 < rows.count, rows[j + 1].depth > rows[i].depth { j += 1 }
        var g = 0
        while g < rows.count, frame(g).midY < y { g += 1 }
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
        let lineY = g == 0 ? frame(0).minY : frame(g - 1).maxY
        return DropTarget(gap: g, depth: d, parent: parent, index: index, y: lineY)
    }

    // MARK: Find (⌘F)

    func focusFind() { commitEditing(); findFocusTick += 1 }

    func setFind(_ s: String) {
        if !isFinding { preFindSelection = selection }
        find = s
        let rows = navRows
        if isFinding, selection.map({ id in !rows.contains { $0.id == .task(id) } }) ?? true {
            selection = rows.first?.task?.id
        }
        if !isFinding, let p = preFindSelection { selection = p }
    }

    /// Esc: clear the filter, restore selection, hand focus back to the outline.
    func clearFind() {
        let restore = preFindSelection
        find = ""
        findBlurTick += 1
        if let r = restore, node(r) != nil { selection = r }
    }

    /// ↵: clear the filter, reveal (expand ancestors) and select the highlighted match.
    func jumpToMatch() {
        let id = isFinding ? selection : nil
        find = ""
        findBlurTick += 1
        if let id { reveal(id) } else if let r = preFindSelection { selection = r }
    }

    // MARK: Focus Mode (⌘⇧F)

    /// Whole-outline pre-order (Inbox node itself skipped, its children kept).
    private func preorder() -> [OutlineNode] {
        var out: [OutlineNode] = []
        func go(_ nodes: [OutlineNode]) { for n in nodes { if !n.task.isInbox { out.append(n) }; go(n.children) } }
        go(tree)
        return out
    }

    private func focusNext(after id: TaskID, skipSubtree: Bool) -> TaskID? {
        let flat = preorder()
        guard let i = flat.firstIndex(where: { $0.id == id }) else { return nil }
        var skip = Set<TaskID>()
        if skipSubtree { func add(_ n: OutlineNode) { skip.insert(n.id); n.children.forEach(add) }; add(flat[i]) }
        return flat[(i + 1)...].first { !skip.contains($0.id) }?.id
    }

    func snap(_ id: TaskID) -> FocusSnap? {
        guard let n = node(id) else { return nil }
        let path = (ancestors(of: id) ?? []).compactMap { node($0)?.task.title }
        let crumb = (path.isEmpty ? ["Home"] : path).joined(separator: " › ")
        return FocusSnap(title: n.task.title, note: n.task.note, crumb: crumb)
    }

    /// Up to 5 rows before / after the focused task in pre-order, for the 10% ghost context.
    func focusContext() -> (above: [(String, Int)], below: [(String, Int)]) {
        func depth(_ id: TaskID) -> Int { ancestors(of: id)?.count ?? 0 }
        let flat = preorder()
        guard let c = focus?.current, let i = flat.firstIndex(where: { $0.id == c }) else {
            return (flat.suffix(5).map { ($0.task.title, depth($0.id)) }, [])
        }
        return (flat[max(0, i - 5)..<i].map { ($0.task.title, depth($0.id)) },
                flat[(i + 1)...].prefix(5).map { ($0.task.title, depth($0.id)) })
    }

    /// Test hook (HUSH_OPEN=focus): focus the first non-Inbox top-level task.
    func focusFirstTask() {
        if let n = tree.first(where: { !$0.task.isInbox }) { selection = n.id; toggleFocus() }
    }

    func toggleFocus() {
        if focus != nil { exitFocus(); return }
        commitEditing()
        guard let id = selection, let n = node(id), !n.task.isInbox else { return }
        if isFinding { clearFind() }
        withAnimation(Theme.reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            focus = FocusSession(current: id, queued: focusNext(after: id, skipSubtree: false))
        }
        onFocusChange(true)
    }

    func exitFocus() {
        guard let f = focus else { return }
        let target = f.current ?? f.queued ?? f.last
        withAnimation(Theme.reduceMotion ? nil : .easeInOut(duration: 0.2)) { focus = nil }
        onFocusChange(false)
        if let t = target, node(t) != nil { reveal(t) }
    }

    func focusSkip() {
        guard var f = focus, let c = f.current, let n = f.queued else { return }
        f.last = c; f.current = n; f.queued = focusNext(after: n, skipSubtree: false)
        withAnimation(.easeInOut(duration: 0.15)) { focus = f }
    }

    /// ⌘↵: complete the focused task; it lifts away while the next one rises in.
    func focusComplete() {
        guard var f = focus, let c = f.current, let out = snap(c) else { return }
        let next = focusNext(after: c, skipSubtree: true)
        guard (try? store.complete(c)) != nil else { return }
        f.outgoing = out; f.start = Date(); f.last = c
        f.finished += 1
        f.current = next
        f.queued = next.flatMap { focusNext(after: $0, skipSubtree: false) }
        focus = f
        momentumPulse = Date()
        reload()
        let started = f.start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if self?.focus?.start == started { self?.focus?.outgoing = nil }
        }
    }

    private func handleFocus(_ k: KeyPress) -> Bool {
        switch k.code {
        case 53: exitFocus(); return true
        case 3 where k.cmd && k.shift: exitFocus(); return true
        case 36 where k.cmd, 76 where k.cmd: focusComplete(); return true
        case 125 where !k.cmd && !k.opt: focusSkip(); return true
        default: return !k.cmd                       // no typing into the hidden outline
        }
    }

    // MARK: Keys

    /// Returns true if handled. While editing, plain keys (typing, ↵, ⇥, Esc, arrows) belong to the text field.
    func handle(_ k: KeyPress) -> Bool {
        if showShortcuts {                            // ⌘/ sheet: Esc or ⌘/ closes, nothing else leaks through
            if k.code == 53 || (k.code == 44 && k.cmd) { showShortcuts = false }
            return !k.cmd
        }
        if focus != nil { return handleFocus(k) }
        if k.code == 44 && k.cmd { commitEditing(); showShortcuts = true; return true }       // ⌘/
        if k.code == 3 && k.cmd && k.shift { toggleFocus(); return true }                       // ⌘⇧F
        if k.code == 3 && k.cmd { focusFind(); return true }                                    // ⌘F
        if findActive || isFinding, !k.cmd {
            switch k.code {
            case 53: clearFind(); return true
            case 36, 76: jumpToMatch(); return true
            case 126, 125: moveSelection(k.code == 126 ? -1 : 1); return true
            default: return !findActive            // typing belongs to the Find field
            }
        }
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
