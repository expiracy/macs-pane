#!/bin/sh
# Regenerate App/AppIcon.icns and App/AppIcon.icon from the logo's drawing code
# (Sources/MacsPaneKit/Branding/MacsPaneLogo.swift). Run after changing the logo; commit the results.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$root/.build/icon"
rm -rf "$work" && mkdir -p "$work/AppIcon.iconset"
swift build --product macspane --package-path "$root"
"$(swift build --show-bin-path --package-path "$root")/macspane" --export-icon "$work"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$work/icon-1024-dark.png" --out "$work/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$work/icon-1024-dark.png" --out "$work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$work/AppIcon.iconset" -o "$root/App/AppIcon.icns"
cp "$work/marks-light.png" "$root/App/AppIcon.icon/Assets/marks-light.png"
cp "$work/marks-dark.png" "$root/App/AppIcon.icon/Assets/marks-dark.png"
echo "wrote $root/App/AppIcon.icns and App/AppIcon.icon"
