# Hush — Design spec (extracted from approved Paper file "Hush · macOS todo")

Paper: https://app.paper.design/file/01M83J35KQPWJ5XVX6SMJY3ARN
Approved direction: **A · Overcast** (Panic-inspired: gray ground, white surfaces, 1px hairlines instead of shadows, single electric-blue accent).
Pages: 1 Directions · 2 Foundations · 3 Screens (A1–A3 capture, B1 outline, C1 menu bar, D1 settings) · 4 Keyboard spec · 5 Vanishing List · 6 Daily Closure + History · 7 Focus (exploration) · 8 Closure spec + MVP scope.

## Tokens
> **2026-11-23 — design system switched to Vercel Geist** (user request). Code (`Theme.swift`) is the source of truth:
> background-100 #FFF/#0A0A0A (surface) · background-200 #FAFAFA/#000 (ground, popover) · gray-100 #F2F2F2/#1A1A1A (selected row, keycaps) · hover #FAFAFA/#111 · border #EBEBEB/#2E2E2E · text gray-1000 #171717/#EDEDED · secondary gray-900 #666/#A1A1A1 · faint #A1A1A1/#6E6E6E · accent blue-700 #0070F3 (caret, focus, drop line, completion fill only — never selection, never nesting guides).
> Type: Geist Sans / Geist Mono (bundled, OFL, `Resources/Fonts`); rows copy-14; headings semibold (no light weights); radius row 6, popover/modal 12. The Overcast table below is historical.

| Token | Light | Dark |
|---|---|---|
| ground (window bg behind outline / desktop-ish) | #EBEBEB | #0B0B0C |
| surface (modal, popover, outline window) | #FFFFFF | #1A1A1C |
| surface-sunk (hover row, keycap fill) | #F5F5F6 | #232326 |
| hairline (1px borders, dividers) | #DCDCDF | #2E2E32 |
| ink | #1C1C1E | #F2F2F3 |
| ink-mute | #6E6E73 | #8E8E93 |
| ink-faint (placeholder, done, counts) | #A1A1A6 | #5A5A5F |
| accent — ONLY caret, focus ring, selection, drop line, completion fill | #0852FF | #3D7BFF |
| accent-wash (selected row bg) | #E8EEFF | #14224A |

Type: **SF Pro** (system font). Mono: **Geist Mono** is not bundled → use `.monospaced` system font (SF Mono) for keycaps.
- capture input 24/30, weight light (~274 → `.light`), tracking −2%
- outline title 36 light; display 56 light
- row 15/22 regular · body 14/20 · caption 12/16 · keycap mono 11
Spacing 4pt grid. Row height **32**, indent **24** per level, row h-padding 8, slot order: [chevron 16][circle 16][text flex][trailing].
Radius: keycap 4, row 6, popover 10, modal/window 14, checkbox full.
Elevation: hairline + one soft shadow, floating surfaces only. Modal shadow `0 32 64 -16 rgba(0,0,0,.28)`.

## Screens
**A · Quick Capture** (NSPanel, 640w, top ≈ 23% of screen height, centered). Input row padding 24, placeholder "What's on your mind?". Footer (hairline top, 10px v-pad): left "📁 Inbox" (destination, ink-mute 12) — right hints `⇥ Details`, `↵ Save`. Tab expands Details: Note (14, multi-line) + "Under [Parent › Path]" picker; in details ⌘↵ saves, ⇧⇥ back to title. Typing `/name` in title files under matching existing parent (autocomplete). On save: modal morphs into pill "✓ Saved to **Inbox**  ⌘Z" (blue check circle, 180ms), holds 900ms, fades 150ms; previous app regains focus immediately. Esc dismisses; draft kept 60s. ⌥↵ save & keep open.
**B · Outline window** (~1040×780, toolbar 52h: traffic lights, breadcrumb `Home / Work`, Find field ⌘F). Content column 720w centered, title (36 light) + right meta "7 open". Rows per tokens; collapsed parent shows open-child count (ink-faint 12) on the right. Nesting guide: 1px hairline vertical line through parent chevron center; branch containing the selection draws the guide in accent. Selected row: accent-wash bg + circle stroke accent. Hover: surface-sunk bg + drag handle (6-dot) at right. Editing: accent caret. Bottom hint bar (44h, hairline top): ⇥ Indent · ⇧⇥ Outdent · ⌘↵ Complete · ⌘. Collapse · ⌥⌘↑↓ Move · ⌘] Zoom in · ⌘/ All shortcuts. Drag: lifted row (white, hairline, shadow), drop line 2px accent with 6px ring at left, ghost at origin 35% opacity.
**C · Menu bar popover** (320w, r10): capture trigger field "Capture a task… ⌘⇧Space", RECENT label + "5 of 12 open", 5 recent rows (30h, 14px circle, 13pt text, relative time right), footer: Open outline ⌘O · Settings… ⌘, · Quit Hush ⌘Q. Menu bar icon: 14px circle outline with center dot (template image).
**D · Settings** (560w): Capture shortcut (recorder, ✕ to reset) · Launch at login (switch) · Appearance System/Light/Dark (3 preview tiles) · "Your tasks live on this Mac" + path + Show in Finder. Changes apply instantly.

## Completion — "Strike & Fold" (approved)
Trigger ⌘↵ or click circle. 0–90ms circle fills accent + scale 1→1.12→1 (spring); 30–150ms strike draws L→R 1.5px ink; 90–160ms text+circle → ink-faint; 160–280ms row height 32→0, opacity→0, x+6px, ease-in-out; siblings reflow driven by the fold; selection moves to next sibling (or previous / parent). Parent with children: children strike top→bottom +40ms stagger, then branch folds. Rapid ⌘↵ queues without waiting. **Reduce Motion**: fill + full strike instantly, hold 400ms, 120ms opacity fade, reflow in one frame.
Undo toast: ink pill bottom-center "Done · <title>  ⌘Z Undo", rise 8px/160ms, holds 4s (paused on hover), next completion replaces it. Completed tasks leave the outline; they live only in History.
Empty: when a zoomed node/root has 0 open → "All clear." (32 light) + check icon + "Nothing in Work is waiting on you. Enjoy it, or press ↵ to add the next thing." fades in +400ms.

## History (⌘Y)
Window/route "Home / History", title "Finished", meta "Kept forever, on this Mac". Grouped by local day (day boundary **04:00**). Header "Today" / weekday / "Friday 20 November" + right "8 finished" or "A quiet day" / "A quiet weekend" for empty spans. Row: faint filled check, title in ink-mute (NOT struck), parent path (ink-faint 12), time (mono 11). Hover: Restore button (⌘R) restores to original parent at end (or root if parent gone).

## Daily Closure card (⌘D, P2) — 340w popover
Date label (mono caps 10) · headline (28 light) · "N things finished today." · N marks (3×14 ink bars, cap 8) · 3 latest titles + "and N more" · italic closing line · footer ↵ Reflect, ⌘Y History.
Copy by count: ≥6 "A good day's work." / "The rest can wait until tomorrow." · 2–5 "Steady progress." / "Every one of these counts." · 1 "One thing, done." / "Sometimes one is the right number." · 0 "A quiet day." / "Not every day is for crossing things off." · list empty "All clear." / "Nothing is waiting on you. Enjoy it."
NEVER: percentages, streaks, goals, comparisons, notifications, sounds, confetti.

## Keyboard (global)
⌘⇧Space capture (rebindable). Outline: ↑↓ select · ↵ new sibling below (in edit: split at caret) · ⇥/⇧⇥ indent/outdent · ⌘↵ complete · ⌘./⌘→ collapse/expand · ⌥⌘↑↓ reorder within siblings · ⌘]/⌘[ zoom in/out · Space/typing edit, Esc stop editing · ⌘⌫ delete (undoable) · ⌘Z/⇧⌘Z · ⌘F find · ⌘Y history · ⌘D today.

---
# Post-MVP (M4) — from Paper pages 5–8

## Quiet Momentum (Settings toggle "Show today's progress in the toolbar", default OFF)
Outline toolbar, right of Find: marks + "N today" (12 ink-mute). Marks = 3×11 rounded bars, 3px gap, ink-mute, cap 8 (count text keeps going). New mark on completion: scaleY 0→1 at +90ms of Strike & Fold, accent → ink-mute over 600ms. Click (or ⌘D) opens the Daily Closure card anchored to the marks. Hidden when 0.

## Find (⌘F) — outline toolbar field (200w, 26h, surface-sunk, r6, magnifier, "Find", ⌘F hint)
Typing filters the outline to matching open tasks (case-insensitive substring) shown with their ancestors (ancestors ink-faint, matches ink, match substring bold). ↑↓ moves among matches, ↵ jumps: clears find, reveals (expands ancestors) and selects the task. Esc clears and returns focus to the outline. Empty result: "No open tasks match “q”." in ink-faint. History window keeps its own find field ("Find finished") with the same behavior over history rows.

## Full-screen reflection (↵ on Daily Closure card = "Reflect")
Borderless window filling the active screen, dk-ground #0B0B0C regardless of appearance (it's an evening ritual). Centered 640w column:
- mono caps 11 "MONDAY · 23 NOVEMBER · 6:42 PM" (dk-ink-faint)
- headline 64 light, −2.5%, dk-ink (ClosureCopy headline)
- "N things finished today." 18 dk-ink-mute
- Two-column list of today's finished tasks: time (mono 11 dk-ink-faint, 40w) + title (14 #C7C7CC). Max 12, then "and N more".
- closing line italic 20 dk-ink
- hairline (#1F1F22) then "THIS WEEK" mono caps 10 + week strip: 7 columns (previous 6 days + Today), each a vertical stack of 4px dots (3px gap, one per finished task, cap 12) above a 12pt day label; past days #5A5A5F, Today dots+label #F2F2F3 semibold "Today"; zero days show only the label. Caption 12 #5A5A5F "One dot per finished task. Rest days are just quiet."
- Bottom hints (absolute, 50px from bottom): esc Back to list · ⌘Y History · ← → Other days.
← / → browse previous/next days (not beyond today); headline/count/list/date update for that day ("A quiet day." copy when 0). Transition: card headline grows 28→64 as window cross-dissolves in 320ms; Reduce Motion = 150ms fade. Esc closes.

## Focus Mode (⌘⇧F on a selected row, or from the row's context)
The outline window content switches to focus (same window). Toolbar shows only dimmed traffic lights + centered mono caps "FOCUS". Ghost outline rows above/below at 10% opacity. Centered 640w: breadcrumb (12 ink-faint "Work › Launch v1.2 › Release notes"), row: 28px circle (2px accent stroke) + title 44 light −2.5% ink, note below (15/23 ink-mute, indented 48). Bottom "Up next  <title>" (12, faint+mute). Hint bar: ⌘↵ Done, show next · ↓ Skip for now · esc Back to outline.
"Next" = next open task in outline pre-order after the focused one, starting where you entered (skipping Inbox node itself; wraps no). Complete: circle fills accent + strike (160ms) → task lifts −24px & fades while next rises +24px & fades in (200ms, 80ms overlap). Nothing left: "That's everything." (24 light) + "N finished in this focus session" (12 ink-faint) — the only place a session count appears. Esc (or ⌘⇧F) exits to the outline with the last focused/next task selected. Reduce Motion: crossfade only.

## Shortcuts sheet (⌘/ in the outline)
Sheet over the outline window (480w, r14, surface, hairline): title "Keyboard" (20 semibold) and grouped two-column rows (keycap ⇢ action): Capture · Outline · Views (⌘F Find, ⌘Y History, ⌘D Today, ⌘⇧F Focus, ⌘/ This sheet). Esc closes. Re-add "⌘/ All shortcuts" to the outline hint bar.

## Polish bar (applies everywhere)
- Light AND dark verified against tokens; no hard-coded colors outside Theme.
- Every window: correct min sizes, remembers frame (setFrameAutosaveName), Esc behavior consistent, ⌘W closes, focus ring/selection always visible.
- VoiceOver labels on circles ("Complete <title>"), rows ("<title>, level N, N open inside, collapsed"), toolbar marks ("N finished today").
- Text never clips: long titles truncate with … in popover/history, wrap in outline (row grows in 22pt steps).
- No layout jumps on launch; app launches < 300ms to menu bar.
