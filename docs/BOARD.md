# Hush — Board (PM)

Source of truth for UI: `docs/DESIGN.md`. Ownership and tech decisions: `docs/ARCHITECTURE.md`. API: `docs/CONTRACTS.md` (Backend).
Status values: `todo` · `doing` · `review` · `done`. Engineers update their own task's status; only PM edits scope and acceptance criteria.
A task is done when its criteria pass, `swift build` is warning-free and `swift test` is green. BE criteria are proven by Swift Testing tests on an in-memory DB; FE criteria by running `build/Hush.app`.

## Milestones
| | Scope | Exit test |
|---|---|---|
| **M1 = P0** | App shell, menu bar item + popover, global ⌘⇧Space, Quick Capture (title only), SQLite persistence, create / list / complete | Capture a task from any app, see it in the popover and outline, complete it, quit, relaunch: state is intact. |
| **M2 = P1** | Nested outline, keyboard nav and editing, reorder incl. drag, Strike & Fold, undo, History, capture Details / `/name` / draft / ⌥↵ | Every outline shortcut in DESIGN "Keyboard" works without the mouse, except ⌘F and ⌘D (M3). |
| **M3 = P2** | Daily Closure card, Settings, Find | Design screens C and D and the closure card are complete. |
| Explore later, **not scheduled** | Focus Mode, Quiet Momentum | — |

## M1 — P0

**P0-01 · Backend · Contract v1** · deps: none · `todo`
- [ ] `docs/CONTRACTS.md` lists the public types and signatures for: open the store (file or in-memory), create task, complete task, list open tasks as a tree, observe changes, open-task count.
- [ ] The task type already carries parent, sibling order, note, collapsed, createdAt, completedAt, deletedAt, so P1 adds no breaking change.
- [ ] The signatures compile in `HushCore` (bodies may be unimplemented) so Frontend can build against them. Ship this before P0-02.

**P0-02 · Backend · Schema, migrations, Inbox seed** · deps: P0-01 · `todo`
- [ ] Given no DB file, when the store opens, then the file is created at the ARCHITECTURE path and contains exactly one task: root-level "Inbox".
- [ ] Given an existing DB, when the store opens again, then no second Inbox is created and existing tasks are unchanged.
- [ ] Completing, deleting, renaming or moving Inbox fails with a typed error and changes nothing.

**P0-03 · Backend · Create, list, complete, observe** · deps: P0-02 · `todo`
- [ ] Create with a title and no parent puts the task at the end of Inbox's children. Create with a parent puts it at the end of that parent's children.
- [ ] Titles are validated per decision D12; invalid titles fail with a typed error and write nothing.
- [ ] Complete sets completedAt; the task no longer appears in the open list or the open count.
- [ ] The open list returns tasks in sibling order with depth or parent links, Inbox first.
- [ ] An observer receives a new snapshot after every create and complete, with no polling.
- [ ] Data survives closing and reopening the store.

**P0-04 · Frontend · App shell and bundle** · deps: none · `todo`
- [ ] `scripts/bundle.sh` produces `build/Hush.app` that launches by double-click.
- [ ] No Dock icon and no app-switcher entry. The menu bar shows the template icon (14px circle outline with centre dot), legible in light and dark menu bars.
- [ ] Launching a second copy does not create a second menu bar item.
- [ ] ⌘Q from any Hush window or the popover quits; closing a window does not quit.

**P0-05 · Frontend · Theme tokens** · deps: none · `todo`
- [ ] Every colour, type size, radius and spacing value in DESIGN "Tokens" exists as a named token; views use tokens, never literals.
- [ ] Switching system appearance while the app runs updates all open Hush surfaces without relaunch.

**P0-06 · Frontend · Global hotkey** · deps: P0-04 · `todo`
- [ ] Given any app is frontmost, when ⌘⇧Space is pressed, then Quick Capture appears within 100 ms with the caret in the input.
- [ ] Pressing ⌘⇧Space while the panel is open closes it (same as Esc).
- [ ] If registration fails, the app still launches and capture remains reachable from the popover.

**P0-07 · Frontend · Quick Capture panel (title only)** · deps: P0-06; P0-01 to build, P0-03 to save · `todo`
- [ ] Panel is 640 wide, horizontally centred, top edge at about 23% of the height of the screen containing the pointer. Placeholder "What's on your mind?". Footer shows the Inbox destination left and `↵ Save` right (`⇥ Details` hidden until P1-14).
- [ ] Given a non-empty title, when ↵ is pressed, then the task is saved to Inbox, the panel morphs to the pill "✓ Saved to **Inbox**" (180 ms in, 900 ms hold, 150 ms fade), and the previously frontmost app is frontmost again immediately.
- [ ] Given an empty or whitespace-only title, ↵ does nothing and the panel stays open.
- [ ] Esc or a click outside closes the panel, discards the text (draft retention is P1-14) and returns focus to the previous app.
- [ ] With Reduce Motion on, the pill appears and disappears with opacity only.

**P0-08 · Frontend · Menu bar popover** · deps: P0-04, P0-03 · `todo`
- [ ] Clicking the menu bar icon opens a 320-wide popover matching DESIGN screen C; clicking outside or Esc closes it.
- [ ] The capture row shows "Capture a task…" and the shortcut; clicking it closes the popover and opens Quick Capture.
- [ ] RECENT shows up to 5 rows and "N of M open" per D10; rows update live when a task is captured or completed.
- [ ] Clicking a row's circle completes that task and the row disappears. Clicking the row text opens the outline.
- [ ] With zero open tasks the rows are replaced by one caption line "All clear." and the count is hidden.
- [ ] Footer: Open outline ⌘O and Quit Hush ⌘Q work by click and by key while the popover is open. "Settings…" is hidden until P2-03.

**P0-09 · Frontend · Outline window v0 (read and complete)** · deps: P0-03, P0-05 · `todo`
- [ ] ⌘O or "Open outline" opens one window (~1040×780, 720 content column, title "Home" 36 light, meta "N open"). Opening again focuses the existing window.
- [ ] All open tasks appear as 32-high rows in store order, indented 24 per level; Inbox shows a folder glyph instead of a circle.
- [ ] Clicking a circle completes the task; the row is removed (no animation in P0) and "N open" updates.
- [ ] A task saved from Quick Capture appears without reopening the window.
- [ ] No editing, creation, selection or shortcuts in this task; those are M2.

## M2 — P1

**P1-01 · Backend · Contract v2** · deps: P0-03 · `todo`
- [ ] CONTRACTS.md adds signatures for everything in P1-02 to P1-06, compiling, before any of them is implemented. Frontend sign-off recorded in the "Requests" section.

**P1-02 · Backend · Tree operations** · deps: P1-01 · `todo`
- [ ] Create at a given parent and index; rename; set note; set collapsed (persisted).
- [ ] Indent: the task becomes the last child of its previous sibling, taking its subtree; no-op with no previous sibling.
- [ ] Outdent: the task becomes the sibling immediately after its former parent; no-op at root.
- [ ] Move to (parent, index): rejects a move into the task's own subtree and any move that displaces Inbox from first root position.
- [ ] After any sequence of operations, sibling orders are gap-free and unique (property-style test).
- [ ] The subtree query for any node returns open descendants plus an open-descendant count per node.

**P1-03 · Backend · Cascade complete and soft delete** · deps: P1-02 · `todo`
- [ ] Completing a parent gives the parent and every open descendant a completedAt in one transaction.
- [ ] Delete sets deletedAt on the task and all its open descendants; deleted tasks appear in no list, count or History.
- [ ] Invariant test: no open task ever has a completed or deleted ancestor.

**P1-04 · Backend · Undo / redo** · deps: P1-03 · `todo`
- [ ] One undo step reverses exactly one user action: create, rename, note edit, complete (including the whole cascade), delete (whole subtree), indent, outdent, move.
- [ ] Undo restores the task to its exact prior parent and index. Redo re-applies it. A new action clears redo.
- [ ] The stack holds at least 50 steps, is app-wide and in-memory, and is empty after relaunch.
- [ ] Undo and redo with an empty stack are no-ops, not errors.

**P1-05 · Backend · History and restore** · deps: P1-03 · `todo`
- [ ] The history query returns completed, non-deleted tasks, newest first, each with title, completedAt, parent path and local-day key using the 04:00 boundary (tests at 03:59 and 04:00, and across a DST change).
- [ ] Restore clears completedAt on that one task and places it per D5; descendants completed with it stay in History.
- [ ] Count of tasks finished "today" (04:00 boundary) is available.

**P1-06 · Backend · Parent search** · deps: P1-02 · `todo`
- [ ] Given a query string, returns open tasks whose title starts with it, case-insensitive, most recently modified first, max 5, each with its path. Empty query returns nothing.

**P1-07 · Frontend · Nested outline rendering** · deps: P0-09, P1-01 · `todo`
- [ ] Row slots, chevron, hover, selected and editing states match DESIGN screen B in light and dark.
- [ ] A collapsed parent shows its open-descendant count at the right; leaf rows show no chevron.
- [ ] Nesting guides are 1px hairlines; the branch containing the selection draws its guide in accent.
- [ ] Toolbar shows the breadcrumb; the bottom hint bar shows the shortcuts listed in DESIGN, minus "⌘/ All shortcuts" (D20).

**P1-08 · Frontend · Keyboard navigation and editing** · deps: P1-07, P1-02 · `todo`
- [ ] ↑/↓ move a single selection through visible rows; selection never lands on a hidden row.
- [ ] Space or typing starts editing the selected row; Esc stops editing and keeps the text.
- [ ] ↵ on a selected row creates a sibling below in edit mode. ↵ while editing splits at the caret: text after the caret moves to a new sibling below; children stay with the original.
- [ ] ⇥ / ⇧⇥ indent / outdent, ⌘. toggles collapse, ⌘→ expands, ⌥⌘↑ / ⌥⌘↓ reorder within siblings; selection follows the row.
- [ ] ⌘⌫ deletes the selected row and its subtree; selection moves to next sibling, else previous, else parent.
- [ ] Empty-title handling follows D12. Every shortcut is a no-op on Inbox where D1 forbids it.

**P1-09 · Frontend · Zoom, breadcrumb, empty state** · deps: P1-08 · `todo`
- [ ] ⌘] zooms into the selected row: its title becomes the 36 light page title, its children the rows, "N open" its open descendants. ⌘[ zooms out one level with the former node selected.
- [ ] Breadcrumb shows `Home / … / Node`; clicking a crumb zooms there.
- [ ] Given a zoomed node with 0 open tasks, the "All clear." block fades in after 400 ms with the node name in the copy; ↵ creates its first child in edit mode.
- [ ] If the zoomed node is completed or deleted, the view zooms to its nearest open ancestor, else Home.

**P1-10 · Frontend · Drag reorder** · deps: P1-07, P1-02 · `todo`
- [ ] Hover shows the 6-dot handle; dragging shows the lifted row, a 35% ghost at the origin and the 2px accent drop line with ring.
- [ ] The drop line appears only at valid targets per D15; releasing moves the task and its subtree there. Esc or release on an invalid target cancels with no change.
- [ ] A drag is one undo step (once P1-12 lands).

**P1-11 · Frontend · Strike & Fold** · deps: P1-07, P1-03 · `todo`
- [ ] ⌘↵ or a circle click plays the timeline in DESIGN "Completion" (verify by screen recording frame-step: fill 0–90, strike 30–150, fade 90–160, fold 160–280 ms).
- [ ] A parent's children strike top to bottom with 40 ms stagger, then the branch folds as one.
- [ ] Five rapid ⌘↵ presses complete five rows; none is dropped or waits for a prior animation.
- [ ] Selection ends on next sibling, else previous, else parent.
- [ ] With Reduce Motion: instant fill and strike, 400 ms hold, 120 ms fade, single-frame reflow.

**P1-12 · Frontend · Undo wiring and toast** · deps: P1-04, P1-11 · `todo`
- [ ] ⌘Z / ⇧⌘Z in the outline call Core undo / redo; the restored row is selected and scrolled into view.
- [ ] After a completion the toast "Done · <title>  ⌘Z Undo" rises 8px in 160 ms, holds 4 s, pauses while hovered, and is replaced by the next completion's toast.
- [ ] While a title is being edited, ⌘Z undoes typing in the field only.

**P1-13 · Frontend · History** · deps: P1-05, P1-07 · `todo`
- [ ] ⌘Y shows "Home / History", title "Finished", meta "Kept forever, on this Mac"; ⌘[ or the Home crumb returns to the outline.
- [ ] Rows grouped by day with headers and counts per D16 and D17; row shows faint filled check, unstruck ink-mute title, parent path, time.
- [ ] ↑/↓ select rows. Hover or selection shows Restore; click or ⌘R restores and the row leaves History.

**P1-14 · Frontend · Capture: Details, `/name`, draft, ⌥↵** · deps: P0-07, P1-02, P1-06 · `todo`
- [ ] ⇥ in the title expands Details (Note, "Under" picker); ⇧⇥ returns to the title. In Note, ↵ is a newline and ⌘↵ saves. ↵ in the title always saves.
- [ ] The "Under" picker and `/name` both use parent search and behave per D7; the footer destination and the saved pill name the chosen parent.
- [ ] Given Esc with text entered, when the panel reopens within 60 s, then title, note and destination are restored; after 60 s or after a save it opens blank.
- [ ] ⌥↵ saves, clears the fields, keeps the panel open and the destination unchanged; no pill is shown.

## M3 — P2

**P2-01 · Backend · Today summary** · deps: P1-05 · `todo`
- [ ] One query returns: finished-today count (04:00 boundary), the 3 most recently finished titles, and the total open count.

**P2-02 · Frontend · Daily Closure card** · deps: P2-01 · `todo`
- [ ] ⌘D (outline or popover open) shows the 340-wide card anchored to the menu bar icon; Esc or ↵ closes it; ⌘Y opens History.
- [ ] Headline and closing line match the DESIGN copy table for counts 0, 1, 2–5, ≥6 and list-empty (precedence per D18).
- [ ] Marks: one bar per finished task, capped at 8. Titles: latest 3, then "and N more" when N > 0.
- [ ] No percentage, streak, goal, comparison, notification, sound or confetti appears anywhere.

**P2-03 · Frontend · Settings window** · deps: P0-04 · `todo`
- [ ] "Settings…" appears in the popover footer; it and ⌘, open one 560-wide window.
- [ ] Launch at login toggles `SMAppService` state and reflects the real state on reopen.
- [ ] Appearance System / Light / Dark applies instantly to all Hush surfaces and persists across relaunch.
- [ ] "Your tasks live on this Mac" shows the real DB path; Show in Finder reveals the file.

**P2-04 · Frontend · Shortcut recorder** · deps: P2-03, P0-06 · `todo`
- [ ] Recording a new combination re-registers the hotkey immediately; the old one stops working; the choice persists across relaunch.
- [ ] ✕ resets to ⌘⇧Space. A combination with no modifier, or one that fails to register, is rejected with an inline message and the previous shortcut stays active.
- [ ] The popover capture row shows the current shortcut.

**P2-05 · Frontend · Find** · deps: P1-07 · `todo`
- [ ] ⌘F focuses the toolbar Find field. Typing filters the current zoom level to open tasks whose title contains the text (case-insensitive) plus their ancestors, expanded.
- [ ] Esc clears the filter and restores the previous collapse state and selection.

## Product decisions
Team Lead defaults: all confirmed; D5 and D9 are refined, D8 is new and deviates from DESIGN.

- **D1 Inbox** — Confirmed: a real root-level task named "Inbox", created on first launch; cannot be completed or deleted. Added: it cannot be renamed, indented or moved, and is always the first root row. It is excluded from every count, from Recent and from History.
- **D2 Home** — Confirmed: Home is all top-level nodes. The outline opens at Home on launch and keeps its zoom level for the rest of the session.
- **D3 Parent completion** — Confirmed: completing a parent completes all open descendants; each gets completedAt and each is its own History row and counts as one finished task. One undo restores all.
- **D4 Completed tasks** — Confirmed: they leave the outline and appear only in History.
- **D5 Restore** — Confirmed with detail: original parent if it is open, else nearest open ancestor, else root; appended at the end. Restores that one task only. Restore is not on the undo stack.
- **D6 Delete** — Confirmed: ⌘⌫ is soft (deletedAt), covers the subtree, undoable in-session, no trash UI, no confirmation dialog, no toast.
- **D7 `/name` filing** — Confirmed: P1, case-insensitive prefix match on open task titles. The token is a `/` at the start of the title or after a space, running to the end of the input. Up to 5 suggestions; ↑/↓ choose, ↵ accepts, which removes the token from the title and sets the destination. With no accepted match the text stays in the title literally and the task goes to Inbox.
- **D8 Capture pill has no ⌘Z** — Deviation from DESIGN, ACCEPTED by Team Lead. Focus returns to the previous app immediately, so ⌘Z would belong to that app; hijacking it globally is not acceptable. The pill reads "✓ Saved to **Inbox**". From P1 a captured task is undoable with ⌘Z in the outline.
- **D9 Draft and ⌥↵** — Confirmed: P1. In P0, Esc discards.
- **D10 Recent** — The 5 most recently created open tasks at any depth, newest first. "N of M open": N rows shown, M all open tasks. Time is since creation: "now" under 1 min, then "5m", "2h", "3d", then "20 Nov".
- **D11 Notes** — Confirmed: plain text, P1, edited only in capture Details. The outline does not show or edit notes in MVP. Max 10,000 characters.
- **D12 Titles** — Single line, trimmed, 1–500 characters; pasted newlines become spaces. Capture ignores ↵ on an empty title. In the outline, a new row left empty is discarded silently (no undo step); emptying an existing title reverts to the previous title.
- **D13 Counts** — "N open" is the open descendants of the current zoom node, not counting the node itself. The collapsed-row count is that row's open descendants.
- **D14 Day boundary** — Confirmed: 04:00 local for "today", History grouping and Daily Closure.
- **D15 Drag targets** — Drops land between visible rows. Horizontal position picks a depth from the next row's depth up to the previous row's depth + 1 (which appends as last child, also for a collapsed row). Never into the dragged row's own subtree, never above Inbox. Keyboard reorder (⌥⌘↑↓) stays within siblings.
- **D16 History headers** — "Today", then weekday names for the previous 6 days, then "Friday 20 November" (with year when not the current year). Right side "N finished". Rows newest first. Time follows the system 12/24-hour setting.
- **D17 Quiet spans** — Today with nothing finished shows "A quiet day". Between days with completions, a one-day gap shows "A quiet day" and a gap of exactly Saturday + Sunday shows "A quiet weekend". Longer gaps show nothing. History shows the latest 500 completions; paging is deferred until someone hits it.
- **D18 Closure copy precedence** — If there are no open tasks at all, use the "All clear." pair regardless of count; otherwise choose by finished-today count. The "N things finished today." line always shows the true count.
- **D19 Selection** — Single selection only; no multi-select in MVP.
- **D20 Cut from DESIGN for MVP** — "⌘/ All shortcuts" (no sheet is specified) and the closure card's "↵ Reflect" (behaviour unspecified; ↵ just closes). Both are hidden rather than shown inert.
- **D21 Undo scope** — One app-wide stack covering create, rename, note, complete, delete, indent, outdent, move. Collapse, zoom and restore are not undoable.
- **D22 New tasks** — Capture appends to the end of the destination's children. Outline ↵ always inserts a sibling directly below. No nesting depth cap; zoom is the answer to deep trees.
- **D23 First launch** — No onboarding, no sample tasks, no window. Only the menu bar icon appears.
- **D24 Hotkey conflict** — If the shortcut cannot be registered, fail quietly until P2-04 adds the inline message.

## Open questions
Engineers: append `Q<n> (role, task ID): question`. PM answers inline and promotes lasting answers to Product decisions.

_None yet._

## Out of scope (MVP)
Sync or cloud of any kind · accounts · AI · notifications · sounds · streaks, goals, percentages, comparisons, confetti · tags · due dates, reminders, recurrence · calendars · multi-select · trash UI · notes in the outline · rich text or Markdown · attachments · import / export · multiple windows of the outline · iOS or widgets · onboarding · Dock icon · shortcuts sheet (⌘/) · Reflect · Focus Mode · Quiet Momentum.
