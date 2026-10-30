#!/bin/bash
# Builds the release assets into dist/release/:
#
#   Midtrack-<version>-macos.zip
#   Midtrack-<version>.dmg
#   SHA256SUMS.txt
#
# Uses the same ad-hoc signed bundle as ./build.sh. Run from a normal Terminal,
# or set MIDTRACK_NO_SWIFT_SANDBOX=1 inside another sandbox.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Midtrack.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
RELEASE_DIR="dist/release"
ZIP_NAME="Midtrack-${VERSION}-macos.zip"
DMG_NAME="Midtrack-${VERSION}.dmg"

echo "==> Building Midtrack ${VERSION}"
./build.sh

echo "==> Verifying bundle"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "==> Creating ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_DIR/$ZIP_NAME"

echo "==> Creating DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Midtrack.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
    -volname "Midtrack ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$RELEASE_DIR/$DMG_NAME" >/dev/null

echo "==> Writing checksums"
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > SHA256SUMS.txt
)

echo
echo "Release assets:"
ls -lh "$RELEASE_DIR"
