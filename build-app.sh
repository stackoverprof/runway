#!/usr/bin/env bash
# Build Runway and assemble a Runway.app bundle (no Xcode required).
# Usage: ./build-app.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="dist/Runway.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Runway" "$APP/Contents/MacOS/Runway"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Bundle the libghostty GPU framework so the .app is self-contained (otherwise
# it only runs while .build exists). Add an rpath so the binary finds it.
if [ -d "$BIN_DIR/CGhosttyKitBinary.framework" ]; then
  cp -R "$BIN_DIR/CGhosttyKitBinary.framework" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/Runway" 2>/dev/null || true
  # Re-sign ad-hoc so the modified binary + bundled framework load cleanly.
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "▸ Built $APP"
echo "  Run it with:  open $APP"
