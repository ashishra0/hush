import Foundation
import GRDB

public final class TaskStore: Sendable {
    /// Days roll over at 04:00 local time.
    public static let dayBoundaryHour = 4
    public static let maxTitleLength = 500
    public static let maxNoteLength = 10_000
    public static let maxHistory = 500

    /// D12: newlines -> spaces, trimmed, 1...500 characters.
    static func normalizedTitle(_ raw: String) throws -> String {
        let t = raw.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { throw HushError.emptyTitle }
        if t.count > maxTitleLength { throw HushError.titleTooLong }
        return t
    }
    static func checkedNote(_ n: String) throws -> String {
        if n.count > maxNoteLength { throw HushError.noteTooLong }
        return n
    }

    private let db: DatabaseQueue
    private let now: @Sendable () -> Date
    private let undoLog = UndoLog()

    public init(path: String, now: @escaping @Sendable () -> Date = { Date() }) throws {
        self.db = try DatabaseQueue(path: path)
        self.now = now
        try Self.migrate(db)
    }

    public static func inMemory(now: @escaping @Sendable () -> Date = { Date() }) throws -> TaskStore {
        try TaskStore(path: ":memory:", now: now)
    }

    /// ~/Library/Application Support/Hush/hush.sqlite (directory is created).
    public static func defaultURL() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { throw HushError.applicationSupportUnavailable }
        let dir = base.appendingPathComponent("Hush", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hush.sqlite")
    }

    private static func migrate(_ db: DatabaseQueue) throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE task (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  parentId INTEGER REFERENCES task(id),
                  position INTEGER NOT NULL DEFAULT 0,
                  title TEXT NOT NULL DEFAULT '',
                  note TEXT NOT NULL DEFAULT '',
                  createdAt REAL NOT NULL,
                  completedAt REAL,
                  deletedAt REAL,
                  isInbox INTEGER NOT NULL DEFAULT 0,
                  collapsed INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX task_parent ON task(parentId, position);
                CREATE INDEX task_completed ON task(completedAt);
                CREATE UNIQUE INDEX task_one_inbox ON task(isInbox) WHERE isInbox = 1;
                """)
            try db.execute(sql: "INSERT INTO task (position, title, createdAt, isInbox) VALUES (0, 'Inbox', ?, 1)",
                           arguments: [Date().timeIntervalSince1970])
        }
        try m.migrate(db)
    }

    // MARK: Reads

    public func inbox() throws -> TaskItem {
        try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM task WHERE isInbox = 1") else {
                throw HushError.notFound(TaskID(0))
            }
            return TaskItem(row)
        }
    }

    public func task(_ id: TaskID) throws -> TaskItem {
        try db.read { try $0.task(id.raw) }
    }

    /// Open children tree of `root` (nil = whole outline, Inbox first).
    public func outline(root: TaskID? = nil) throws -> [OutlineNode] {
        try db.read { try Self.readOutline($0, root: root) }
    }

    /// "N open" for a zoom node: its open descendants (not itself). nil = Home = all open non-Inbox tasks.
    public func openDescendantCount(of id: TaskID? = nil) throws -> Int {
        guard let id else { return try openCount() }
        return try db.read { try $0.subtree(of: id.raw, openOnly: true).count - 1 }
    }

    public func setCollapsed(_ id: TaskID, _ collapsed: Bool) throws {
        try db.write { try $0.execute(sql: "UPDATE task SET collapsed = ? WHERE id = ?", arguments: [collapsed, id.raw]) }
    }

    /// Open tasks (excluding Inbox), newest created first.
    public func recent(limit: Int) throws -> [TaskItem] {
        try db.read { try Self.readRecent($0, limit: limit) }
    }

    public func openCount() throws -> Int {
        try db.read { try Self.readOpenCount($0) }
    }

    /// Finished tasks grouped by local day (04:00 boundary), newest day first.
    public func history(calendar: Calendar = .current, limit: Int = TaskStore.maxHistory) throws -> [HistoryDay] {
        try db.read { try Self.readHistory($0, calendar: calendar, limit: limit) }
    }

    public func todaySummary(now: Date? = nil, calendar: Calendar = .current) throws -> TodaySummary {
        let at = now ?? self.now()
        return try db.read { try Self.readToday($0, now: at, calendar: calendar) }
    }

    /// Open tasks whose title or note contains `query` (case-insensitive), max 50.
    public func search(_ query: String) throws -> [TaskItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let esc = q.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        return try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM task WHERE completedAt IS NULL AND deletedAt IS NULL AND isInbox = 0
                AND (title LIKE ?1 ESCAPE '\\' OR note LIKE ?1 ESCAPE '\\')
                ORDER BY createdAt DESC LIMIT 50
                """, arguments: ["%\(esc)%"]).map(TaskItem.init)
        }
    }

    // MARK: Writes

    /// New open task under `parent` (nil = top level), after sibling `after` or at the end.
    @discardableResult
    public func create(title: String, note: String = "", parent: TaskID? = nil, after: TaskID? = nil) throws -> TaskItem {
        let title = try Self.normalizedTitle(title), note = try Self.checkedNote(note)
        let ts = now().timeIntervalSince1970
        return try record { db in
            if let p = parent { try db.requireOpen(p.raw) }
            var sibs = try db.openChildren(of: parent?.raw)
            let idx = after.flatMap { a in sibs.firstIndex(of: a.raw).map { $0 + 1 } } ?? sibs.count
            try db.execute(sql: "INSERT INTO task (parentId, position, title, note, createdAt) VALUES (?, ?, ?, ?, ?)",
                           arguments: [parent?.raw, idx, title, note, ts])
            let id = db.lastInsertedRowID
            sibs.insert(id, at: idx)
            try db.setOrder(parent: parent?.raw, ids: sibs)
            return try db.task(id)
        }
    }

    @discardableResult
    public func update(_ id: TaskID, title: String? = nil, note: String? = nil) throws -> TaskItem {
        let title = try title.map(Self.normalizedTitle), note = try note.map(Self.checkedNote)
        return try record { db in
            let t = try db.task(id.raw)
            if t.isInbox && title != nil { throw HushError.inboxProtected }
            try db.execute(sql: "UPDATE task SET title = ?, note = ? WHERE id = ?",
                           arguments: [title ?? t.title, note ?? t.note, id.raw])
            return try db.task(id.raw)
        }
    }

    /// Move under `newParent` (nil = top level) at `index` among open siblings (nil/too large = end).
    public func move(_ id: TaskID, newParent: TaskID?, index: Int? = nil) throws {
        try record { db in
            let t = try db.task(id.raw)
            if t.isInbox { throw HushError.inboxProtected }
            if let p = newParent {
                try db.requireOpen(p.raw)
                if try db.subtree(of: id.raw).contains(p.raw) { throw HushError.invalidMove }
            }
            let oldParent = t.parentID?.raw
            var old = try db.openChildren(of: oldParent)
            old.removeAll { $0 == id.raw }
            var dest = oldParent == newParent?.raw ? old : try db.openChildren(of: newParent?.raw)
            dest.removeAll { $0 == id.raw }
            dest.insert(id.raw, at: max(newParent == nil ? 1 : 0, min(index ?? dest.count, dest.count)))  // root: never above Inbox
            if oldParent != newParent?.raw { try db.setOrder(parent: oldParent, ids: old) }
            try db.setOrder(parent: newParent?.raw, ids: dest)
        }
    }

    /// Becomes the last child of its previous sibling. Throws `.cannotIndent` for a first child.
    public func indent(_ id: TaskID) throws {
        let parent: TaskID? = try db.read { try $0.task(id.raw).parentID }
        let sibs = try db.read { try $0.openChildren(of: parent?.raw) }
        guard let i = sibs.firstIndex(of: id.raw) else { throw HushError.notFound(id) }
        guard i > 0 else { throw HushError.cannotIndent }
        try move(id, newParent: TaskID(sibs[i - 1]))
    }

    /// Becomes the next sibling of its parent. Throws `.cannotOutdent` at top level.
    public func outdent(_ id: TaskID) throws {
        try record { db in
            let t = try db.task(id.raw)
            if t.isInbox { throw HushError.inboxProtected }
            guard let p = t.parentID else { throw HushError.cannotOutdent }
            let parent = try db.task(p.raw)
            var dest = try db.openChildren(of: parent.parentID?.raw)
            var old = try db.openChildren(of: p.raw)
            old.removeAll { $0 == id.raw }
            let at = (dest.firstIndex(of: p.raw) ?? dest.count - 1) + 1
            dest.insert(id.raw, at: at)
            try db.setOrder(parent: p.raw, ids: old)
            try db.setOrder(parent: parent.parentID?.raw, ids: dest)
        }
    }

    /// Swap with the previous/next open sibling; no-op at the edge. Returns whether it moved.
    @discardableResult
    public func moveUp(_ id: TaskID) throws -> Bool { try shift(id, by: -1) }
    @discardableResult
    public func moveDown(_ id: TaskID) throws -> Bool { try shift(id, by: 1) }

    private func shift(_ id: TaskID, by d: Int) throws -> Bool {
        try record { db in
            let t = try db.task(id.raw)
            if t.isInbox { throw HushError.inboxProtected }
            var sibs = try db.openChildren(of: t.parentID?.raw)
            guard let i = sibs.firstIndex(of: id.raw) else { throw HushError.notFound(id) }
            let j = i + d
            guard sibs.indices.contains(j), j > 0 || t.parentID != nil else { return false }  // never above Inbox
            sibs.swapAt(i, j)
            try db.setOrder(parent: t.parentID?.raw, ids: sibs)
            return true
        }
    }

    /// Completes the task and all its open descendants with one timestamp.
    public func complete(_ id: TaskID) throws -> CompletionReceipt {
        let ts = now()
        return try record { db in
            let t = try db.task(id.raw)
            if t.isInbox { throw HushError.inboxProtected }
            try db.requireOpen(id.raw)
            let ids = try db.subtree(of: id.raw, openOnly: true)
            try db.execute(sql: "UPDATE task SET completedAt = ? WHERE id IN (\(ids.map(String.init).joined(separator: ",")))",
                           arguments: [ts.timeIntervalSince1970])
            try db.setOrder(parent: t.parentID?.raw, ids: try db.openChildren(of: t.parentID?.raw))
            return CompletionReceipt(root: t, ids: ids.map(TaskID.init), completedAt: ts)
        }
    }

    public func undoComplete(_ r: CompletionReceipt) throws {
        try db.write { db in
            undoLog.clear()  // not on the undo stack (D21 / receipt API)
            try db.execute(sql: "UPDATE task SET completedAt = NULL WHERE id IN (\(r.ids.map { String($0.raw) }.joined(separator: ",")))")
            try db.renumberParents(of: r.ids.map(\.raw))
        }
    }

    /// Soft-deletes the task and its whole subtree.
    public func delete(_ id: TaskID) throws -> DeletionReceipt {
        let ts = now().timeIntervalSince1970
        return try record { db in
            let t = try db.task(id.raw)
            if t.isInbox { throw HushError.inboxProtected }
            let ids = try db.subtree(of: id.raw, notDeleted: true)
            try db.execute(sql: "UPDATE task SET deletedAt = ? WHERE id IN (\(ids.map(String.init).joined(separator: ",")))",
                           arguments: [ts])
            try db.setOrder(parent: t.parentID?.raw, ids: try db.openChildren(of: t.parentID?.raw))
            return DeletionReceipt(root: t, ids: ids.map(TaskID.init))
        }
    }

    public func undoDelete(_ r: DeletionReceipt) throws {
        try db.write { db in
            undoLog.clear()  // not on the undo stack (D21 / receipt API)
            try db.execute(sql: "UPDATE task SET deletedAt = NULL WHERE id IN (\(r.ids.map { String($0.raw) }.joined(separator: ",")))")
            try db.renumberParents(of: r.ids.map(\.raw))
        }
    }

    /// Re-opens a finished task under its nearest open ancestor (else top level), at the end.
    /// Descendants that were completed with it stay in History.
    @discardableResult
    public func restore(fromHistory id: TaskID) throws -> TaskItem {
        try db.write { db in
            undoLog.clear()  // not on the undo stack (D21 / receipt API)
            let t = try db.task(id.raw)
            var p = t.parentID?.raw
            while let cur = p {
                let r = try Row.fetchOne(db, sql: "SELECT * FROM task WHERE id = ?", arguments: [cur])
                guard let row = r else { p = nil; break }
                let a = TaskItem(row)
                if a.completedAt == nil && (row["deletedAt"] as Double?) == nil { break }
                p = a.parentID?.raw
            }
            let sibs = try db.openChildren(of: p)
            try db.execute(sql: "UPDATE task SET completedAt = NULL, parentId = ?, position = ? WHERE id = ?",
                           arguments: [p, sibs.count, id.raw])
            return try db.task(id.raw)
        }
    }

    // MARK: Undo / redo (D21)

    public var canUndo: Bool { undoLog.canUndo }
    public var canRedo: Bool { undoLog.canRedo }

    /// Reverts the last create/rename/note/complete/delete/indent/outdent/move. Returns the ids
    /// it touched (empty = nothing to undo).
    @discardableResult public func undo() throws -> [TaskID] { try replay(redo: false) }
    @discardableResult public func redo() throws -> [TaskID] { try replay(redo: true) }

    private func replay(redo: Bool) throws -> [TaskID] {
        try db.write { db in
            guard let step = redo ? undoLog.popRedo() : undoLog.popUndo() else { return [] }
            for r in redo ? step.after : step.before { try r.write(db) }
            // positions come back from the snapshots, so no renumbering is needed
            undoLog.push(step, toUndo: redo, keepRedo: true)
            return step.after.map { TaskID($0.id) }
        }
    }

    /// Runs a user action and logs the row-level diff as one undo step.
    // ponytail: snapshots every row per action (O(n)); fine for thousands of tasks, switch to affected-id diffs beyond that.
    private func record<T>(_ body: (Database) throws -> T) throws -> T {
        try db.write { db in
            let before = try RowState.all(db)
            let result = try body(db)
            let after = try RowState.all(db)
            var b: [RowState] = [], a: [RowState] = []
            for (id, new) in after {
                if let old = before[id] { if old != new { b.append(old); a.append(new) } }
                else { var gone = new; gone.deletedAt = 1; b.append(gone); a.append(new) }  // created: undo = soft delete
            }
            if !a.isEmpty { undoLog.push(UndoStep(before: b, after: a), toUndo: true, keepRedo: false) }
            return result
        }
    }

    /// Open tasks whose title starts with `prefix` (case-insensitive), newest created first, with paths (D7).
    public func searchParents(prefix: String, limit: Int = 5) throws -> [ParentMatch] {
        let q = prefix.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let esc = q.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        return try db.read { db in
            let all = try Row.fetchAll(db, sql: "SELECT * FROM task WHERE deletedAt IS NULL").map(TaskItem.init)
            let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            let hits = try Row.fetchAll(db, sql: """
                SELECT * FROM task WHERE completedAt IS NULL AND deletedAt IS NULL AND title LIKE ? ESCAPE '\\'
                ORDER BY createdAt DESC, id DESC LIMIT ?
                """, arguments: [esc + "%", limit]).map(TaskItem.init)
            return hits.map { t in
                var path: [String] = []; var p = t.parentID
                while let id = p, let a = byID[id] { path.insert(a.title, at: 0); p = a.parentID }
                return ParentMatch(task: t, path: path)
            }
        }
    }

    // MARK: Observation (callbacks delivered on the main queue)

    public func observeOutline(root: TaskID? = nil, onChange: @escaping @Sendable ([OutlineNode]) -> Void) -> Subscription {
        observe({ try Self.readOutline($0, root: root) }, onChange)
    }

    public func observeMenuBar(limit: Int = 5, onChange: @escaping @Sendable (MenuBarSnapshot) -> Void) -> Subscription {
        observe({ MenuBarSnapshot(recent: try Self.readRecent($0, limit: limit), openCount: try Self.readOpenCount($0)) }, onChange)
    }

    public func observeHistory(calendar: Calendar = .current, onChange: @escaping @Sendable ([HistoryDay]) -> Void) -> Subscription {
        observe({ try Self.readHistory($0, calendar: calendar, limit: Self.maxHistory) }, onChange)
    }

    public func observeToday(calendar: Calendar = .current, onChange: @escaping @Sendable (TodaySummary) -> Void) -> Subscription {
        let clock = now
        return observe({ try Self.readToday($0, now: clock(), calendar: calendar) }, onChange)
    }

    private func observe<T: Sendable>(_ read: @escaping @Sendable (Database) throws -> T,
                                      _ onChange: @escaping @Sendable (T) -> Void) -> Subscription {
        let c = ValueObservation.tracking(read).start(
            in: db, scheduling: .async(onQueue: .main),
            onError: { NSLog("Hush observation error: \($0)") },
            onChange: onChange)
        return Subscription { c.cancel() }
    }

    // MARK: Read implementations

    private static func readOutline(_ db: Database, root: TaskID?) throws -> [OutlineNode] {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM task WHERE completedAt IS NULL AND deletedAt IS NULL ORDER BY position, id")
        let byParent = Dictionary(grouping: rows.map(TaskItem.init), by: { $0.parentID })
        func build(_ p: TaskID?) -> [OutlineNode] {
            (byParent[p] ?? []).map { OutlineNode(task: $0, children: build($0.id)) }
        }
        return build(root)
    }

    private static func readRecent(_ db: Database, limit: Int) throws -> [TaskItem] {
        try Row.fetchAll(db, sql: "SELECT * FROM task WHERE completedAt IS NULL AND deletedAt IS NULL AND isInbox = 0 ORDER BY createdAt DESC, id DESC LIMIT ?",
                         arguments: [limit]).map(TaskItem.init)
    }

    private static func readOpenCount(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task WHERE completedAt IS NULL AND deletedAt IS NULL AND isInbox = 0") ?? 0
    }

    private static func readHistory(_ db: Database, calendar: Calendar, limit: Int) throws -> [HistoryDay] {
        let all = try Row.fetchAll(db, sql: "SELECT * FROM task WHERE deletedAt IS NULL").map(TaskItem.init)
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let done = all.filter { $0.completedAt != nil }
            .sorted { ($0.completedAt!, $0.id.raw) > ($1.completedAt!, $1.id.raw) }.prefix(limit)
        func path(_ t: TaskItem) -> [String] {
            var out: [String] = []; var p = t.parentID
            while let id = p, let a = byID[id] { out.insert(a.title, at: 0); p = a.parentID }
            return out
        }
        var days: [(Date, [HistoryEntry])] = []
        for t in done {
            let shifted = calendar.date(byAdding: .hour, value: -dayBoundaryHour, to: t.completedAt!)!
            let day = calendar.startOfDay(for: shifted)
            let e = HistoryEntry(task: t, path: path(t))
            if days.last?.0 == day { days[days.count - 1].1.append(e) } else { days.append((day, [e])) }
        }
        return days.map { HistoryDay(day: $0.0, entries: $0.1) }
    }

    private static func readToday(_ db: Database, now: Date, calendar: Calendar) throws -> TodaySummary {
        let shifted = calendar.date(byAdding: .hour, value: -dayBoundaryHour, to: now)!
        let dayStart = calendar.startOfDay(for: shifted)
        let start = calendar.date(byAdding: .hour, value: dayBoundaryHour, to: dayStart)!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let args: StatementArguments = [start.timeIntervalSince1970, end.timeIntervalSince1970]
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task WHERE deletedAt IS NULL AND completedAt >= ? AND completedAt < ?", arguments: args) ?? 0
        let titles = try String.fetchAll(db, sql: "SELECT title FROM task WHERE deletedAt IS NULL AND completedAt >= ? AND completedAt < ? ORDER BY completedAt DESC, id DESC LIMIT 3", arguments: args)
        return TodaySummary(doneCount: count, latestTitles: titles, openCount: try readOpenCount(db))
    }
}

// MARK: - Internals

extension TaskItem {
    init(_ r: Row) {
        id = TaskID(r["id"])
        parentID = (r["parentId"] as Int64?).map(TaskID.init)
        position = r["position"]
        title = r["title"]
        note = r["note"]
        createdAt = Date(timeIntervalSince1970: r["createdAt"])
        completedAt = (r["completedAt"] as Double?).map { Date(timeIntervalSince1970: $0) }
        isInbox = (r["isInbox"] as Int) != 0
        collapsed = (r["collapsed"] as Int) != 0
    }
}

private extension Database {
    func task(_ id: Int64) throws -> TaskItem {
        guard let r = try Row.fetchOne(self, sql: "SELECT * FROM task WHERE id = ? AND deletedAt IS NULL", arguments: [id])
        else { throw HushError.notFound(TaskID(id)) }
        return TaskItem(r)
    }

    func requireOpen(_ id: Int64) throws {
        let ok = try Bool.fetchOne(self, sql: "SELECT 1 FROM task WHERE id = ? AND completedAt IS NULL AND deletedAt IS NULL", arguments: [id]) ?? false
        if !ok { throw HushError.notFound(TaskID(id)) }
    }

    func openChildren(of parent: Int64?) throws -> [Int64] {
        try Int64.fetchAll(self, sql: "SELECT id FROM task WHERE parentId IS ? AND completedAt IS NULL AND deletedAt IS NULL ORDER BY position, id",
                           arguments: [parent])
    }

    func setOrder(parent: Int64?, ids: [Int64]) throws {
        for (i, id) in ids.enumerated() {
            try execute(sql: "UPDATE task SET parentId = ?, position = ? WHERE id = ?", arguments: [parent, i, id])
        }
    }

    /// id + all descendants (optionally only open / not-deleted ones).
    func subtree(of id: Int64, openOnly: Bool = false, notDeleted: Bool = false) throws -> [Int64] {
        var filter = ""
        if openOnly { filter = " WHERE completedAt IS NULL AND deletedAt IS NULL" }
        else if notDeleted { filter = " WHERE deletedAt IS NULL" }
        return try Int64.fetchAll(self, sql: """
            WITH RECURSIVE sub(id) AS (SELECT ? UNION SELECT t.id FROM task t JOIN sub ON t.parentId = sub.id)
            SELECT task.id FROM task JOIN sub ON task.id = sub.id\(filter) ORDER BY task.id
            """, arguments: [id])
    }

    func renumberParents(of ids: [Int64]) throws {
        let list = ids.map(String.init).joined(separator: ",")
        let parents = try Row.fetchAll(self, sql: "SELECT DISTINCT parentId FROM task WHERE id IN (\(list))")
        for p in parents { let pid: Int64? = p["parentId"]; try setOrder(parent: pid, ids: try openChildren(of: pid)) }
    }
}

// MARK: - Undo log (value-type snapshots)

private struct RowState: Equatable {
    var id: Int64, parentId: Int64?, position: Int, title: String, note: String
    var completedAt: Double?, deletedAt: Double?

    static func all(_ db: Database) throws -> [Int64: RowState] {
        let rows = try Row.fetchAll(db, sql: "SELECT id, parentId, position, title, note, completedAt, deletedAt FROM task")
        return Dictionary(uniqueKeysWithValues: rows.map { r in
            (r["id"] as Int64, RowState(id: r["id"], parentId: r["parentId"], position: r["position"], title: r["title"],
                                         note: r["note"], completedAt: r["completedAt"], deletedAt: r["deletedAt"]))
        })
    }

    func write(_ db: Database) throws {
        try db.execute(sql: "UPDATE task SET parentId = ?, position = ?, title = ?, note = ?, completedAt = ?, deletedAt = ? WHERE id = ?",
                       arguments: [parentId, position, title, note, completedAt, deletedAt, id])
    }
}

private struct UndoStep { var before: [RowState]; var after: [RowState] }

/// App-wide, in-memory, 100 steps. Mutated inside the db write queue; lock guards the `canUndo` reads.
private final class UndoLog: @unchecked Sendable {
    private let lock = NSLock()
    private var undo: [UndoStep] = [], redo: [UndoStep] = []
    var canUndo: Bool { lock.withLock { !undo.isEmpty } }
    var canRedo: Bool { lock.withLock { !redo.isEmpty } }
    func clear() { lock.withLock { undo = []; redo = [] } }
    func popUndo() -> UndoStep? { lock.withLock { undo.popLast() } }
    func popRedo() -> UndoStep? { lock.withLock { redo.popLast() } }
    /// toUndo: step goes on the undo stack (a new action, or a redo); else on the redo stack.
    func push(_ s: UndoStep, toUndo: Bool, keepRedo: Bool) {
        lock.withLock {
            if toUndo { undo.append(s); if undo.count > 100 { undo.removeFirst() }; if !keepRedo { redo = [] } }
            else { redo.append(s) }
        }
    }
}
