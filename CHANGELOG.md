# Changelog

## 1.0.0 — 2026-10-30

First Midtrack release: **Skip to the good part — automatically.**

### Added
- A conventional main window with **Control**, **Players**, **Diagnostics**,
  **Settings**, and **About** tabs, alongside the menu bar panel.
- A first-run welcome sheet, a Dock icon while a window is open, and a menu bar
  item that returns to accessory mode when the window closes.
- A **Players to ignore** tab with a plain-language ticked/unticked legend and
  the active player marked.
- An **Enable guardrails** switch, off by default. While off, Min length and Max
  jump are ignored and their sliders are locked; turning it on applies both.
- A two-handle **Random window** slider for Random mode, replacing the separate
  From and To sliders.
- A diagnostics page with live status, log access, a copyable report, and the
  `--check` command.
- A monochrome template version of the app mark for the menu bar, dimmed while
  paused.
- `--render-window`, `--render-panel`, `--render-onboarding`,
  `--render-menubar-icon`, and `--tab` for reviewing layouts off-screen.
- A generated app icon (`scripts/make-icon.py`): a teal waveform bisected by an
  orange midpoint marker.

### Changed
- Rebuilt the panel and controls in the visual language of Konvolusi: card
  surfaces, section headers, ⓘ popovers, monospaced values, and shared controls
  between the panel and the window.
- The status line now calls the master switch **Running/Paused** rather than
  on/off, matching the Start/Pause button.
- The panel is 420 pt wide and shows the **Players to ignore** list directly.
  Guardrails and Settings stay in the main window, and the panel footer has only
  **Open Midtrack** and **Quit Midtrack**.

### Fixed
- Slider values snap while the track stays continuous, so macOS no longer draws
  a tick mark for every integer.
- Preferences no longer ask `UserDefaults` for the app's own bundle identifier
  as a suite (which Foundation rejects).
