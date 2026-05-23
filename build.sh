#!/bin/bash
# build.sh — Compiles SoundLock and assembles an .app bundle
# Run from anywhere: bash /path/to/build.sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="SoundLock"
BUNDLE="$APP_NAME.app"
SOURCES=$(find Sources -name '*.swift' | tr '\n' ' ')

# ── 1. Generate icon (always regenerated so design changes take effect) ──
echo "==> Generating icon..."
rm -f AppIcon.icns
swift make_icon.swift

mkdir -p SoundLock.iconset
for s in 16 32 64 128 256 512; do
    sips -z $s $s soundlock_1024.png \
        --out "SoundLock.iconset/icon_${s}x${s}.png"       >/dev/null
    sips -z $((s*2)) $((s*2)) soundlock_1024.png \
        --out "SoundLock.iconset/icon_${s}x${s}@2x.png"    >/dev/null
done
iconutil -c icns SoundLock.iconset -o AppIcon.icns
rm -rf SoundLock.iconset soundlock_1024.png
echo "==> AppIcon.icns ready"

# ── 2. Compile ──────────────────────────────────────────────────────────
echo "==> Compiling $APP_NAME..."
swiftc $SOURCES \
    -framework Cocoa \
    -framework CoreAudio \
    -target arm64-apple-macosx13.0 \
    -O \
    -o "$APP_NAME"

# ── 3. Assemble bundle ─────────────────────────────────────────────────
echo "==> Assembling $BUNDLE..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$APP_NAME"       "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "Info.plist"      "$BUNDLE/Contents/Info.plist"
cp "AppIcon.icns"    "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "StatusIcon.png"  "$BUNDLE/Contents/Resources/StatusIcon.png"

rm "$APP_NAME"
rm -f "StatusIcon.png"

echo ""
echo "✅  Done!  open $BUNDLE"
echo ""
echo "Install:  cp -r $BUNDLE /Applications/"
