#!/usr/bin/env bash
# Build MacsPane with SwiftPM, wrap it in a small .app bundle, sign it, and open it.
#
# Accessibility is granted to a signed identity. An ad-hoc signature changes on every build, so macOS
# forgets the grant each time; set MACSPANE_SIGN_IDENTITY to a code-signing identity in your keychain
# (a self-signed one is fine) to keep it across rebuilds.
#   scripts/run.sh            build, quit any running copy, open the new one
#   scripts/run.sh --build    build and bundle only
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build --product macspane
BIN="$(swift build --show-bin-path)/macspane"

APP="$ROOT/.build/MacsPane.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacsPane"
cp "$ROOT/App/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MacsPane</string>
  <key>CFBundleIdentifier</key><string>com.jgray.macspane</string>
  <key>CFBundleName</key><string>MacsPane</string>
  <key>CFBundleDisplayName</key><string>MacsPane</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

/usr/bin/codesign --force --sign "${MACSPANE_SIGN_IDENTITY:--}" --timestamp=none "$APP"

[[ "${1:-}" == "--build" ]] && { echo "$APP"; exit 0; }
pkill -x MacsPane 2>/dev/null || true
sleep 0.5
open "$APP"
echo "MacsPane running from $APP"
