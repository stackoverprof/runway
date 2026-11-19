#!/usr/bin/env bash
# Build Runway Widget (menu bar app) and install it to /Applications.
# Usage: ./build-widget.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")"
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product RunwayWidget
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="dist/Runway Widget.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 1.0)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/RunwayWidget" "$APP/Contents/MacOS/RunwayWidget"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The fonts ship in SwiftPM's resource bundle, which Bundle.module finds in Resources.
[ -d "$BIN_DIR/Runway_RunwayWidget.bundle" ] && cp -R "$BIN_DIR/Runway_RunwayWidget.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Runway Widget</string>
  <key>CFBundleDisplayName</key><string>Runway Widget</string>
  <key>CFBundleIdentifier</key><string>com.runway.Widget</string>
  <key>CFBundleExecutable</key><string>RunwayWidget</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>RunwayStateFolder</key><string>RunwayWidget</string>
</dict></plist>
PLIST
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
pkill -x RunwayWidget 2>/dev/null || true
rm -rf "/Applications/Runway Widget.app"
cp -R "$APP" "/Applications/Runway Widget.app"
open "/Applications/Runway Widget.app"
echo "▸ Installed and launched /Applications/Runway Widget.app"
