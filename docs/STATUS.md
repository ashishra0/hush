# Status (Team Lead)

**Milestone:** M2 — P1 core experience. (M1/P0 code-complete; manual hotkey test pending with user.)

| Area | Owner | State |
|---|---|---|
| Backlog, acceptance criteria | PM | done (docs/BOARD.md); idle until review |
| HushCore: store, outline, completion, history, undo/redo, parent search, closure copy | Backend | done, 25 tests green; idle |
| Outline window, nested rendering, keyboard, zoom, Strike & Fold | Frontend-1 | in progress |
| History window, capture Details / `/name` / draft / ⌥↵ | Frontend-2 | in progress |
| Drag reorder (P1-10), undo wiring + toast (P1-12) | Frontend-1 | next |

**Verified at runtime:** app bundles + launches, menu bar icon renders, hotkey registers without error.
**Not yet verified:** pressing ⌘⇧Space → panel → save → focus return (no desktop automation available; needs a human).
**Decisions:** Carbon hotkey (not KeyboardShortcuts); `create(parent: nil)` = top-level (capture passes Inbox); D8 pill has no ⌘Z (accepted); D20 cuts ⌘/ sheet and ↵ Reflect; frontend must use `store.undo()` not receipts.
**Blockers:** none.
