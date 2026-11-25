# Architecture

Hush is a local-first macOS menu bar app. No network, no accounts, no analytics.

## Modules (SwiftPM)
| Target | What | May import | Must not |
|---|---|---|---|
| `HushCore` (library) | Models, persistence, undo, day/week summaries | Foundation, GRDB | AppKit, SwiftUI |
| `Hush` (executable) | Menu bar item, windows, panels, keyboard | SwiftUI, AppKit, Carbon, HushCore | SQL, GRDB, task file I/O |
| `HushCoreTests` | Swift Testing suite for HushCore | Testing, HushCore | — |

The app reaches persistence only through the public API in [CORE-API.md](CORE-API.md).

## Building without Xcode
The project builds with the Command Line Tools alone (Swift 6, macOS 15 SDK): `swift build`, `swift test`.
`scripts/bundle.sh` assembles `build/Hush.app` from the release binary: Info.plist (`LSUIElement`), the
Geist fonts (`ATSApplicationFontsPath`), and an ad-hoc signature. There are no asset catalogs or storyboards.

## Decisions
1. **GRDB + SQLite**, one `DatabaseQueue` at `~/Library/Application Support/Hush/hush.sqlite`, migrations via `DatabaseMigrator`, in-memory DB for tests. Soft delete; sibling positions renumbered in one transaction.
2. **Observation**: HushCore exposes `ValueObservation`-backed callbacks on the main queue; the app holds `@Observable` view models that subscribe.
3. **Global hotkey: Carbon `RegisterEventHotKey`**, in-house (~60 lines) rather than a package: SwiftPM resource bundles don't load in a hand-assembled .app, and there is only one rebindable shortcut (stored in UserDefaults).
4. **Quick Capture** is an `NSPanel` with `.nonactivatingPanel`. It never calls `NSApp.activate()`: activating would raise every Hush window. The previously frontmost app is re-activated on dismiss.
5. **Menu bar popover** likewise opens without activating the app.
6. **Outline window**: a regular `NSWindow` hosting SwiftUI; keyboard via local event monitors. No third-party outline libraries.
7. **Launch at login**: `SMAppService.mainApp` (works only from the bundled .app).
8. **Day boundary** is 04:00 local time, DST-safe via `Calendar`.

## Quality bar
`swift build` without warnings in our code, `swift test` green, everything reachable by keyboard, Reduce Motion respected, light and dark checked against the tokens in [DESIGN.md](DESIGN.md).
