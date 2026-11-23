import Foundation

public struct TaskID: Hashable, Codable, Sendable {
    public let raw: Int64
    public init(_ raw: Int64) { self.raw = raw }
}

public struct TaskItem: Identifiable, Hashable, Sendable {
    public init(id: TaskID, parentID: TaskID? = nil, position: Int = 0, title: String, note: String = "", createdAt: Date = Date(), completedAt: Date? = nil, isInbox: Bool = false, collapsed: Bool = false) {
        self.id = id; self.parentID = parentID; self.position = position; self.title = title; self.note = note
        self.createdAt = createdAt; self.completedAt = completedAt; self.isInbox = isInbox; self.collapsed = collapsed
    }
    public let id: TaskID
    /// nil = top level (sibling of Inbox).
    public let parentID: TaskID?
    public let position: Int
    public let title: String
    public let note: String
    public let createdAt: Date
    public let completedAt: Date?
    public let isInbox: Bool
    public let collapsed: Bool
}

/// A node of the open-task outline. Only open (not completed, not deleted) tasks appear.
public struct OutlineNode: Identifiable, Hashable, Sendable {
    public init(task: TaskItem, children: [OutlineNode]) { self.task = task; self.children = children }
    public let task: TaskItem
    public let children: [OutlineNode]
    public var id: TaskID { task.id }
    /// Direct open children only. For the "N open" count use `openDescendantCount` (D13).
    public var openChildCount: Int { children.count }
    /// Open descendants, not counting this node (what a collapsed row shows).
    public var openDescendantCount: Int { children.reduce(0) { $0 + 1 + $1.openDescendantCount } }
}

public struct CompletionReceipt: Hashable, Sendable {
    public let root: TaskItem
    /// Every id completed (root + open descendants), all with `completedAt`.
    public let ids: [TaskID]
    public let completedAt: Date
}

public struct DeletionReceipt: Hashable, Sendable {
    public let root: TaskItem
    public let ids: [TaskID]
}

public struct HistoryEntry: Identifiable, Hashable, Sendable {
    public init(task: TaskItem, path: [String]) { self.task = task; self.path = path }
    public let task: TaskItem
    /// Ancestor titles, outermost first (e.g. ["Work", "Q4"]). Empty at top level.
    public let path: [String]
    public var id: TaskID { task.id }
}

public struct HistoryDay: Identifiable, Hashable, Sendable {
    public init(day: Date, entries: [HistoryEntry]) { self.day = day; self.entries = entries }
    /// Start (00:00) of the local calendar day this group belongs to, using the 04:00 boundary.
    public let day: Date
    /// Newest first.
    public let entries: [HistoryEntry]
    public var id: Date { day }
}

public struct TodaySummary: Hashable, Sendable {
    public init(doneCount: Int, latestTitles: [String], openCount: Int) { self.doneCount = doneCount; self.latestTitles = latestTitles; self.openCount = openCount }
    public let doneCount: Int
    /// Up to 3, newest first.
    public let latestTitles: [String]
    /// All open tasks excluding Inbox.
    public let openCount: Int
    /// Closure card headline/closing pair per D18.
    public var copy: ClosureCopy { ClosureCopy.choose(doneCount: doneCount, openCount: openCount) }
}

public struct ClosureCopy: Hashable, Sendable {
    public init(headline: String, closing: String) { self.headline = headline; self.closing = closing }
    public let headline: String
    public let closing: String

    /// D18: no open tasks at all -> "All clear." pair regardless of count; else by finished-today count.
    public static func choose(doneCount: Int, openCount: Int) -> ClosureCopy {
        if openCount == 0 { return .init(headline: "All clear.", closing: "Nothing is waiting on you. Enjoy it.") }
        switch doneCount {
        case 6...: return .init(headline: "A good day's work.", closing: "The rest can wait until tomorrow.")
        case 2...: return .init(headline: "Steady progress.", closing: "Every one of these counts.")
        case 1: return .init(headline: "One thing, done.", closing: "Sometimes one is the right number.")
        default: return .init(headline: "A quiet day.", closing: "Not every day is for crossing things off.")
        }
    }
}

/// A `/name` filing suggestion (D7).
public struct ParentMatch: Identifiable, Hashable, Sendable {
    public init(task: TaskItem, path: [String]) { self.task = task; self.path = path }
    public let task: TaskItem
    /// Ancestor titles, outermost first.
    public let path: [String]
    public var id: TaskID { task.id }
}

/// Everything the menu bar popover shows.
public struct MenuBarSnapshot: Hashable, Sendable {
    public init(recent: [TaskItem], openCount: Int) { self.recent = recent; self.openCount = openCount }
    /// Open tasks (excluding Inbox), newest created first.
    public let recent: [TaskItem]
    /// Open tasks excluding Inbox.
    public let openCount: Int
}

public enum HushError: Error, Equatable, Sendable {
    case notFound(TaskID)
    case inboxProtected      // Inbox can't be renamed, moved, completed or deleted
    case cannotIndent        // first sibling
    case cannotOutdent       // already top level
    case emptyTitle          // title empty after trimming
    case titleTooLong        // > 500 characters
    case noteTooLong         // > 10,000 characters
    case invalidMove         // into itself/descendant, or index/parent invalid
    case applicationSupportUnavailable
}

/// Cancels its observation on `cancel()` or deinit.
public final class Subscription: @unchecked Sendable {
    private let onCancel: @Sendable () -> Void
    init(_ onCancel: @escaping @Sendable () -> Void) { self.onCancel = onCancel }
    public func cancel() { onCancel() }
    deinit { onCancel() }
}

/// Same shape as `TodaySummary` for any day, plus the finished tasks themselves.
public struct DaySummary: Hashable, Sendable {
    public init(day: Date, doneCount: Int, finished: [HistoryEntry], latestTitles: [String], openCount: Int) {
        self.day = day; self.doneCount = doneCount; self.finished = finished; self.latestTitles = latestTitles; self.openCount = openCount
    }
    public let day: Date                      // local midnight of the calendar day
    public let doneCount: Int
    public let finished: [HistoryEntry]       // newest first (title, completedAt, path)
    public let latestTitles: [String]         // up to 3
    public let openCount: Int
    public var copy: ClosureCopy { ClosureCopy.choose(doneCount: doneCount, openCount: openCount) }
}

public struct DayCount: Hashable, Sendable {
    public init(day: Date, count: Int) { self.day = day; self.count = count }
    public let day: Date
    public let count: Int
}

public struct FindMatch: Identifiable, Hashable, Sendable {
    public init(task: TaskItem, ancestors: [TaskItem], ranges: [Range<String.Index>]) { self.task = task; self.ancestors = ancestors; self.ranges = ranges }
    public let task: TaskItem
    /// Ancestors below the search root, outermost first.
    public let ancestors: [TaskItem]
    /// Match ranges in `task.title`.
    public let ranges: [Range<String.Index>]
    public var id: TaskID { task.id }
}
