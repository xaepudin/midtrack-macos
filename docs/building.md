# Building and testing

## Requirements

- macOS 15 or later
- Xcode command line tools with Swift 6 tooling
- No third-party Swift packages and no network access for the build

## Build

```bash
./build.sh                 # release build
./build.sh debug           # debug build
```

`build.sh` runs SwiftPM, assembles `dist/Midtrack.app`, copies
`Resources/Info.plist`, `reader.js`, and `AppIcon.icns`, then ad-hoc signs the
bundle. It also writes a `Midtrack` launcher at the repository root for Login
Items.

```bash
open dist/Midtrack.app
# or a Login Item can point at ./Midtrack
```

### Nested sandbox

SwiftPM wraps manifest compilation in its own `sandbox-exec`, which a nested
sandbox refuses. From a normal Terminal this is not needed. From inside another
sandbox:

```bash
MIDTRACK_NO_SWIFT_SANDBOX=1 ./build.sh
```

## Tests

```bash
swift test --disable-sandbox
```

The suite is 48 tests in `Tests/MidtrackKitTests`. It does not start the reader,
does not call MediaRemote, and writes to a throwaway UserDefaults domain.

## Bundle layout

```
dist/Midtrack.app/
  Contents/Info.plist
  Contents/MacOS/Midtrack
  Contents/Resources/AppIcon.icns
  Contents/Resources/reader.js
  Contents/_CodeSignature/…
```

`LSUIElement` is true. The app switches to a regular activation policy while the
main window is open and back to accessory when it closes.

## Command line

The app binary has development modes that run before the UI starts.

```bash
# self-check: bundle, reader, seek symbol, rule, and one live snapshot
dist/Midtrack.app/Contents/MacOS/Midtrack --check

# render the main window off-screen
dist/Midtrack.app/Contents/MacOS/Midtrack --render-window window.png
dist/Midtrack.app/Contents/MacOS/Midtrack --render-window players.png --tab players
dist/Midtrack.app/Contents/MacOS/Midtrack --render-window settings.png --tab settings

# render the menu bar panel
dist/Midtrack.app/Contents/MacOS/Midtrack --render-panel panel.png
dist/Midtrack.app/Contents/MacOS/Midtrack --render-panel squeezed.png --height 600

# first-run sheet and monochrome menu bar mark
dist/Midtrack.app/Contents/MacOS/Midtrack --render-onboarding welcome.png
dist/Midtrack.app/Contents/MacOS/Midtrack --render-menubar-icon glyph.png

# pin appearance for documentation
dist/Midtrack.app/Contents/MacOS/Midtrack --render-window dark.png --appearance dark
```

`--tab` accepts `control`, `players`, `diagnostics`, `settings`, and `about`.
`--appearance` accepts `dark` and `light`. `--height` squeezes the panel on
purpose; a `MenuBarExtra` window is capped in height.

The render modes use a real off-screen window and `cacheDisplay`, so AppKit
draws switches, pickers, and the custom range slider. The off-screen window does
not inherit the menu bar material, so some accents may look muted; `--check` is
the source of truth for values.

## App icon

`Resources/AppIcon.icns` is generated:

```bash
python3 scripts/make-icon.py
```

The script uses Pillow, draws at 4x, writes an `.iconset` under `build/`, and
calls `iconutil`. The menu bar mark is drawn in code in
`Sources/Midtrack/MenuBarIcon.swift` as a template image.

## Release packaging

```bash
MIDTRACK_NO_SWIFT_SANDBOX=1 ./scripts/package.sh
```

This rebuilds the app, verifies the signature, and writes a ZIP, a DMG with an
Applications symlink, and `SHA256SUMS.txt` under `dist/release/`. The tag
workflow uses the same script — see [release.md](release.md).
