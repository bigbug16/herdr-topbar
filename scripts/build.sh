#!/bin/bash
# Build HerdrBar.app and install it to ~/Applications.
#
# Invoked by the plugin's [[build]] step on `herdr plugin install`. Note that
# `herdr plugin link` does NOT run build steps, so during local development this
# has to be run by hand after editing any Swift source.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
APP_NAME="HerdrBar"
BUNDLE_ID="dev.herdr.topbar"
VERSION="0.1.0"
DEST="${HERDR_TOPBAR_DEST:-$HOME/Applications/$APP_NAME.app}"

# This path is later handed to `rm -rf`, and it can be overridden from the
# environment, so refuse anything that is not an app bundle. Without this a
# stray HERDR_TOPBAR_DEST (say, $HOME) would delete the wrong tree outright.
case "$DEST" in
    *.app) ;;
    *)
        echo "Refusing to build: HERDR_TOPBAR_DEST must end in .app (got '$DEST')" >&2
        exit 1
        ;;
esac
if [ "${DEST%.app}" = "" ] || [ "$DEST" = "/.app" ]; then
    echo "Refusing to build: HERDR_TOPBAR_DEST is not a valid destination" >&2
    exit 1
fi

MIN_MACOS="13.0"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos${MIN_MACOS}"

echo "==> Building $APP_NAME ($TARGET)"
rm -rf "$BUILD"
mkdir -p "$BUILD"

# Swift 5 language mode: the app is single-threaded AppKit code and does not
# need (or satisfy) Swift 6 strict concurrency checking.
COMMON_FLAGS=(-O -swift-version 5 -target "$TARGET")

swiftc "${COMMON_FLAGS[@]}" \
    -framework AppKit \
    "$ROOT/Sources/Shared/UnixSocket.swift" \
    "$ROOT"/Sources/HerdrBar/*.swift \
    -o "$BUILD/$APP_NAME"

swiftc "${COMMON_FLAGS[@]}" \
    "$ROOT/Sources/Shared/UnixSocket.swift" \
    "$ROOT"/Sources/herdrbar-open/*.swift \
    -o "$BUILD/herdrbar-open"

echo "==> Assembling bundle"
STAGE="$BUILD/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BUILD/$APP_NAME" "$STAGE/Contents/MacOS/$APP_NAME"
cp "$BUILD/herdrbar-open" "$STAGE/Contents/MacOS/herdrbar-open"
cp "$ROOT/scripts/install-finder.sh" "$STAGE/Contents/Resources/install-finder.sh"

# Menu bar artwork, generated from Resources/ram.svg by scripts/make-icon.sh.
if [ ! -f "$ROOT/Resources/ram.pdf" ]; then
    echo "Resources/ram.pdf is missing — run scripts/make-icon.sh" >&2
    exit 1
fi
cp "$ROOT/Resources/ram.pdf" "$STAGE/Contents/Resources/ram.pdf"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <!-- Menu bar only: no Dock tile, no application menu. -->
    <key>LSUIElement</key><true/>
    <!-- Puts HerdrBar in Finder's "Open With" for folders and for any file.
         Rank Alternate keeps it from ever becoming a default handler. -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Folder</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.folder</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>File</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.item</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc signature. Unsigned bundles get killed on launch on Apple silicon.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$STAGE" >/dev/null 2>&1 \
    || codesign --force --sign - "$STAGE"

echo "==> Installing to $DEST"
WAS_RUNNING=0
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    WAS_RUNNING=1
    # Replacing a running bundle leaves the old code mapped; stop it first.
    pkill -x "$APP_NAME" || true
    sleep 1
fi

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -R "$STAGE" "$DEST"

# Refresh LaunchServices so the Open With entry appears without a relogin.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$DEST" >/dev/null 2>&1 || true

if [ "$WAS_RUNNING" -eq 1 ]; then
    echo "==> Relaunching"
    open -g "$DEST"
fi

echo "Built $DEST"
