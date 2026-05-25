#!/bin/bash
# build.sh — Builds a production SoundLock.app bundle in the project root.
# Run from anywhere: bash /path/to/build.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="SoundLock"
BUNDLE="$APP_NAME.app"
ICONSET_DIR="$APP_NAME.iconset"
MODULE_CACHE_ROOT="/private/tmp/soundlock-build-cache"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_ROOT/clang"
SWIFT_MODULECACHE_PATH="$MODULE_CACHE_ROOT/swift"
export CLANG_MODULE_CACHE_PATH
export SWIFT_MODULECACHE_PATH

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULECACHE_PATH"

if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cleanup() {
    rm -rf "$ICONSET_DIR" soundlock_1024.png
}
trap cleanup EXIT

SWIFTC_BIN="$(command -v swiftc)"
SWIFT_BIN="$(command -v swift)"

SOURCE_FILES=()
while IFS= read -r file; do
    SOURCE_FILES+=("$file")
done < <(find Sources -name '*.swift' | sort)

# ── 1. Generate icon (always regenerated so design changes take effect) ──
echo "==> Generating icon..."
rm -f AppIcon.icns
"$SWIFT_BIN" make_icon.swift

mkdir -p "$ICONSET_DIR"
for s in 16 32 128 256 512; do
    sips -z $s $s soundlock_1024.png \
        --out "$ICONSET_DIR/icon_${s}x${s}.png"            >/dev/null
    sips -z $((s*2)) $((s*2)) soundlock_1024.png \
        --out "$ICONSET_DIR/icon_${s}x${s}@2x.png"         >/dev/null
done
cp soundlock_1024.png "$ICONSET_DIR/icon_1024x1024.png"
iconutil -c icns "$ICONSET_DIR" -o AppIcon.icns
echo "==> AppIcon.icns ready"

# ── 2. Compile ──────────────────────────────────────────────────────────
echo "==> Compiling $APP_NAME..."
"$SWIFTC_BIN" "${SOURCE_FILES[@]}" \
    -framework Cocoa \
    -framework CoreAudio \
    -target arm64-apple-macosx13.0 \
    -O \
    -whole-module-optimization \
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
