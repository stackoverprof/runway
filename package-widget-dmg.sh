#!/usr/bin/env bash
# Build Runway Widget and package it in a drag-to-install macOS disk image.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
ARCH="$(uname -m)"
APP="dist/Runway Widget.app"
OUTPUT="dist/RunwayWidget-${VERSION}-${ARCH}.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

./build-widget.sh release
codesign --verify --deep --strict --verbose=2 "$APP"

ditto "$APP" "$STAGING/Runway Widget.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$OUTPUT"
hdiutil create -volname "Runway Widget ${VERSION}" -srcfolder "$STAGING" -format UDZO -ov "$OUTPUT"

echo "▸ Packaged $OUTPUT"
