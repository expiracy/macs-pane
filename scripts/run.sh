#!/usr/bin/env bash
# Build MacsPane with SwiftPM, wrap it in a small .app bundle, sign it, and open it.
#
# Accessibility remembers a grant against the app's designated requirement. An ad-hoc signature's
# default requirement is that one build's hash, so every rebuild would need granting again; the
# ad-hoc signature here instead requires only the bundle identifier, which every build shares, so
# one grant lasts across rebuilds. Set MACSPANE_SIGN_IDENTITY to a code-signing identity in your
# keychain to sign with that instead.
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
"$ROOT/scripts/make_app.sh" "$BIN" "$APP" "$(tr -d '[:space:]' < "$ROOT/VERSION")" "$(git -C "$ROOT" rev-list --count HEAD)"

if [[ -n "${MACSPANE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --sign "$MACSPANE_SIGN_IDENTITY" --timestamp=none "$APP"
else
  /usr/bin/codesign --force --sign - --timestamp=none \
    -r='designated => identifier "com.jgray.macspane"' "$APP"
fi

[[ "${1:-}" == "--build" ]] && { echo "$APP"; exit 0; }
pkill -x MacsPane 2>/dev/null || true
sleep 0.5
open "$APP"
echo "MacsPane running from $APP"
