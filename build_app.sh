#!/bin/bash
# Builds a universal (Apple Silicon + Intel) release binary and packages it
# as ScreenClip.app so macOS treats it as a normal app (stable identity for
# TCC permissions, works on both Mac architectures).
#
# Usage:
#   ./build_app.sh            build ScreenClip.app in this folder
#   ./build_app.sh --install  also copy it into /Applications
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ScreenClip"
APP_DIR="${APP_NAME}.app"
BIN_NAME="ScreenClip"

# Both --arch builds report the same --show-bin-path, so the second one
# overwrites the first: each slice is copied out right after its own build
# rather than read from a fixed path afterwards. The previous hard-coded
# .build/<triple>/release/ paths silently went stale when the toolchain
# changed its output layout, and lipo happily packaged months-old binaries
# with no error at all — hence the explicit existence check below.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

for arch in arm64 x86_64; do
    swift build -c release --arch "$arch"
    BIN_PATH="$(swift build -c release --arch "$arch" --show-bin-path)/${BIN_NAME}"
    if [ ! -x "$BIN_PATH" ]; then
        echo "error: ${arch} のビルド結果が見つかりません: ${BIN_PATH}" >&2
        exit 1
    fi
    cp "$BIN_PATH" "$STAGE/$arch"
done

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

lipo -create -output "$APP_DIR/Contents/MacOS/${APP_NAME}" "$STAGE/arm64" "$STAGE/x86_64"

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.screenclip</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

# Ad-hoc sign the whole bundle (not just the linker's default signature on
# the binary alone) so Info.plist/Resources are sealed together under one
# identity — this keeps TCC permission grants (Screen Recording) stable
# across rebuilds and avoids "damaged app" errors on other Macs. It does
# NOT satisfy Gatekeeper on another machine (that needs a paid Developer ID
# + notarization) — see the printed note below.
codesign --force --deep --sign - "$APP_DIR"

# Force Launch Services / the Dock to pick up the new icon instead of a
# stale cached one from a previous build at this same path.
touch "$APP_DIR"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$(pwd)/$APP_DIR" >/dev/null 2>&1 || true

echo "Built ${APP_DIR} ($(lipo -archs "$APP_DIR/Contents/MacOS/${APP_NAME}"))."

if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/${APP_DIR}"
    cp -R "$APP_DIR" "/Applications/${APP_DIR}"
    /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "/Applications/${APP_DIR}" >/dev/null 2>&1 || true
    echo "Installed to /Applications/${APP_DIR}."
else
    echo "Move it to /Applications and open it (or double-click) to launch, or re-run with --install."
fi

echo ""
echo "Note: this build is only ad-hoc signed (no Apple Developer ID / notarization)."
echo "On another Mac, Gatekeeper will block it the first time — right-click the app"
echo "and choose Open, or allow it via System Settings > Privacy & Security."
