#!/bin/bash
# Builds Midtrack.app (menu bar app) into dist/, the same shape as Konvolusi:
# an SPM release binary packaged into a bundle and ad-hoc signed.
#
#   ./build.sh            release build (default)
#   ./build.sh debug      debug build
set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-release}"
APP="dist/Midtrack.app"

# SwiftPM wraps manifest compilation in its own sandbox-exec, which a nested
# sandbox refuses. A plain Terminal build does not need this; set
# MIDTRACK_NO_SWIFT_SANDBOX=1 when building from inside another sandbox.
SANDBOX_FLAG=""
if [ "${MIDTRACK_NO_SWIFT_SANDBOX:-0}" = "1" ]; then
    SANDBOX_FLAG="--disable-sandbox"
fi

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product Midtrack $SANDBOX_FLAG

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path $SANDBOX_FLAG)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Midtrack" "$APP/Contents/MacOS/Midtrack"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp reader.js "$APP/Contents/Resources/reader.js"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Launcher"
# A stable path for a Login Item (System Settings › General › Login Items).
cat > Midtrack <<'LAUNCHER'
#!/bin/bash
# Launcher: the app lives in dist/Midtrack.app.
exec "$(cd "$(dirname "$0")" && pwd)/dist/Midtrack.app/Contents/MacOS/Midtrack" "$@"
LAUNCHER
chmod +x Midtrack

echo
echo "Built:"
echo "  $(pwd)/$APP"
echo
echo "Run:      open $APP        (or ./Midtrack)"
echo "Verify:   $APP/Contents/MacOS/Midtrack --check"
