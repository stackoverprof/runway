#!/usr/bin/env bash
# Build Runway and assemble a Runway.app bundle (no Xcode required).
# Usage: ./build-app.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Runway"
EXEC_NAME="Runway"

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="dist/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Runway" "$APP/Contents/MacOS/$EXEC_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM's resource bundle goes in Resources, where Bundle.module looks and
# where codesign accepts a nested bundle.
if [ -d "$BIN_DIR/Runway_Runway.bundle" ]; then
  rm -rf "$APP/Contents/Resources/Runway_Runway.bundle"
  cp -R "$BIN_DIR/Runway_Runway.bundle" "$APP/Contents/Resources/"
fi

# Bundle the libghostty GPU framework so the .app is self-contained (otherwise
# it only runs while .build exists). Add an rpath so the binary finds it.
if [ -d "$BIN_DIR/CGhosttyKitBinary.framework" ]; then
  cp -R "$BIN_DIR/CGhosttyKitBinary.framework" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/$EXEC_NAME" 2>/dev/null || true
  # Re-sign ad-hoc so the modified binary + bundled framework load cleanly.
  chmod -R u+w "$APP"
  xattr -cr "$APP" 2>/dev/null || true
  # Sign the nested framework first, then the app bundle to establish a valid nested signature
  codesign --force --sign - "$APP/Contents/Frameworks/CGhosttyKitBinary.framework"
  codesign --force --sign - "$APP"
fi

echo "▸ Built $APP"
echo "  Run it with:  open $APP"
