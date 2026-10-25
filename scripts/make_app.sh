#!/usr/bin/env bash
# Wrap a built macspane binary in MacsPane.app: the bundle layout, its icon and its Info.plist.
# Signing is left to the caller (run.sh signs for development, release.sh for distribution).
#   scripts/make_app.sh <binary> <MacsPane.app> <version> <build>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$1"
APP="$2"
VERSION="$3"
BUILD="$4"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacsPane"
cp "$ROOT/App/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MacsPane</string>
  <key>CFBundleIdentifier</key><string>com.jgray.macspane</string>
  <key>CFBundleName</key><string>MacsPane</string>
  <key>CFBundleDisplayName</key><string>MacsPane</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 James Gray. Licensed under the GNU AGPL v3.</string>
</dict></plist>
PLIST
