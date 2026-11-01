#!/bin/sh
# Builds dist/GameAnnouncer.app: a universal (Apple Silicon + Intel) release build of the
# GameAnnouncer target wrapped in an app bundle, with the icon rendered from AppIcon.swift.
#
# Usage: scripts/make-app.sh [--open | --zip]
#   --open  open the app when done
#   --zip   also write dist/GameAnnouncer-<version>.zip and its .sha256, for a release
set -eu
cd "$(dirname "$0")/.."

ARCHS="--arch arm64 --arch x86_64"
swift build -c release --product GameAnnouncer $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/GameAnnouncer"

APP=dist/GameAnnouncer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GameAnnouncer"
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

# Ad-hoc signature: seals the bundle, but isn't a Developer ID signature, so downloaded
# copies still need "Open Anyway" until releases are notarized.
codesign --force --sign - "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/GameAnnouncer"))"

case "${1:-}" in
--open)
    open "$APP"
    ;;
--zip)
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
    ZIP="dist/GameAnnouncer-$VERSION.zip"
    rm -f "$ZIP" "$ZIP.sha256"
    # ditto keeps the bundle's symlinks, permissions and signature intact; plain zip doesn't.
    ditto -c -k --keepParent "$APP" "$ZIP"
    (cd dist && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
    echo "Wrote $ZIP"
    cat "$ZIP.sha256"
    ;;
esac
