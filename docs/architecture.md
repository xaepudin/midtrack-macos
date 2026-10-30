# Architecture and watcher rules

Midtrack is a menu bar agent with a conventional window. Its job is narrow: read
the system Now Playing session, decide when a track change deserves a seek, and
call the private seek function.

```
reader.js ──▶ osascript child ──▶ snapshots ──▶ Watcher ──▶ MRMediaRemoteSetElapsedTime
 (JXA)          (Apple-signed)       10 Hz        rules                (private API)
```

## Source map

```
Sources/MidtrackKit/        No UI. Preferences, seek maths, guardrails, reader, watcher.
  AppLog.swift              Append-only log at ~/Library/Logs/Midtrack/app.log
  JXAReader.swift           Spawns osascript, parses one JSON line per snapshot
  MediaRemote.swift         dlopen("MRMediaRemoteSetElapsedTime")
  Preferences.swift         UserDefaults-backed rule, ignore list, last jump
  SeekLogic.swift           SeekSettings, targets, skip reasons, formatting
  Watcher.swift             Baseline, track changes, dedup, position guard, seek

Sources/Midtrack/           UI and lifecycle.
  MidtrackApp.swift         MenuBarExtra, main Window, AppDelegate, Dock policy
  AppModel.swift            Reader lifecycle, published low-rate state, actions
  Stores.swift              NowPlayingStore (10 Hz), StatusStore (rare)
  ControlViews.swift        Shared panel/window controls, TrackMeter, range slider
  PanelView.swift           Compact menu bar panel
  MainWindowView.swift      Sidebar tabs: Control, Players, Diagnostics, Settings, About
  OnboardingView.swift      First-run sheet
  SettingsView.swift        Dock lifecycle + Settings form
  Diagnostics.swift         --check and off-screen render modes
  MenuBarIcon.swift         Monochrome template mark for the menu bar

Tests/MidtrackKitTests/     48 tests covering seek maths, guardrails, preferences,
                            the ignore list, and every watcher decision.
reader.js                   JXA reader copied into the app bundle by build.sh.
Resources/                  Info.plist and AppIcon.icns.
scripts/                    Icon generation, release packaging.
```

## Reading Now Playing

On recent macOS the MediaRemote **read** side is gated to Apple-signed
processes. A normal app gets nil, but `osascript` is Apple-signed, so Midtrack
runs a persistent `osascript` child with `reader.js`:

- The child prints a JSON snapshot on every
  `kMRMediaRemoteNowPlayingInfoDidChangeNotification` plus a 0.1 s fallback poll.
- A snapshot carries app name, title, artist, duration, elapsed time, playback
  rate, and the player's timestamp.
- `JXAReader` parses lines on a background thread and hops them to the main
  queue. The child is respawned if it exits.

Track identity is `title|artist`. A session with no title has no identity and is
treated as no media.

## Seeking

`MediaRemote.seek(to:)` resolves `MRMediaRemoteSetElapsedTime` with `dlopen` and
calls it with the target offset. This is the same private function the system's
own Now Playing widget uses. Only the write side is called from the app process.

## The watcher

`Watcher.tick(snapshot)` is deliberately free of timers and UI. Its dependencies
are injectable (`seek`, `settings`, `isEnabled`, `ignoresPlayer`, `now`,
`recordJump`), which is why the decision rules are testable without touching
playback.

### Baseline

The first track after launch (or after the media session has been gone long
enough) is remembered as the baseline and is **never** jumped. This also applies
when seeking is paused: pausing does not reset the baseline, so re-enabling
mid-song does not yank the current track.

### Track change

When the identity changes, the watcher:

1. Ignores sessions from a player on the deny-list entirely. Such a session
   never becomes the baseline.
2. If the length is not known yet, stores the track as pending and judges it
   when the length arrives.
3. Computes `autoNext`: the previous track ended naturally if its elapsed time
   was within 3 seconds of its duration.
4. If **Also seek on natural end** is off and this was a natural end, leaves it
   alone.
5. Applies guardrails and the target rule.

A metadata re-post with the same title within 3 seconds of the baseline is the
same track, not a new one. Players often publish a title before the artist or a
corrected duration.

A transient gap in the media session (Chrome often drops it between tracks) is
tolerated for roughly 4.5 seconds before the baseline is reset.

### Position ownership

A track change may report an elapsed position that was already past the target.
The watcher does not blindly treat that as "the user skipped to the end":

- A position that has not moved since before the change belongs to the previous
  track and cannot veto the jump.
- A trusted position clearly past the target (by more than 5 seconds) is left
  alone, so a manual skip is not yanked backwards.
- The same track is not jumped twice within 30 seconds. This is the only dedup;
  replaying a track later still gets its jump.

The 30-second window handles a track change reported twice a moment apart. A
session handed back and forth between players is handled by the ignore list and
the position guard instead.

### Guardrails

Two limits are **opt-in**, controlled by `SeekSettings.guardrailsEnabled`
(`Prefs.guardrailsEnabled`), which defaults to false:

- `minDurationSeconds` — skip tracks shorter than the limit.
- `maxTargetPercent` — cap how far into a track a jump may land.

While the toggle is off, both fields are ignored but kept, so re-enabling
restores them. A track with no known length is never seeked regardless of the
toggle, because there is no safe target.

`guardrailSummary` renders ` · >1:30, ≤80%`, ` · guardrails off`, or nothing
(toggle on, both values 0).

### Jump now

The panel's **Jump now** bypasses the dedup and the min-length limit (an explicit
"do it anyway"), but still refuses:

- when seeking is paused,
- when the player is on the ignore list,
- when the track has no known length.

The max-jump ceiling is still applied when guardrails are on.

### Player deny-list

`Prefs.ignoredPlayers` is a deny-list. A ticked player:

- never has its tracks jumped,
- never becomes the baseline,
- has **Jump now** refused.

An empty player name cannot be matched, so it is never ignored. This prevents an
unknown session from silently turning Midtrack into a no-op.

## UI state and energy

`AppModel` publishes only low-rate values: settings, active player, status
narration, last jump, and hints. The 10 Hz now-playing values live in
`NowPlayingStore`, and the menu bar label observes only `StatusStore`.

The same pattern is why the `MenuBarExtra` scene does not re-render ten times a
second. The panel and main window call `uiAppeared()` / `uiDisappeared()`; the
fast values are only mirrored while a surface is visible. The 1 Hz health timer
only changes `hintMessage` when the message actually changes.

The menu bar panel contains:

- status header and pause switch,
- now playing and **Jump now**,
- jump target and the two-handle random window,
- the always-visible player deny-list,
- status messages and the rule/reader footer,
- **Open Midtrack** / **Quit Midtrack**.

Guardrails and Settings are main-window only. The panel deliberately does not
collapse sections: the list is always visible and the panel stays a predictable
height.

## Lifecycle

- `LSUIElement` makes the app a menu bar agent by default.
- Opening the main window switches the activation policy to `.regular` so it
  appears in the Dock and ⌘-Tab.
- Closing the window switches back to `.accessory` and keeps the reader running.
- Reopening from the Dock, Spotlight, or Finder posts a notification that opens
  the window.
- Quit stops the reader and terminates. The app menu's Quit is routed through the
  same path as the panel.

## Tests

`Tests/MidtrackKitTests/MidtrackKitTests.swift` covers:

- target maths for Time, Percent, and Random,
- the unknown-length rule,
- min length and max jump with guardrails on and off,
- preference clamping and defaults,
- the 30-second dedup and auto-next gating,
- transient media gaps and baseline absorption,
- a video stealing the session and handing it back,
- an ignored player never disturbing the baseline,
- **Jump now** refusal and bypass rules.

Run with `swift test --disable-sandbox` (see [building](building.md)).
