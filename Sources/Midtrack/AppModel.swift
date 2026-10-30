import AppKit
import Combine
import Foundation
import MidtrackKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    // MARK: - Settings (published so the panel's controls drive them directly)

    @Published var enabled: Bool = Prefs.enabled {
        didSet {
            guard enabled != oldValue else { return }
            if !isStaging { Prefs.enabled = enabled }
            status.enabled = enabled
            AppLog.write("enabled -> \(enabled)")
            refreshSummary()
        }
    }

    /// The rule: mode, numbers, guardrails. Every field is editable through the
    /// same form the panel shows.
    @Published var settings: SeekSettings = Prefs.settings {
        didSet {
            guard settings != oldValue else { return }
            Prefs.save(settings)
            if settings.mode != oldValue.mode { AppLog.write("jump mode -> \(settings.mode.rawValue)") }
            refreshSummary()
        }
    }

    /// Players whose sessions are left alone entirely — the deny-list.
    @Published var ignoredPlayers: Set<String> = Prefs.ignoredPlayers {
        didSet {
            guard ignoredPlayers != oldValue else { return }
            Prefs.ignoredPlayers = ignoredPlayers
            AppLog.write("ignoring -> \(ignoredPlayers.isEmpty ? "nobody" : ignoredPlayers.sorted().joined(separator: ", "))")
            refreshSummary()
        }
    }

    @Published private(set) var seenPlayers: [String] = Prefs.seenPlayers
    @Published private(set) var activePlayer: String?

    // MARK: - Published state (all of it low-rate; see Stores.swift)

    @Published private(set) var statusText = "Starting…"
    @Published private(set) var lastJumpText: String
    @Published private(set) var infoLines: [String] = []
    @Published private(set) var hintMessage: String?
    @Published private(set) var errorMessage: String?

    let nowPlaying = NowPlayingStore()
    let status = StatusStore()

    let appVersion: String
    let appBuild: String

    private let watcher = Watcher()
    private var reader: JXAReader?
    private var latest: JXAReader.Snapshot?
    private var readerState = "starting"
    private var healthTimer: Timer?
    /// How many surfaces (menu bar panel, main window) are on screen. The
    /// 10 Hz values are mirrored only while at least one of them is visible.
    private var visibleSurfaces = 0
    private var hasStarted = false
    private var hasSeenTrack = false
    private var isStaging = false
    private let launchAt = Date()
    private var lastTrackSeenAt = Date()

    init() {
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        lastJumpText = Prefs.lastJumpTitle.map { "\($0) → \(SeekLogic.format(Prefs.lastJumpAt))" } ?? "none yet"
        // No reader, timer or file work here: SwiftUI is allowed to evaluate the
        // StateObject closure more than once, and a second reader would mean two
        // osascript children fighting over the same session.
        AppLog.write("AppModel init (bundle \(Bundle.main.bundleIdentifier ?? "-"))")
    }

    /// Called once, after the application has finished launching.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        AppLog.write("start")
        Prefs.forgetRetiredKeys()

        wireWatcher()

        let script = JXAReader.defaultScriptURL()
        if FileManager.default.fileExists(atPath: script.path) {
            let reader = JXAReader(scriptPath: script.path)
            reader.onSnapshot = { [weak self] snapshot in
                DispatchQueue.main.async { self?.received(snapshot) }
            }
            reader.start()
            self.reader = reader
            readerState = "reading reader.js"
        } else {
            readerState = "reader.js missing"
            errorMessage = "reader.js was not found at \(script.path)."
            AppLog.write("reader.js missing at \(script.path)")
        }
        if !MediaRemote.isAvailable {
            errorMessage = "MRMediaRemoteSetElapsedTime is unavailable — jumping is disabled."
        }

        status.enabled = enabled
        refreshSummary()
        startHealthTimer()
    }

    // MARK: - Reader

    private func wireWatcher() {
        watcher.onState = { [weak self] text in
            // The watcher runs on the main thread; snapshots are hopped there
            // before they reach it.
            self?.statusText = text
            AppLog.write(text)
        }
        watcher.onSeek = { [weak self] title, target in
            self?.lastJumpText = "\(title) → \(SeekLogic.format(target))"
        }
    }

    /// Staging for `--render-panel` / `--render-window`: runs the real watcher
    /// over `snapshot` with the seek stubbed out, so a photograph shows text
    /// produced by the production path without starting the reader or moving
    /// playback.
    func stageForPreview(snapshot: JXAReader.Snapshot?) {
        isStaging = true
        defer { isStaging = false }
        wireWatcher()
        watcher.seek = { _ in true }
        watcher.recordJump = { _, _ in }
        watcher.isEnabled = { true }
        // Show the running state in screenshots without writing the preference:
        // `enabled` skips persistence while staging.
        enabled = true
        // One synthetic baseline, then the live snapshot: the watcher then
        // narrates the change exactly as it would for a real track change.
        received(JXAReader.Snapshot(app: "Preview",
                                    title: "Previous track",
                                    artist: "Example artist",
                                    duration: 200,
                                    elapsed: 5,
                                    rate: 1,
                                    timestamp: Date().timeIntervalSince1970))
        // The live snapshot when a player is publishing one, an example track
        // otherwise, so a render always shows the position meter and the marker.
        // The position is pinned to 12 s so the demonstration shows the seek
        // path rather than the watcher correctly refusing a track already past
        // its target.
        let staged: JXAReader.Snapshot
        if let snapshot, snapshot.identity != nil {
            staged = JXAReader.Snapshot(app: snapshot.app ?? "YouTube Music",
                                        title: snapshot.title ?? "Example song",
                                        artist: snapshot.artist ?? "Example artist",
                                        duration: snapshot.duration > 60 ? snapshot.duration : 214,
                                        elapsed: 12,
                                        rate: 1,
                                        timestamp: Date().timeIntervalSince1970)
        } else {
            staged = JXAReader.Snapshot(app: "YouTube Music",
                                        title: "Example song",
                                        artist: "Example artist",
                                        duration: 214,
                                        elapsed: 12,
                                        rate: 1,
                                        timestamp: Date().timeIntervalSince1970)
        }
        received(staged)
        uiAppeared()
        readerState = "reading reader.js"
        refreshSummary()
    }

    private func received(_ snapshot: JXAReader.Snapshot?) {
        latest = snapshot
        if let player = snapshot?.app, !player.isEmpty, player != activePlayer {
            activePlayer = player
            // Staging must not write example players into the real list.
            if !isStaging {
                Prefs.rememberPlayer(player)
                seenPlayers = Prefs.seenPlayers
            }
        }
        if snapshot?.identity != nil {
            hasSeenTrack = true
            lastTrackSeenAt = Date()
        }
        watcher.tick(snapshot)
        if visibleSurfaces > 0 { publishNowPlaying() }
    }

    private func publishNowPlaying() {
        nowPlaying.update(with: latest, settings: .current)
    }

    /// Called by the menu bar panel and the main window. The 10 Hz values are
    /// only mirrored into the observable store while a surface can show them.
    func uiAppeared() {
        visibleSurfaces += 1
        guard visibleSurfaces == 1 else { return }
        publishNowPlaying()
    }

    func uiDisappeared() {
        visibleSurfaces = max(0, visibleSurfaces - 1)
    }

    /// Names used by the menu bar panel.
    func panelAppeared() { uiAppeared() }
    func panelDisappeared() { uiDisappeared() }

    // MARK: - Actions

    func toggleEnabled() {
        enabled.toggle()
    }

    /// Applies the rule to the song already playing, minus the dedup and the
    /// minimum-length guardrail — the panel's version of the Android app's
    /// "Jump now" notification button. Refused while the master switch is off,
    /// exactly as the Android app refuses it.
    func jumpNow() {
        let message = watcher.jumpNow(latest)
        statusText = message
        // The watcher already logged a successful jump through `onState`.
        if !message.hasPrefix("SEEK (manual)") { AppLog.write("jump now: \(message)") }
    }

    func isIgnored(_ player: String) -> Bool {
        ignoredPlayers.contains(player)
    }

    func setIgnored(_ ignored: Bool, forPlayer player: String) {
        var players = ignoredPlayers
        if ignored { players.insert(player) } else { players.remove(player) }
        ignoredPlayers = players
    }

    /// Re-reads the players the reader has seen, so a player that spoke up while
    /// a surface was closed still appears in the list.
    func refreshPlayers() {
        seenPlayers = Prefs.seenPlayers
    }

    func revealLog() {
        try? FileManager.default.createDirectory(at: AppLog.url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([AppLog.url])
    }

    func openLog() {
        try? FileManager.default.createDirectory(at: AppLog.url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppLog.url)
    }

    /// Copies a support-friendly report to the pasteboard. No audio, and no
    /// track titles beyond what is already on screen.
    func copyDiagnosticReport() {
        var lines = [
            "Midtrack \(appVersion) (\(appBuild))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Seeking: \(enabled ? "on" : "off")",
            "Rule: \(SeekLogic.describe(.current))\(Prefs.settings.guardrailSummary)",
            "Ignoring: \(ignoredPlayers.isEmpty ? "nobody" : ignoredPlayers.sorted().joined(separator: ", "))",
            "Seen players: \(seenPlayers.isEmpty ? "none yet" : seenPlayers.joined(separator: ", "))",
            "Reader: \(readerState)",
            "Seek API: \(MediaRemote.isAvailable ? "available" : "unavailable")",
            "Log: \(AppLog.url.path)",
        ]
        if let activePlayer {
            lines.append("Active player: \(activePlayer)")
        }
        if !statusText.isEmpty {
            lines.append("Status: \(statusText)")
        }
        if !infoLines.isEmpty {
            lines.append("")
            lines.append(contentsOf: infoLines)
        }
        if let errorMessage {
            lines.append("")
            lines.append("Error: \(errorMessage)")
        }
        if let hintMessage {
            lines.append("Hint: \(hintMessage)")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func quit() {
        AppLog.write("quit")
        reader?.stop()
        healthTimer?.invalidate()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Footer / hints

    private func refreshSummary() {
        var lines = [SeekLogic.describe(.current) + Prefs.settings.guardrailSummary]
        if !ignoredPlayers.isEmpty {
            lines.append("Ignoring: \(ignoredPlayers.sorted().joined(separator: ", "))")
        }
        lines.append("Reader: \(readerState) · Seek API: "
            + "\(MediaRemote.isAvailable ? "ready" : "unavailable")")
        infoLines = lines
    }

    /// 1 Hz and cheap: it only touches `hintMessage` when the message actually
    /// changes, so the menu bar scene is not invalidated once a second.
    private func startHealthTimer() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.healthTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func healthTick() {
        let quietFor = Date().timeIntervalSince(hasSeenTrack ? lastTrackSeenAt : launchAt)
        let newHint: String?
        if enabled, !hasSeenTrack, quietFor > 20 {
            newHint = "No now-playing session yet. Start playback in any player — the reader polls it ten times a second."
        } else {
            newHint = nil
        }
        if newHint != hintMessage { hintMessage = newHint }
    }
}
