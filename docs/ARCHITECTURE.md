# Hush — Architecture & ownership (Team Lead)

Smallest excellent native macOS todo app. Local-first, offline-only, menu bar app.

## Toolchain constraint
Only Command Line Tools are installed (Swift 6.1.2, macOS 15 SDK) — **no Xcode, no xcodebuild**.
- Build: `swift build` / `swift test` (Swift Testing `import Testing` works; verified).
- App bundle: `scripts/bundle.sh` assembles `build/Hush.app` from the SwiftPM release binary
  (Info.plist with `LSUIElement=YES`, ad-hoc `codesign -s -`). No asset catalogs, no storyboards.

## Modules (SwiftPM)
| Target | Owner | May import | Must not |
|---|---|---|---|
| `HushCore` (library) | Backend | Foundation, GRDB | AppKit, SwiftUI, Combine-UI glue |
| `Hush` (executable) | Frontend | SwiftUI, AppKit, Carbon, HushCore | SQL, GRDB, file I/O for tasks |
| `HushCoreTests` | Backend | Testing, HushCore | — |

Frontend talks to persistence **only** through the public API in `docs/CONTRACTS.md`.

## Decisions (ADR-lite)
1. **GRDB + SQLite**, single `DatabaseQueue` at `~/Library/Application Support/Hush/hush.sqlite`. Migrations via `DatabaseMigrator`. In-memory DB for tests.
2. **Observation**: Core exposes an `@Observable`-free API; frontend observes via a `ValueObservation`-backed `AsyncStream`/callback provided by Core (Core may use GRDB's `ValueObservation`). Frontend holds an `@Observable` view model that subscribes.
3. **Global hotkey: Carbon `RegisterEventHotKey`, in-house (~60 lines). Not the KeyboardShortcuts package.** Reason: SwiftPM resource bundles (`Bundle.module`) don't work in a hand-assembled, codesigned .app without Xcode; and we need only one rebindable shortcut. Rebinding stored in UserDefaults as (keyCode, modifiers).
4. **Quick Capture window**: `NSPanel` subclass, `.nonactivatingPanel` + `.titled`-less, `canBecomeKey = true`, floating level, hosts SwiftUI via `NSHostingView`. Focus return = record `NSWorkspace.shared.frontmostApplication` before showing, `activate()` it after dismiss.
5. **Outline window**: regular `NSWindow` hosting SwiftUI. Keyboard handling via `NSEvent.addLocalMonitorForEvents` / `onKeyPress` — whichever is reliable; no third-party outline libs.
6. **Launch at login**: `SMAppService.mainApp` (works only from a bundled .app).
7. No DI frameworks, no networking, no analytics, no sounds.

## Ownership & files
- `docs/BOARD.md` — PM (backlog, priorities, acceptance criteria, status per task). Others append Q&A under "Open questions".
- `docs/CONTRACTS.md` — Backend (public types & functions). Frontend requests changes in "Requests" section.
- `docs/DESIGN.md` — design spec extracted from Paper (Team Lead). Source of truth for UI.
- `docs/STATUS.md` — Team Lead.
- `Package.swift` — Team Lead only. Ask before adding dependencies.

## Quality gates
`swift build` clean (no warnings in our code), `swift test` green, acceptance criteria met, keyboard accessible, Reduce Motion respected, light/dark via system colors/tokens.
