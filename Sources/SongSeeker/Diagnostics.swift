import AppKit
import Foundation
import SongSeekerKit
import SwiftUI

/// `SongSeeker --check` exercises the pieces the panel depends on and exits, so
/// the app can be verified without hijacking playback. Same idea as IRSVerb's
/// `--diagnose`.
enum Diagnostics {
    static func runIfRequested() {
        if let path = value(for: "--render-panel") {
            MainActor.assumeIsolated { render(panelTo: URL(fileURLWithPath: path)) }
            exit(0)
        }
        guard CommandLine.arguments.contains("--check") else { return }
        let report = report()
        print(report.text)
        exit(report.passed ? 0 : 1)
    }

    /// `--render-panel <file.png>` photographs the menu bar panel. Handy for
    /// reviewing a layout change without hunting for the status item — which
    /// matters here, because menu bar managers (Ice, Bartender) routinely file
    /// new items away in their hidden section.
    ///
    /// The panel is hosted in a real off-screen window and captured with
    /// `cacheDisplay`, so the sliders, segmented picker and switches are drawn by
    /// AppKit itself instead of as placeholder glyphs.
    @MainActor
    private static func render(panelTo url: URL) {
        let model = AppModel()
        let script = JXAReader.defaultScriptURL()
        let snapshot = FileManager.default.fileExists(atPath: script.path) ? firstSnapshot(script: script) : nil
        model.stageForPreview(snapshot: snapshot)

        // The real panel gets its background from the window's material; an
        // off-screen window has none, so the render carries its own — otherwise
        // the capture is a transparent PNG full of holes.
        let content = PanelView(model: model, nowPlaying: model.nowPlaying, status: model.status)
            .background(Color.white)

        // `--height` squeezes the panel into a smaller window, which is what the
        // real window does when it cannot be as tall as the content wants.
        let forcedHeight = value(for: "--height").flatMap(Double.init)
        let root = forcedHeight.map { height in
            AnyView(content.frame(width: 380, height: height, alignment: .top))
        } ?? AnyView(content)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 380, height: forcedHeight ?? 560)
        let window = NSWindow(contentRect: host.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = host
        // Far off any display, so nothing flashes on screen while this runs.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        if forcedHeight == nil {
            let fitting = host.fittingSize
            if fitting.height > 100 {
                host.frame = NSRect(x: 0, y: 0, width: 380, height: fitting.height)
                window.setContentSize(host.frame.size)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            }
        }

        guard let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("could not render the panel")
            return
        }
        host.cacheDisplay(in: host.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            print("could not encode the panel")
            return
        }
        do {
            try png.write(to: url)
            print("wrote \(url.path) (\(Int(host.bounds.width))x\(Int(host.bounds.height)))")
        } catch {
            print("could not write \(url.path): \(error.localizedDescription)")
        }
    }


    private static func value(for flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func report() -> (text: String, passed: Bool) {
        let script = JXAReader.defaultScriptURL()
        let scriptExists = FileManager.default.fileExists(atPath: script.path)
        var lines = [
            "Song Seeker self-check",
            "  bundle          : \(Bundle.main.bundleIdentifier ?? "-") (\(Bundle.main.bundlePath))",
            "  reader script   : \(script.path)\(scriptExists ? " (found)" : " (MISSING)")",
            "  MediaRemote seek: \(MediaRemote.isAvailable ? "available" : "UNAVAILABLE")",
            "  settings        : \(Prefs.enabled ? "on" : "off") · \(SeekLogic.describe(.current))\(Prefs.settings.guardrailSummary)"
                + " · auto-next \(Prefs.seekOnAutoNext ? "on" : "off")",
            "  ignoring        : \(Prefs.ignoredPlayers.isEmpty ? "nobody" : Prefs.ignoredPlayers.sorted().joined(separator: ", "))",
            "  seen players    : \(Prefs.seenPlayers.isEmpty ? "none yet" : Prefs.seenPlayers.joined(separator: ", "))",
            "  log             : \(AppLog.url.path)",
        ]
        var passed = scriptExists && MediaRemote.isAvailable
        if scriptExists {
            if let snapshot = firstSnapshot(script: script) {
                lines.append("  now playing     : \(describe(snapshot))")
            } else {
                lines.append("  now playing     : no snapshot within \(Int(timeout)) s")
                passed = false
            }
        }
        lines.append(passed
            ? "RESULT: PASS — the seek API is reachable and reader.js is producing snapshots."
            : "RESULT: FAIL — see the lines marked above.")
        return (lines.joined(separator: "\n"), passed)
    }

    private static let timeout: TimeInterval = 6

    /// Runs the reader once and returns its first snapshot line.
    private static func firstSnapshot(script: URL) -> JXAReader.Snapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", script.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        defer { process.terminate() }

        var buffer = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            buffer.append(chunk)
            if let newline = buffer.firstIndex(of: 0x0A) {
                return JXAReader.parse(Data(buffer[..<newline]))
            }
        }
        return nil
    }

    private static func describe(_ snapshot: JXAReader.Snapshot) -> String {
        guard let title = snapshot.title, !title.isEmpty else {
            return "no session (\(snapshot.app ?? "no player"))"
        }
        let artist = (snapshot.artist?.isEmpty == false) ? " — \(snapshot.artist!)" : ""
        let position = snapshot.duration > 0
            ? "\(SeekLogic.format(snapshot.elapsed)) / \(SeekLogic.format(snapshot.duration))"
            : SeekLogic.format(snapshot.elapsed)
        return "\(snapshot.app ?? "?") · \(title)\(artist) (\(position), rate \(snapshot.rate))"
    }
}
