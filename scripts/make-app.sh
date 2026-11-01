#!/bin/sh
# Builds dist/GameDay.app: a release build of the GameDay target wrapped in an app bundle,
# with the icon rendered from AppIcon.swift. Usage: scripts/make-app.sh [--open]
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product GameDay
BIN="$(swift build -c release --show-bin-path)/GameDay"

APP=dist/GameDay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GameDay"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Every size macOS asks for, downscaled from one 1024px render.
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
"$BIN" --render-icon "$WORK/icon-1024.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$WORK"

# Ad-hoc signature so Gatekeeper treats it as one sealed app on this Mac.
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--open" ]; then
    open "$APP"
fi
