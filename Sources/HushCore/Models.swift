import Foundation

public struct TaskID: Hashable, Codable, Sendable {
    public let raw: Int64
    public init(_ raw: Int64) { self.raw = raw }
}

public struct TaskItem: Identifiable, Hashable, Sendable {
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
    public let task: TaskItem
    /// Ancestor titles, outermost first (e.g. ["Work", "Q4"]). Empty at top level.
    public let path: [String]
    public var id: TaskID { task.id }
}

public struct HistoryDay: Identifiable, Hashable, Sendable {
    /// Start (00:00) of the local calendar day this group belongs to, using the 04:00 boundary.
    public let day: Date
    /// Newest first.
    public let entries: [HistoryEntry]
    public var id: Date { day }
}

public struct TodaySummary: Hashable, Sendable {
    public let doneCount: Int
    /// Up to 3, newest first.
    public let latestTitles: [String]
    /// All open tasks excluding Inbox.
    public let openCount: Int
    /// Closure card headline/closing pair per D18.
    public var copy: ClosureCopy { ClosureCopy.choose(doneCount: doneCount, openCount: openCount) }
}

public struct ClosureCopy: Hashable, Sendable {
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
    public let task: TaskItem
    /// Ancestor titles, outermost first.
    public let path: [String]
    public var id: TaskID { task.id }
}

/// Everything the menu bar popover shows.
public struct MenuBarSnapshot: Hashable, Sendable {
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
