# Status (Team Lead)

**Milestone:** M4 (post-MVP + polish) code-complete and visually verified. All designed features shipped.

| Area | State |
|---|---|
| HushCore | 33 tests green: store, cascade, undo/redo, history, day summaries, week counts, find, next-open |
| Capture, menu bar, outline, drag, Strike & Fold, undo toast | done (MVP, user-tested) |
| Find (outline + History), Focus Mode, Quiet Momentum, ⌘/ sheet | done, screenshotted light + dark |
| Reflection + week strip, Closure card ↵ Reflect, Settings toggle | done, screenshotted |
| Polish: light/dark fidelity, popover appearance, title wrapping, VoiceOver labels, frame autosave, ~150ms warm launch | done |

**Verified by Team Lead (screenshots, throwaway DB, both appearances):** outline, popover, capture, history, settings, closure card, reflection, focus, shortcuts sheet, momentum marks.
**Not verifiable here:** real keystroke/mouse paths for M4 additions (Find typing, Focus ⌘↵ transitions, reflection ← →), animation timing.
**Decisions:** D27–D32 (BOARD.md); Momentum key `showMomentum`, off by default.
**Screenshot harness:** `HUSH_DB_PATH=<tmp> HUSH_OPEN=outline,popover,... build/Hush.app/Contents/MacOS/Hush -appearance light|dark -showMomentum YES`.
