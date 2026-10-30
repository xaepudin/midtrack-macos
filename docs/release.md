# Release pipeline

Midtrack releases are built on a GitHub-hosted macOS runner and published from a
version tag.

## Versioning

Two values in `Resources/Info.plist` define a release:

- `CFBundleShortVersionString` — marketing version, for example `1.0.0`.
- `CFBundleVersion` — build number, increment for every upload.

Update both, add a `CHANGELOG.md` entry, and merge to `main` before tagging.

## Tag a release

```bash
git tag -a v1.0.0 -m "Midtrack 1.0.0"
git push origin v1.0.0
```

The tag **must** match the marketing version: `v1.0.0` is checked against
`CFBundleShortVersionString` in the workflow. A mismatch fails the job before
anything is published.

## What the workflow does

`.github/workflows/release.yml` runs on `macos-15` for `v*` tags:

1. Checks out the tag.
2. Verifies the tag matches `CFBundleShortVersionString`.
3. Runs `swift test --disable-sandbox`.
4. Runs `scripts/package.sh`, which builds and verifies the app, then writes:
   - `Midtrack-<version>-macos.zip`,
   - `Midtrack-<version>.dmg` (with an Applications symlink),
   - `SHA256SUMS.txt`.
5. Creates a GitHub release with generated notes and uploads those files.

The workflow needs `contents: write`; it uses the repository `GITHUB_TOKEN` and
the `softprops/action-gh-release` action.

`.github/workflows/ci.yml` runs the same tests and a local bundle build on pushes
to `main`/`midtrack` and on pull requests, without publishing.

## Local release build

```bash
MIDTRACK_NO_SWIFT_SANDBOX=1 ./scripts/package.sh
```

Everything lands in `dist/release/`. Verify:

```bash
cd dist/release
shasum -a 256 -c SHA256SUMS.txt
hdiutil attach Midtrack-1.0.0.dmg
# open the mounted volume, drag Midtrack to Applications
```

## Signing and Gatekeeper

The build is **ad-hoc signed** (`codesign --sign -`), not notarized. There is no
Developer ID certificate in the pipeline. This is deliberate for a personal app
that uses the private MediaRemote framework and cannot ship on the App Store.

As a result, macOS may block the first launch:

- Right-click **Midtrack.app** › **Open**, or
- `xattr -dr com.apple.quarantine /Applications/Midtrack.app`.

The README tells end users this. If the project ever gets a Developer ID
identity, replace the ad-hoc step in `build.sh` with hardened-runtime signing and
add a notarization step; do not fake the current provenance.

## Post-release checklist

- [ ] Tag matches the version in `Info.plist`.
- [ ] `swift test --disable-sandbox` passes locally and in CI.
- [ ] `./scripts/package.sh` produces both assets and checksums.
- [ ] The DMG opens and `Midtrack.app` launches on a clean account.
- [ ] `--check` passes on a machine with a live Now Playing session.
- [ ] The release notes mention the Gatekeeper workaround.
- [ ] The About tab points at the correct repository and licence.

## CI environment notes

The macOS runner has the same SwiftPM sandbox nesting issue as local builds, so
both workflows set `MIDTRACK_NO_SWIFT_SANDBOX=1`. The tests use a throwaway
preferences domain and do not need a logged-in GUI session.

The full `--check` is not run in CI because the runner has no Now Playing
session; it is a local and post-release check.
