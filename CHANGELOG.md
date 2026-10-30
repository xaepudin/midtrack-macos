# Changelog

## 1.0.0 — 2026-10-30

Midtrack is the new name for Song Seeker. The seek engine, its guardrails, and
its watcher behaviour are unchanged; the app around them is new.

### Added
- A conventional main window with **Control**, **Players**, **Diagnostics**,
  **Settings**, and **About** tabs, alongside the menu bar panel.
- A first-run welcome sheet, a Dock icon while a window is open, and a menu bar
  item that returns to accessory mode when the window closes.
- A **Players** tab for the ignore list, with the active player marked.
- A diagnostics page with live status, log access, a copyable report, and the
  `--check` command.
- `--render-window`, `--render-onboarding`, and `--tab` for reviewing layouts
  off-screen.
- A generated app icon (`scripts/make-icon.py`): a teal waveform bisected by an
  orange midpoint marker.

### Changed
- Renamed the package, targets, types, bundle identifier, executable, log
  directory, and launcher from Song Seeker to Midtrack.
- Rebuilt the panel and controls in the visual language of Konvolusi: card
  surfaces, section headers, ⓘ popovers, monospaced values, and shared controls
  between the panel and the window.
- Preferences now live in `com.asep.midtrack`; the first launch copies the rule,
  ignore list, seen players, and last jump once from the old domains.
- The status line now calls the master switch **Running/Paused** rather than
  on/off, matching the new Start/Pause button.
- The panel is 420 pt wide and no longer carries the player list; **Players…**
  opens the full tab instead.

### Fixed
- Slider values snap while the track stays continuous, so macOS no longer draws
  a tick mark for every integer.
- Preferences no longer ask `UserDefaults` for the app's own bundle identifier
  as a suite (which Foundation rejects).
