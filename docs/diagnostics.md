# Diagnostics

## Log

Everything the watcher and reader decide is appended to:

```
~/Library/Logs/Midtrack/app.log
```

Open it from **Diagnostics › Open Log**, reveal it in Finder, or follow it:

```bash
tail -f ~/Library/Logs/Midtrack/app.log
```

The log contains lifecycle messages, player names, track titles, and seek
decisions. It never contains audio.

## Self-check

```bash
dist/Midtrack.app/Contents/MacOS/Midtrack --check
```

It inspects the bundle, resolves `reader.js`, checks whether
`MRMediaRemoteSetElapsedTime` is reachable, prints the active rule and ignore
list, and waits for one live Now Playing snapshot.

Example:

```
Midtrack self-check
  bundle          : com.xaepudin.midtrack (…/dist/Midtrack.app)
  reader script   : …/Contents/Resources/reader.js (found)
  MediaRemote seek: available
  settings        : on · Random · jump somewhere between 15% and 60% · guardrails off · auto-next on
  ignoring        : IINA, mpv
  seen players    : Google Chrome, YouTube Music, mpv, IINA, Cog
  log             : /Users/asep/Library/Logs/Midtrack/app.log
  now playing     : Google Chrome · Instagram (0:00 / 1:38, rate 1.0)
RESULT: PASS — the seek API is reachable and reader.js is producing snapshots.
```

The check exits non-zero when `reader.js` is missing, the seek symbol is
unavailable, or no snapshot arrives. A runner with no Now Playing session can
still return a snapshot with no title; that is reported as `no session`.

## Copy report

**Diagnostics › Copy Report** puts the bundle, rule, ignore list, seen players,
reader state, seek API state, log path, and last status on the clipboard. It
contains no audio. Attach it to an issue.

## Common situations

### No Now Playing session

Start playback in a player that publishes to Now Playing — YouTube Music in
Safari/Chrome, Spotify, Apple Music, Cog, mpv, VLC, and so on. The reader polls
at 10 Hz. The panel's status line and the Diagnostics log say what it sees.

### Nothing jumps

Check, in order:

1. Is the master switch **Running**? **Jump now** is disabled while paused.
2. Is this the first track? The baseline is never jumped.
3. Is the player ticked in **Players to ignore**?
4. Does the track have a known duration? Live streams, ads, and some videos do
   not, and are never jumped.
5. Are guardrails on? A track shorter than **Min length** is skipped. A target
   beyond **Max jump** is capped.
6. Is **Also seek on natural end** off and the track ended by itself?
7. Is a browser stealing Now Playing? Tick it in **Players to ignore** so its
   session cannot disturb the music.

The status line names the reason for every skip.

### Chrome stops updating

Chrome can freeze its media session when a tab is heavily backgrounded. The
reader keeps the last known snapshot and catches the next change when the session
resumes. This is a Chrome limitation, not a seek failure.

### The menu bar icon is hidden

Ice and Bartender file newly seen status items under *Hidden*. Drag the Midtrack
waveform mark into *Visible* in their layout editor, or use their hidden-items
chevron.

### macOS blocks the app

Release builds are ad-hoc signed but not notarized. On first launch, right-click
the app and choose **Open**, or remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Midtrack.app
```

### Private API stopped working

`MRMediaRemoteSetElapsedTime` is private. A future macOS release may remove or
gate it. The read side is already gated to Apple-signed processes, which is why
the reader runs under `osascript`. If the write symbol disappears,
`MediaRemote.isAvailable` is false, the Diagnostics tab says so, and seeking is
disabled until the app is updated.

## Reporting a bug

Open an issue at <https://github.com/xaepudin/midtrack-macos/issues> with:

- macOS version,
- Midtrack version (About tab),
- the copied report,
- what you expected and what happened,
- the relevant lines from `~/Library/Logs/Midtrack/app.log`.

Please do not paste personal listening history beyond what is needed to explain
the problem.
