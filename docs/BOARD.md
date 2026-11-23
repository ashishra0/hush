# Hush — Board (PM)

Source of truth for UI: `docs/DESIGN.md`. Ownership and tech decisions: `docs/ARCHITECTURE.md`. API: `docs/CONTRACTS.md` (Backend).
Status: `todo` · `doing` · `review` (built, needs a manual check) · `done`. M1–M3 are `done`: review findings F1–F11 were fixed in ded4d8f and the user tested the MVP and reports it works. Engineers set status on their own M4 tasks; only PM edits scope and acceptance criteria.
A task is done when its criteria pass, `swift build` is warning-free and `swift test` is green. BE criteria are proven by Swift Testing tests on an in-memory DB; FE criteria by running `build/Hush.app`.

## Milestones
| | Scope | Exit test |
|---|---|---|
| **M1 = P0** | App shell, menu bar item + popover, global ⌘⇧Space, Quick Capture (title only), SQLite persistence, create / list / complete | Capture a task from any app, see it in the popover and outline, complete it, quit, relaunch: state is intact. |
| **M2 = P1** | Nested outline, keyboard nav and editing, reorder incl. drag, Strike & Fold, undo, History, capture Details / `/name` / draft / ⌥↵ | Every outline shortcut in DESIGN "Keyboard" works without the mouse, except ⌘F and ⌘D (M3). |
| **M3 = P2** | Daily Closure card, Settings (Find deferred, D25) | Design screens C and D and the closure card are complete. |
| **M4 = P3** | Quiet Momentum, Find, full-screen reflection + week strip, Focus Mode, shortcuts sheet, polish | Every item in DESIGN "Post-MVP (M4)" works, and the Polish bar holds on every surface in light and dark. |

## M1 — P0

**P0-01 · Backend · Contract v1** · deps: none · `done`
- [x] `docs/CONTRACTS.md` lists the public types and signatures for: open the store (file or in-memory), create task, complete task, list open tasks as a tree, observe changes, open-task count.
- [x] The task type already carries parent, sibling order, note, collapsed, createdAt, completedAt, deletedAt, so P1 adds no breaking change.
- [x] The signatures compile in `HushCore` (bodies may be unimplemented) so Frontend can build against them. Ship this before P0-02.

**P0-02 · Backend · Schema, migrations, Inbox seed** · deps: P0-01 · `done`
- [x] Given no DB file, when the store opens, then the file is created at the ARCHITECTURE path and contains exactly one task: root-level "Inbox".
- [x] Given an existing DB, when the store opens again, then no second Inbox is created and existing tasks are unchanged.
- [x] Completing, deleting, renaming or moving Inbox fails with a typed error and changes nothing.

**P0-03 · Backend · Create, list, complete, observe** · deps: P0-02 · `done`
- [x] Create with a parent puts it at the end of that parent's children; `parent: nil` creates a top-level project (Team Lead decision — capture passes `inbox().id` explicitly).
- [x] Titles are validated per decision D12; invalid titles fail with a typed error and write nothing.
- [x] Complete sets completedAt; the task no longer appears in the open list or the open count.
- [x] The open list returns tasks in sibling order with depth or parent links, Inbox first.
- [x] An observer receives a new snapshot after every create and complete, with no polling.
- [x] Data survives closing and reopening the store.

**P0-04 · Frontend · App shell and bundle** · deps: none · `done`
- [x] `scripts/bundle.sh` produces `build/Hush.app` that launches by double-click.
- [x] No Dock icon and no app-switcher entry. The menu bar shows the template icon (14px circle outline with centre dot), legible in light and dark menu bars.
- [x] Launching a second copy does not create a second menu bar item.
- [x] ⌘Q from any Hush window or the popover quits; closing a window does not quit.

**P0-05 · Frontend · Theme tokens** · deps: none · `done`
- [x] Every colour, type size, radius and spacing value in DESIGN "Tokens" exists as a named token; views use tokens, never literals. (Accepted in review: a few one-off sizes are literals.)
- [x] Switching system appearance while the app runs updates all open Hush surfaces without relaunch.

**P0-06 · Frontend · Global hotkey** · deps: P0-04 · `done`
- [x] Given any app is frontmost, when ⌘⇧Space is pressed, then Quick Capture appears within 100 ms with the caret in the input.
- [x] Pressing ⌘⇧Space while the panel is open closes it (same as Esc).
- [x] If registration fails, the app still launches and capture remains reachable from the popover.

**P0-07 · Frontend · Quick Capture panel (title only)** · deps: P0-06; P0-01 to build, P0-03 to save · `done`
- [x] Panel is 640 wide, horizontally centred, top edge at about 23% of the height of the screen containing the pointer. Placeholder "What's on your mind?". Footer shows the Inbox destination left and `↵ Save` right (`⇥ Details` hidden until P1-14).
- [x] Given a non-empty title, when ↵ is pressed, then the task is saved to Inbox, the panel morphs to the pill "✓ Saved to **Inbox**" (180 ms in, 900 ms hold, 150 ms fade), and the previously frontmost app is frontmost again immediately.
- [x] Given an empty or whitespace-only title, ↵ does nothing and the panel stays open.
- [x] Esc or a click outside closes the panel, discards the text (draft retention is P1-14) and returns focus to the previous app.
- [x] With Reduce Motion on, the pill appears and disappears with opacity only.

**P0-08 · Frontend · Menu bar popover** · deps: P0-04, P0-03 · `done`
- [x] Clicking the menu bar icon opens a 320-wide popover matching DESIGN screen C; clicking outside or Esc closes it.
- [x] The capture row shows "Capture a task…" and the shortcut; clicking it closes the popover and opens Quick Capture.
- [x] RECENT shows up to 5 rows and "N of M open" per D10; rows update live when a task is captured or completed.
- [x] Clicking a row's circle completes that task and the row disappears. Clicking the row text opens the outline.
- [x] With zero open tasks the rows are replaced by one caption line "All clear." and the count is hidden.
- [x] Footer: Open outline ⌘O and Quit Hush ⌘Q work by click and by key while the popover is open. "Settings…" is hidden until P2-03.

**P0-09 · Frontend · Outline window v0 (read and complete)** · deps: P0-03, P0-05 · `done`
- [x] ⌘O or "Open outline" opens one window (~1040×780, 720 content column, title "Home" 36 light, meta "N open"). Opening again focuses the existing window.
- [x] All open tasks appear as 32-high rows in store order, indented 24 per level; Inbox shows a folder glyph instead of a circle.
- [x] Clicking a circle completes the task; the row is removed (no animation in P0) and "N open" updates.
- [x] A task saved from Quick Capture appears without reopening the window.
- [x] No editing, creation, selection or shortcuts in this task; those are M2.

## M2 — P1

**P1-01 · Backend · Contract v2** · deps: P0-03 · `done`
- [x] CONTRACTS.md adds signatures for everything in P1-02 to P1-06, compiling, before any of them is implemented. Frontend sign-off recorded in the "Requests" section.

**P1-02 · Backend · Tree operations** · deps: P1-01 · `done`
- [x] Create at a given parent and index; rename; set note; set collapsed (persisted).
- [x] Indent: the task becomes the last child of its previous sibling, taking its subtree; no-op with no previous sibling.
- [x] Outdent: the task becomes the sibling immediately after its former parent; no-op at root.
- [x] Move to (parent, index): rejects a move into the task's own subtree and any move that displaces Inbox from first root position.
- [x] After any sequence of operations, sibling orders are gap-free and unique (property-style test).
- [x] The subtree query for any node returns open descendants plus an open-descendant count per node.

**P1-03 · Backend · Cascade complete and soft delete** · deps: P1-02 · `done`
- [x] Completing a parent gives the parent and every open descendant a completedAt in one transaction.
- [x] Delete sets deletedAt on the task and all its open descendants; deleted tasks appear in no list, count or History.
- [x] Invariant test: no open task ever has a completed or deleted ancestor.

**P1-04 · Backend · Undo / redo** · deps: P1-03 · `done`
- [x] One undo step reverses exactly one user action: create, rename, note edit, complete (including the whole cascade), delete (whole subtree), indent, outdent, move.
- [x] Undo restores the task to its exact prior parent and index. Redo re-applies it. A new action clears redo.
- [x] The stack holds at least 50 steps, is app-wide and in-memory, and is empty after relaunch.
- [x] Undo and redo with an empty stack are no-ops, not errors.

**P1-05 · Backend · History and restore** · deps: P1-03 · `done`
- [x] The history query returns completed, non-deleted tasks, newest first, each with title, completedAt, parent path and local-day key using the 04:00 boundary (tests at 03:59 and 04:00, and across a DST change).
- [x] Restore clears completedAt on that one task and places it per D5; descendants completed with it stay in History.
- [x] Count of tasks finished "today" (04:00 boundary) is available.

**P1-06 · Backend · Parent search** · deps: P1-02 · `done`
- [x] Given a query string, returns open tasks whose title starts with it, case-insensitive, newest created first (amended in review: there is no modified date), max 5, each with its path. Empty query returns nothing.

**P1-07 · Frontend · Nested outline rendering** · deps: P0-09, P1-01 · `done`
- [x] Row slots, chevron, hover, selected and editing states match DESIGN screen B in light and dark.
- [x] A collapsed parent shows its open-descendant count at the right; leaf rows show no chevron.
- [x] Nesting guides are 1px hairlines; the branch containing the selection draws its guide in accent.
- [x] Toolbar shows the breadcrumb; the bottom hint bar shows the shortcuts listed in DESIGN, minus "⌘/ All shortcuts" (D20).

**P1-08 · Frontend · Keyboard navigation and editing** · deps: P1-07, P1-02 · `done`
- [x] ↑/↓ move a single selection through visible rows; selection never lands on a hidden row.
- [x] Space or typing starts editing the selected row; Esc stops editing and keeps the text.
- [x] ↵ on a selected row creates a sibling below in edit mode. ↵ while editing splits at the caret: text after the caret moves to a new sibling below; children stay with the original.
- [x] ⇥ / ⇧⇥ indent / outdent, ⌘. toggles collapse, ⌘→ expands, ⌥⌘↑ / ⌥⌘↓ reorder within siblings; selection follows the row.
- [x] ⌘⌫ deletes the selected row and its subtree; selection moves to next sibling, else previous, else parent.
- [x] Empty-title handling follows D12. Every shortcut is a no-op on Inbox where D1 forbids it.

**P1-09 · Frontend · Zoom, breadcrumb, empty state** · deps: P1-08 · `done`
- [x] ⌘] zooms into the selected row: its title becomes the 36 light page title, its children the rows, "N open" its open descendants. ⌘[ zooms out one level with the former node selected.
- [x] Breadcrumb shows `Home / … / Node`; clicking a crumb zooms there.
- [x] Given a zoomed node with 0 open tasks, the "All clear." block fades in after 400 ms with the node name in the copy; ↵ creates its first child in edit mode.
- [x] If the zoomed node is completed or deleted, the view zooms to its nearest open ancestor, else Home.

**P1-10 · Frontend · Drag reorder** · deps: P1-07, P1-02 · `done`
- [x] Hover shows the 6-dot handle; dragging shows the lifted row, a 35% ghost at the origin and the 2px accent drop line with ring.
- [x] The drop line appears only at valid targets per D15; releasing moves the task and its subtree there. Esc or release on an invalid target cancels with no change.
- [x] A drag is one undo step (once P1-12 lands).

**P1-11 · Frontend · Strike & Fold** · deps: P1-07, P1-03 · `done`
- [x] ⌘↵ or a circle click plays the timeline in DESIGN "Completion" (verify by screen recording frame-step: fill 0–90, strike 30–150, fade 90–160, fold 160–280 ms).
- [x] A parent's children strike top to bottom with 40 ms stagger, then the branch folds as one.
- [x] Five rapid ⌘↵ presses complete five rows; none is dropped or waits for a prior animation.
- [x] Selection ends on next sibling, else previous, else parent.
- [x] With Reduce Motion: instant fill and strike, 400 ms hold, 120 ms fade, single-frame reflow.

**P1-12 · Frontend · Undo wiring and toast** · deps: P1-04, P1-11 · `done`
- [x] ⌘Z / ⇧⌘Z in the outline call Core undo / redo; the restored row is selected and scrolled into view.
- [x] After a completion the toast "Done · <title>  ⌘Z Undo" rises 8px in 160 ms, holds 4 s, pauses while hovered, and is replaced by the next completion's toast.
- [x] While a title is being edited, ⌘Z undoes typing in the field only.

**P1-13 · Frontend · History** · deps: P1-05, P1-07 · `done`
- [x] ⌘Y shows "Home / History", title "Finished", meta "Kept forever, on this Mac"; ⌘[ or the Home crumb returns to the outline.
- [x] Rows grouped by day with headers and counts per D16 and D17; row shows faint filled check, unstruck ink-mute title, parent path, time.
- [x] ↑/↓ select rows. Hover or selection shows Restore; click or ⌘R restores and the row leaves History.

**P1-14 · Frontend · Capture: Details, `/name`, draft, ⌥↵** · deps: P0-07, P1-02, P1-06 · `done`
- [x] ⇥ in the title expands Details (Note, "Under" picker); ⇧⇥ returns to the title. In Note, ↵ is a newline and ⌘↵ saves. ↵ in the title always saves.
- [x] The "Under" picker and `/name` both use parent search and behave per D7; the footer destination and the saved pill name the chosen parent.
- [x] Given Esc with text entered, when the panel reopens within 60 s, then title, note and destination are restored; after 60 s or after a save it opens blank.
- [x] ⌥↵ saves, clears the fields, keeps the panel open and the destination unchanged; no pill is shown.

## M3 — P2

**P2-01 · Backend · Today summary** · deps: P1-05 · `done`
- [x] One query returns: finished-today count (04:00 boundary), the 3 most recently finished titles, and the total open count.

**P2-02 · Frontend · Daily Closure card** · deps: P2-01 · `done`
- [x] ⌘D (outline or popover open) shows the 340-wide card anchored to the menu bar icon; Esc or ↵ closes it; ⌘Y opens History.
- [x] Headline and closing line match the DESIGN copy table for counts 0, 1, 2–5, ≥6 and list-empty (precedence per D18).
- [x] Marks: one bar per finished task, capped at 8. Titles: latest 3, then "and N more" when N > 0.
- [x] No percentage, streak, goal, comparison, notification, sound or confetti appears anywhere.

**P2-03 · Frontend · Settings window** · deps: P0-04 · `done`
- [x] "Settings…" appears in the popover footer; it and ⌘, open one 560-wide window.
- [x] Launch at login toggles `SMAppService` state and reflects the real state on reopen.
- [x] Appearance System / Light / Dark applies instantly to all Hush surfaces and persists across relaunch.
- [x] "Your tasks live on this Mac" shows the real DB path; Show in Finder reveals the file.

**P2-04 · Frontend · Shortcut recorder** · deps: P2-03, P0-06 · `done`
- [x] Recording a new combination re-registers the hotkey immediately; the old one stops working; the choice persists across relaunch.
- [x] ✕ resets to ⌘⇧Space. A combination with no modifier, or one that fails to register, is rejected with an inline message and the previous shortcut stays active.
- [x] The popover capture row shows the current shortcut.

**P2-05 · Frontend · Find** · deps: P1-07 · `todo` — superseded by P3-03, P3-05 and P3-13 (D28)
- [ ] ⌘F focuses the toolbar Find field. Typing filters the current zoom level to open tasks whose title contains the text (case-insensitive) plus their ancestors, expanded.
- [ ] Esc clears the filter and restores the previous collapse state and selection.

## M4 — Post-MVP + polish
Spec: DESIGN "Post-MVP (M4)". Owners: **BE** = HushCore · **FE-1** = Outline*, AppDelegate, Theme, PopoverView, HotKey · **FE-2** = Closure*, Reflection*, History*, Settings*, CapturePanel. Frontend may build against P3-01 signatures before the Backend bodies land.

**P3-01 · BE · Contract v3** · deps: none · `todo`
- [ ] CONTRACTS.md gains compiling signatures for P3-02 to P3-04 before any body is written; existing signatures do not change.

**P3-02 · BE · Day summary and week counts** · deps: P3-01 · `todo`
- [ ] Summary for any local day (04:00 boundary, DST-safe): finished count, every finished task with its completedAt (newest first), and the ClosureCopy pair per D31.
- [ ] Week query: 7 finished-counts for the previous 6 days plus today, oldest first, each with its day date; days with nothing return 0.
- [ ] Today's result equals the existing today summary; deleted tasks are never counted. Tests cover 03:59 / 04:00 and an empty day.

**P3-03 · BE · Find** · deps: P3-01 · `todo`
- [ ] Outline find: given a query and an optional root, returns the open tasks under that root whose title contains the query (case-insensitive, including non-ASCII such as "É"/"é"), as a tree that keeps every ancestor and flags which nodes match.
- [ ] History find: finished tasks whose title contains the query, grouped by day exactly like History, searching all completions and returning the newest 500 matches.
- [ ] Blank query returns nothing; `%`, `_` and `\` match literally; notes and Inbox itself are never matched.

**P3-04 · BE · Next open task** · deps: P3-01 · `todo`
- [ ] Given an open task and a scope root, returns the next open task in outline pre-order within that scope: for Skip, the next row (its own children first); for Complete, the first task after its whole subtree.
- [ ] Never returns Inbox itself (its children are eligible); returns nil at the end of the scope, never wrapping. Collapsed state does not affect order.

**P3-05 · FE-1 · Find in the outline** · deps: P3-03 · `todo`
- [ ] Toolbar field per DESIGN (200×26, magnifier, "Find", ⌘F hint). ⌘F commits any edit in progress and focuses it.
- [ ] Typing filters the current zoom level: ancestors ink-faint, matches ink with the matched substring bold. No match shows "No open tasks match “q”." in ink-faint.
- [ ] ↑/↓ move among matches only. ↵ clears the query, expands the match's ancestors, selects it and scrolls it into view. Esc clears and returns focus to the outline with the prior selection and collapse state.
- [ ] While the field has focus, no outline shortcut other than ↑ ↓ ↵ Esc acts on rows.

**P3-06 · FE-1 · Quiet Momentum marks** · deps: P3-10 (shares key, D29) · `todo`
- [ ] With the setting on and ≥1 finished today: 3×11 bars (3px gap, ink-mute, max 8) and "N today" sit right of Find. Hidden at 0 and whenever the setting is off; toggling applies without reopening the window.
- [ ] On completion a new bar grows scaleY 0→1 starting 90 ms into Strike & Fold and fades accent → ink-mute over 600 ms; Reduce Motion shows it at once. Undoing the completion removes it.
- [ ] Clicking the marks opens the Daily Closure card anchored to them; ⌘D does the same when the marks are visible and the outline is key, else anchors to the menu bar icon.
- [ ] The count is correct after 04:00 passes, at the latest when the window next becomes key.

**P3-07 · FE-1 · Focus Mode** · deps: P3-04 · `todo`
- [ ] ⌘⇧F on a selected row, or "Focus" in the row's right-click menu, switches the same window to the focus layout in DESIGN (toolbar "FOCUS", ghost rows at 10%, breadcrumb, 28px circle, title 44 light, note read-only, "Up next"). No-op on Inbox.
- [ ] ⌘↵ completes (cascade per D3) and shows the next task; ↓ skips to the next without completing. Order and scope per D30.
- [ ] When nothing is left: "That's everything." and "N finished in this focus session" (count per D30).
- [ ] Esc or ⌘⇧F returns to the outline with the current task, else the last one focused, selected. ⌘Z undoes the last completion and focuses that task again.
- [ ] Transition timings per DESIGN; Reduce Motion is a crossfade only.

**P3-08 · FE-1 · Shortcuts sheet** · deps: none · `todo`
- [ ] ⌘/ in the outline toggles a 480-wide sheet titled "Keyboard" with groups Capture · Outline · Views; Esc closes it and focus returns to the outline.
- [ ] Every shortcut in DESIGN "Keyboard" plus ⌘F, ⌘⇧F and ⌘/ is listed and each listed shortcut works; the capture row shows the current (rebound) shortcut.
- [ ] "⌘/ All shortcuts" is back at the end of the outline hint bar.

**P3-09 · FE-1 · Polish: outline, popover, app** · deps: P3-05 to P3-08 for the final pass · `todo`
- [ ] Outline titles wrap, never clip; row height grows in 22pt steps; guides, selection wash, drag drop line and Strike & Fold stay correct next to a 3-line row. Popover titles truncate with ….
- [ ] VoiceOver: circles read "Complete <title>", rows "<title>, level N, N open inside, collapsed" (only the parts that apply), marks "N finished today".
- [ ] Outline window has a minimum size at which nothing overlaps, restores its frame after relaunch, and ⌘W closes it. No colour literal outside Theme in FE-1 files.
- [ ] Menu bar icon appears within 300 ms of launch (measured, release build) with no layout jump when the outline or popover first opens. Light and dark each checked against DESIGN tokens.

**P3-10 · FE-2 · Settings toggle** · deps: none · `todo`
- [ ] Settings shows a switch "Show today's progress in the toolbar", off on first launch, persisted under the key in D29, applied instantly.

**P3-11 · FE-2 · Reflection window** · deps: P3-02 · `todo`
- [ ] ↵ on the Daily Closure card opens a borderless window filling the screen that holds the card, always #0B0B0C; the card footer shows "↵ Reflect" again.
- [ ] 640 column per DESIGN: date line, headline 64 light, count line, two-column time + title list (max 12, then "and N more"), italic closing line. Copy matches the card for today.
- [ ] Opens with the 320 ms headline-grow cross-dissolve (150 ms fade with Reduce Motion). Esc closes and restores the previously key window; ⌘Y closes and opens History.

**P3-12 · FE-2 · Week strip and other days** · deps: P3-11 · `todo`
- [ ] "THIS WEEK" strip: 7 columns oldest to Today, one 4px dot per finished task (max 12), zero days show only the label, Today in #F2F2F3 semibold, caption per DESIGN.
- [ ] ← / → move one day within the strip's 7 days (D31); → on today and ← on the oldest day do nothing. Date line, headline, count and list update; a day with nothing reads "A quiet day."

**P3-13 · FE-2 · Find in History** · deps: P3-03 · `todo`
- [ ] ⌘F focuses a "Find finished" field styled like the outline's. Typing filters rows, keeping day headers that still have rows, with the match bold; no match shows "No finished tasks match “q”.".
- [ ] ↑/↓ move among matches, ↵ clears the query and leaves that row selected and visible, Esc clears and returns focus to the list (a second Esc closes History as today). ⌘R restores the selected match.

**P3-14 · FE-2 · Polish: History, Settings, card, capture, reflection** · deps: P3-10 to P3-13 for the final pass · `todo`
- [ ] History and suggestion titles truncate with …; nothing clips at minimum window size. History and Settings restore their frames; ⌘W closes each; Esc per D32.
- [ ] VoiceOver: History rows read title, path and time; Restore, the switch, appearance tiles and the shortcut recorder have labels.
- [ ] Light and dark each checked against DESIGN tokens; no colour literal outside Theme in FE-2 files except the fixed reflection palette.

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
- **D20 (superseded by D27)** — "⌘/ All shortcuts" (no sheet is specified) and the closure card's "↵ Reflect" (behaviour unspecified; ↵ just closes). Both are hidden rather than shown inert.
- **D21 Undo scope** — One app-wide stack covering create, rename, note, complete, delete, indent, outdent, move. Collapse, zoom and restore are not undoable.
- **D22 New tasks** — Capture appends to the end of the destination's children. Outline ↵ always inserts a sibling directly below. No nesting depth cap; zoom is the answer to deep trees.
- **D23 First launch** — No onboarding, no sample tasks, no window. Only the menu bar icon appears.
- **D24 Hotkey conflict** — If the shortcut cannot be registered, fail quietly until P2-04 adds the inline message.
- **D25 (superseded by D28)** — P2-05 is not built for MVP. Nothing else depends on it, the toolbar reads correctly without the field, and zoom plus collapse cover navigation at MVP list sizes; the remaining effort goes to F1 and the manual pass. ⌘F stays unbound.
- **D26 Errors are silent** — A rejected action (invalid title, protected Inbox) is a no-op with no system beep, in line with "no sounds".
- **D27 Reflect and ⌘/ are built (supersedes D20)** — ↵ on the closure card opens the full-screen reflection; ⌘/ opens the shortcuts sheet and its hint returns to the hint bar.
- **D28 Find is built (supersedes D25)** — Outline Find filters the current zoom level; History has its own field. Both match titles only, by case-insensitive substring.
- **D29 Quiet Momentum** — Off by default. One UserDefaults Bool, key `showMomentum`, written by Settings and read by the outline. "N today" counts per D3 with the 04:00 boundary. It shows no goal, streak or comparison.
- **D30 Focus order and count** — Scope is the zoom level you entered from. Next is pre-order from the focused task; skipped tasks are not revisited and there is no wrap. The session count is every task completed in this focus session (cascaded descendants included, undone ones removed); it resets on exit.
- **D31 Reflection days** — ← / → cover only the 7 days in the week strip; older days live in History. Today uses the card's copy (D18); past days choose copy by finished count alone and show the date line without a time.
- **D32 Esc** — Esc undoes the innermost transient state first: Find text, then edit mode, then a drag, then a sheet, card, panel, reflection or Focus. It never closes the outline or Settings window; History keeps closing on Esc when nothing else is active.

## Open questions
Engineers: append `Q<n> (role, task ID): question`. PM answers inline and promotes lasting answers to Product decisions.

_None yet._

## Out of scope (MVP and M4)
Sync or cloud of any kind · accounts · AI · notifications · sounds · streaks, goals, percentages, comparisons, confetti · tags · due dates, reminders, recurrence · calendars · multi-select · trash UI · notes in the outline · rich text or Markdown · attachments · import / export · multiple windows of the outline · iOS or widgets · onboarding · Dock icon.

## Review findings (PM)
Review of c34774a by reading code and tests; nothing was run. All eleven were fixed in ded4d8f (F1 re-read in code by PM; the rest spot-checked by grep and covered by the user's MVP test). Paths are relative to `Sources/`.

| # | Criterion | Defect | Where | Severity |
|---|---|---|---|---|
| F1 | P1-03 box 2, D4 | Deleting a task also soft-deletes its already-completed descendants, so they vanish from History and the today count. Only open descendants should be deleted. | `HushCore/TaskStore.swift:264` (`notDeleted: true`) | fixed (**blocker**) |
| F2 | P1-05 box 1, D14 | The 04:00 boundary is computed by subtracting 4 absolute hours, so on the two DST-change days it sits one hour off. No DST test exists. | `HushCore/TaskStore.swift:420`, `:429-431`; `Tests/HushCoreTests/TaskStoreTests.swift:129` | fixed (minor) |
| F3 | P0-07 box 2 | The saved pill appears at full opacity at once; the 180 ms morph-in is missing (hold and fade are correct). | `Hush/CapturePanel.swift:344-350` | minor |
| F4 | P0-08 box 5 | With zero open tasks the header still shows "0 of 0 open"; the count should be hidden. | `Hush/PopoverView.swift:45-52` | minor |
| F5 | P0-08 box 6, DESIGN C | Popover footer has a "History ⌘Y" row that is not in the design. Remove the row; ⌘Y still works through the menu. | `Hush/PopoverView.swift:72-73` | minor |
| F6 | D20 | Closure card footer shows the "↵ Reflect" hint; it should be hidden. | `Hush/ClosureCard.swift:55` | minor |
| F7 | P2-03, DESIGN D | Appearance is a segmented control, not the three preview tiles. | `Hush/SettingsWindow.swift:167-169` | minor |
| F8 | P2-04 box 3 | A shortcut on a non-letter key displays as "Key 18" in Settings and the popover. | `Hush/HotKey.swift:68-71` | minor |
| F9 | D26 | Rejected actions call `NSSound.beep()`. | `Hush/OutlineModel.swift:225`, `:233`, `:279`, `:285`; `Hush/CapturePanel.swift:334-335` | minor |
| F10 | P1-04 box 3, D5 | Restoring from History empties the whole undo and redo stacks, so an earlier completion can no longer be undone. Restore should only skip adding a step. | `HushCore/TaskStore.swift:285` | fixed (minor) |
| F11 | P0-03 box 5 | No test covers the `observe…` functions. | `Tests/HushCoreTests/TaskStoreTests.swift` | fixed (minor) |

Not defects: P1-01's Frontend sign-off was never recorded (Requests is empty); moot now that both sides shipped.

## Manual test script
About 3 minutes. Covers every task marked `review`. Run steps 1–14 on a throwaway database.

1. `scripts/bundle.sh`, then `HUSH_DB_PATH=/tmp/hush-qa.sqlite build/Hush.app/Contents/MacOS/Hush &` (delete that file first). Expect a menu bar icon, no Dock icon, no window.
2. With TextEdit frontmost press ⌘⇧Space: the panel appears at once, 640 wide near the top, caret in the field. ↵ on the empty field does nothing. Type `Buy milk` ↵: pill "✓ Saved to Inbox" for about a second, and the next key you type lands in TextEdit.
3. ⌘⇧Space, type `draft`, Esc. ⌘⇧Space again: `draft` is back. ⌘⇧Space once more closes it. Reopen and click outside: it closes.
4. ⌘⇧Space, replace the text with `Plan trip`, ⌥↵: the panel stays and clears. Type `Book flights /pl`: "Plan trip" is suggested; ↵ accepts, the token disappears and the footer names Plan trip. ⇥, type a two-line note (↵ makes a newline), ⇧⇥, ↵: pill "✓ Saved to Plan trip".
5. Click the menu bar icon: 320-wide popover, Book flights / Plan trip / Buy milk newest first, "3 of 3 open". Click the circle on Buy milk: the row goes, "2 of 2 open". Esc closes the popover.
6. Open the popover and press ⌘O: the outline opens showing Inbox › Plan trip › Book flights. ⌘O again gives the same window. Capture `Live` with the hotkey: it appears in the outline without reopening.
7. In the outline: ↓ to Live, ↵, type `Alpha`, ↵, type `Beta`, Esc. ⇥ nests Beta under Alpha, ⇧⇥ brings it back, ⌥⌘↑ / ⌥⌘↓ reorder it. Space to edit, put the caret mid-word, ↵ splits the row. Type a few letters, ⌘Z removes only the typing, Esc. Edit a title to empty and Esc: the old title returns.
8. Select Plan trip. ⌘. collapses it and shows "1" at the right; ⌘→ expands. ⌘] zooms in (title "Plan trip", breadcrumb Home / Inbox / Plan trip, "1 open"); click the Inbox crumb, then ⌘[ returns to Home with Inbox selected.
9. Select Alpha, ⌘⌫: it disappears and a neighbour is selected. ⌘Z brings it back selected, ⇧⌘Z removes it again, ⌘Z restores it.
10. Hover Beta and drag its six-dot handle: lifted row, faint ghost at the origin, blue drop line with ring; moving sideways changes the line's depth. No line appears above Inbox or inside Beta's own subtree. Drop it under Plan trip; ⌘Z puts it back in one step. Start another drag and press Esc: nothing moves.
11. Select Plan trip, ⌘↵: the circle fills blue, the strike draws left to right, the child strikes just after, the branch folds, and the toast "Done · Plan trip  ⌘Z Undo" rises and stays about 4 s (longer while hovered). ⌘Z restores both rows. Now press ⌘↵ rapidly until only Inbox is left: no row is skipped. Select Inbox, ⌘]: "All clear." fades in; ↵ starts a new row. Complete one more task with Reduce Motion on: no fold, just a short fade.
12. ⌘Y: "Home / History", title "Finished", a Today header with a count, unstruck grey titles with path and time. ↓ selects a row, ⌘R restores it and the row leaves. ⌘[ returns to the outline, where the task is back.
13. ⌘D: a card under the menu bar icon; headline fits the count (2–5 gives "Steady progress."), one bar per finished task up to 8, three titles then "and N more". ↵ closes it. ⌘D then ⌘Y opens History.
14. ⌘, opens Settings. Switch Light, Dark, System: outline, popover and Settings change at once; in Light, check the selected-row wash, hover fill and guides against DESIGN tokens. Click the shortcut, press ⌃⌥H: ⌘⇧Space stops opening capture, ⌃⌥H opens it, the popover row shows the new shortcut. Record a bare letter: rejected with a message. ✕ resets to ⌘⇧Space.
15. ⌘W closes a window and the icon stays; ⌘Q quits. Relaunch as in step 1: tasks and collapsed state are intact; quit. Then run `open build/Hush.app` twice: one menu bar icon. In Settings, toggle Launch at login and reopen Settings (state holds), and Show in Finder reveals `hush.sqlite`.
