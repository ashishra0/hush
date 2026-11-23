# Status (Team Lead)

**Milestone:** MVP (M1–M3) code-complete. Awaiting manual runtime pass (docs/BOARD.md "Manual test script").

| Area | Owner | State |
|---|---|---|
| Backlog, acceptance review, manual test script | PM | done |
| HushCore (store, outline, cascade, undo/redo, history, summaries) | Backend | done — 29 tests green |
| Capture panel, hotkey, menu bar, outline, drag, Strike & Fold, undo toast | Frontend-1 | built; `review` (needs real keystrokes) |
| History, capture Details//name/draft, Settings, Daily Closure card | Frontend-2 | built; `review` (needs real keystrokes) |

**Runtime-verified by Team Lead:** bundle + launch; menu bar icon; hotkey registers; outline render (nesting, accent branch guide, collapsed counts, hidden completed, N open, centered hint bar, All clear). 
**Not verified (no desktop automation here):** keystroke paths, hotkey → capture → focus return, mouse drag, animation timing, light mode, Settings/Closure visuals.
**Review findings:** F1 blocker + F2–F11 fixed.
**Deferred post-MVP:** Find (⌘F), full-screen reflection, Quiet Momentum, Focus Mode, ⌘/ shortcuts sheet.
**Decisions:** Carbon hotkey; parent:nil = top-level; D8 no ⌘Z on pill; D20 cuts; D25 Find deferred; D26 no beeps.
