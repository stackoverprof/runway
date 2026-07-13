#!/usr/bin/env bash
# Build a release app bundle and package it in a drag-to-install macOS disk image.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
ARCH="$(uname -m)"
OUTPUT="dist/Runway-${VERSION}-${ARCH}.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

./build-app.sh release
codesign --verify --deep --strict --verbose=2 dist/Runway.app

ditto dist/Runway.app "$STAGING/Runway.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$OUTPUT"
hdiutil create \
  -volname "Runway ${VERSION}" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -ov \
  "$OUTPUT"

echo "▸ Packaged $OUTPUT"
