# HushCore public API (Backend-owned). Frontend: request changes under "Requests" at the bottom.

`import HushCore`. All types Sendable. Methods are synchronous and `throws` (GRDB queue, fine on MainActor at this scale).
Observation callbacks arrive on the **main queue**, first value immediately after subscribing, then on every change.

## Store
```swift
let store = try TaskStore(path: TaskStore.defaultURL().path)   // ~/Library/Application Support/Hush/hush.sqlite (dir created)
let store = try TaskStore.inMemory()                            // tests; both accept now: @Sendable () -> Date
```
Inbox (top-level, `isInbox == true`, title "Inbox") is created on first open. It can't be renamed/moved/completed/deleted (`HushError.inboxProtected`).
Top level (`parentID == nil`) = Inbox + user projects. Quick Capture default: `create(title:, note:, parent: inbox.id)`.

## Types
- `TaskID(raw: Int64)` Hashable/Codable. `TaskItem { id, parentID?, position, title, note, createdAt, completedAt?, isInbox, collapsed }`
- `OutlineNode { task, children: [OutlineNode], openChildCount (direct), openDescendantCount (D13: what "N open"/collapsed rows show) }` — open tasks only; children ordered.
- `CompletionReceipt { root: TaskItem, ids, completedAt }`, `DeletionReceipt { root, ids }` — pass back to `undo…`.
- `HistoryDay { day: Date (local midnight of the 04:00-adjusted day), entries: [HistoryEntry] }` newest first; `HistoryEntry { task, path: [String] }` (ancestor titles).
- `TodaySummary { doneCount, latestTitles (≤3, newest first) }`, `MenuBarSnapshot { recent: [TaskItem], openCount }` (Inbox excluded from both).
- `HushError`: notFound(TaskID), emptyTitle, titleTooLong, noteTooLong, inboxProtected, cannotIndent, cannotOutdent, invalidMove, applicationSupportUnavailable.
- `Subscription` — keep a reference; `cancel()` or release to stop.

## Reads
`inbox()`, `task(id)`, `openDescendantCount(of:)` (zoom node's "N open"; nil = Home = all open non-Inbox), `setCollapsed(id, Bool)`, `outline(root: TaskID? = nil) -> [OutlineNode]`, `recent(limit:)`, `openCount()`,
`history(calendar:)` (latest 500 completions, D17; `HistoryDay.day` is a real local-midnight Date), `todaySummary(now:calendar:)`, `search(_:)` (open tasks, title/note substring, ≤50).

## Writes
- `create(title:note:parent:after:) -> TaskItem` (parent nil = top level; `after` = sibling to insert behind, else appended)
- `update(id, title:, note:) -> TaskItem` (nil = unchanged)
- `move(id, newParent:, index:)` (index among open siblings; nil = end; into own subtree -> `.invalidMove`)
- `indent(id)` (-> last child of previous sibling; first child throws `.cannotIndent`), `outdent(id)` (-> right after its parent; top level throws `.cannotOutdent`)
- `moveUp(id)`, `moveDown(id)` -> Bool (false at the edge)
- `complete(id) -> CompletionReceipt` (also completes open descendants, same timestamp), `undoComplete(receipt)`
- `delete(id) -> DeletionReceipt` (soft, whole subtree), `undoDelete(receipt)`
- `restore(fromHistory: id) -> TaskItem` (nearest open ancestor, else top level; appended at end; its completed descendants stay in History)

## Undo / redo (D21)
`undo()` / `redo()` -> `[TaskID]` (ids touched; empty = nothing to do, never an error), `canUndo`, `canRedo`.
One app-wide, in-memory stack (100 steps) of row snapshots; each step restores exact parent/index. Covered: create, update (title/note), move, indent, outdent, moveUp/Down, complete (whole cascade), delete (whole subtree). A new action clears redo.
NOT undoable: `setCollapsed`, `restore(fromHistory:)`. `delete` only soft-deletes OPEN descendants (completed ones stay in History). `undoComplete(receipt)` and `undoDelete(receipt)` clear both stacks; `restore` just isn't recorded -- use `undo()` instead of the receipt API.

## Parent search (D7)
`searchParents(prefix:limit: 5) -> [ParentMatch { task, path }]`: open tasks (Inbox included) whose title starts with prefix, case-insensitive, newest created first. Blank prefix -> [].

## Closure (D18)
`TodaySummary` now has `openCount` and `copy: ClosureCopy { headline, closing }` (all-clear pair when no open tasks, else by doneCount: 0 / 1 / 2-5 / >=6). `ClosureCopy.choose(doneCount:openCount:)` is pure.

## Observation
`observeOutline(root:onChange:)`, `observeMenuBar(limit:onChange:)`, `observeHistory(calendar:onChange:)`, `observeToday(calendar:onChange:)` -> `Subscription`.
Note: `observeToday` re-reads only on DB change, not when 04:00 passes; re-subscribe or call `todaySummary` on popover open.

## Rules
Titles (D12): newlines -> spaces, trimmed, 1-500 chars, else `.emptyTitle`/`.titleTooLong` and nothing is written; notes <= 10,000 (`.noteTooLong`). Applies to `create` and `update`.
Inbox (D15): always first at top level; `move` at root clamps index >= 1, `moveUp` can't swap above it, nothing moves into own subtree. `create(parent: nil)` = top level (NOT Inbox): pass `inbox().id` for capture.
Restore (D5): original parent if open, else nearest open ancestor, else top level; end; single task.
Day boundary 04:00 local (`TaskStore.dayBoundaryHour`). Sibling `position` renumbered 0..n-1 (open siblings) in one transaction on every change. Completed/deleted tasks never appear in outline/recent/search.

## Requests
(none yet)
