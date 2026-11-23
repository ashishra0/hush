#!/bin/bash
# Assembles build/Hush.app from the SwiftPM release binary. Idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."

SCRATCH=.build-frontend
swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/Hush"

APP=build/Hush.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Hush"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.hush.app</string>
  <key>CFBundleName</key><string>Hush</string>
  <key>CFBundleDisplayName</key><string>Hush</string>
  <key>CFBundleExecutable</key><string>Hush</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"
echo "Built $APP"
