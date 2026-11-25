# Contributing

Thanks for helping. Hush is deliberately small: a fix or polish is more welcome than a new feature. For anything bigger than a bug fix, open an issue first so we can agree it fits.

## Setup
macOS 14+, Swift 6 (Command Line Tools or Xcode). No other tools are needed.

```sh
swift build && swift test
scripts/bundle.sh && open build/Hush.app
```

## Layout
```
Sources/HushCore/   models + SQLite persistence (GRDB). No UI imports.
Sources/Hush/       the menu bar app (SwiftUI + AppKit). No SQL.
Tests/HushCoreTests Swift Testing suite for HushCore
Resources/Fonts/    Geist Sans / Mono (OFL), copied into the .app by scripts/bundle.sh
scripts/            bundle.sh (build the .app), screenshots.sh (UI screenshots)
docs/               architecture, HushCore API, design tokens and specs
```

## Trying UI changes safely
Debug hooks let you run against a throwaway database and open any window directly:

```sh
HUSH_DB_PATH=/tmp/hush-dev.sqlite HUSH_OPEN=outline,popover \
  build/Hush.app/Contents/MacOS/Hush -appearance dark -showMomentum YES
```
`HUSH_OPEN` accepts `outline, settings, history, closure, capture, popover, reflection, focus, shortcuts`.
`scripts/screenshots.sh light /tmp/shots outline` seeds sample tasks and captures the windows; attach light and dark screenshots to UI pull requests.

## Pull requests
- `swift build` with no new warnings, `swift test` green.
- New HushCore behavior comes with a test; update [docs/CORE-API.md](docs/CORE-API.md) if the public API changes.
- UI uses tokens from `Theme.swift` only (see [docs/DESIGN.md](docs/DESIGN.md)); check light and dark, keyboard access and Reduce Motion.
- Keep it quiet: no sounds, badges, streaks or notifications.
