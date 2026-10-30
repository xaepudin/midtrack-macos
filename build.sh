#!/bin/bash
# Builds SongSeeker.app (menu bar app) into dist/, the same shape as the IRSVerb
# build: an SPM release binary packaged into a bundle and ad-hoc signed.
#
#   ./build.sh            release build (default)
#   ./build.sh debug      debug build
set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-release}"
APP="dist/SongSeeker.app"

# SwiftPM wraps manifest compilation in its own sandbox-exec, which a nested
# sandbox refuses. A plain Terminal build does not need this; set
# SONGSEEKER_NO_SWIFT_SANDBOX=1 when building from inside another sandbox.
SANDBOX_FLAG=""
if [ "${SONGSEEKER_NO_SWIFT_SANDBOX:-0}" = "1" ]; then
    SANDBOX_FLAG="--disable-sandbox"
fi

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product SongSeeker $SANDBOX_FLAG

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path $SANDBOX_FLAG)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SongSeeker" "$APP/Contents/MacOS/SongSeeker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp reader.js "$APP/Contents/Resources/reader.js"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Legacy launcher"
# The app used to be this exact path; keep it working so an existing Login Item
# (System Settings › General › Login Items) still starts the current build.
cat > SongSeeker <<'LAUNCHER'
#!/bin/bash
# Legacy launcher: the app now lives in dist/SongSeeker.app.
exec "$(cd "$(dirname "$0")" && pwd)/dist/SongSeeker.app/Contents/MacOS/SongSeeker" "$@"
LAUNCHER
chmod +x SongSeeker

echo
echo "Built:"
echo "  $(pwd)/$APP"
echo
echo "Run:      open $APP        (or ./SongSeeker)"
echo "Verify:   $APP/Contents/MacOS/SongSeeker --check"
