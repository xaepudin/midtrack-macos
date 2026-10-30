import AppKit
import Foundation
import MidtrackKit
import SwiftUI

/// `Midtrack --check` exercises the pieces the panel depends on and exits, so
/// the app can be verified without hijacking playback. The render modes turn
/// SwiftUI surfaces into PNGs for documentation and layout review.
enum Diagnostics {
    static func runIfRequested() {
        if let path = value(for: "--render-panel") {
            MainActor.assumeIsolated { renderPanel(to: URL(fileURLWithPath: path)) }
            exit(0)
        }
        if let path = value(for: "--render-window") {
            MainActor.assumeIsolated { renderWindow(to: URL(fileURLWithPath: path)) }
            exit(0)
        }
        if let path = value(for: "--render-onboarding") {
            MainActor.assumeIsolated { renderOnboarding(to: URL(fileURLWithPath: path)) }
            exit(0)
        }
        if let path = value(for: "--render-menubar-icon") {
            MainActor.assumeIsolated { renderMenuBarIcon(to: URL(fileURLWithPath: path)) }
            exit(0)
        }
        guard CommandLine.arguments.contains("--check") else { return }
        let report = report()
        print(report.text)
        exit(report.passed ? 0 : 1)
    }

    // MARK: - Renders

    /// `--render-panel <file.png>` photographs the menu bar panel. Handy for
    /// reviewing a layout change without hunting for the status item — which
    /// matters here, because menu bar managers (Ice, Bartender) routinely file
    /// new items away in their hidden section.
    @MainActor
    private static func renderPanel(to url: URL) {
        let model = stagedModel()
        let content = PanelView(model: model, nowPlaying: model.nowPlaying, status: model.status)
            .background(Color(nsColor: .windowBackgroundColor))
        let forcedHeight = value(for: "--height").flatMap(Double.init)
        let root = forcedHeight.map { height in
            AnyView(content.frame(width: 420, height: height, alignment: .top))
        } ?? AnyView(content)
        render(root: root,
               size: CGSize(width: 420, height: forcedHeight ?? 640),
               fitsHeight: forcedHeight == nil,
               to: url)
    }

    /// `--render-window <file.png>` photographs the conventional window.
    /// `--tab control|players|diagnostics|settings|about` chooses the sidebar
    /// selection; `--appearance dark|light` pins the appearance for docs.
    @MainActor
    private static func renderWindow(to url: URL) {
        let model = stagedModel()
        let tab = value(for: "--tab").flatMap(MainTab.init(rawValue:)) ?? .control
        let content = MainWindowView(model: model,
                                     nowPlaying: model.nowPlaying,
                                     status: model.status,
                                     suppressWelcome: true,
                                     initialTab: tab)
        render(root: AnyView(content),
               size: CGSize(width: 1120, height: 720),
               fitsHeight: false,
               to: url)
    }

    @MainActor
    private static func stagedModel() -> AppModel {
        let model = AppModel()
        let script = JXAReader.defaultScriptURL()
        let snapshot = FileManager.default.fileExists(atPath: script.path) ? firstSnapshot(script: script) : nil
        model.stageForPreview(snapshot: snapshot)
        return model
    }

    /// `--render-onboarding <file.png>` photographs the first-run sheet.
    @MainActor
    private static func renderOnboarding(to url: URL) {
        let model = stagedModel()
        let content = OnboardingView(model: model)
            .background(Color(nsColor: .windowBackgroundColor))
        render(root: AnyView(content),
               size: CGSize(width: 600, height: 640),
               fitsHeight: true,
               to: url)
    }

    /// `--render-menubar-icon <file.png>` renders the template menu bar mark at
    /// 8x on a neutral background, so its silhouette can be reviewed.
    @MainActor
    private static func renderMenuBarIcon(to url: URL) {
        let size = NSSize(width: 180, height: 180)
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        MenuBarIcon.image.draw(in: NSRect(x: 18, y: 18, width: 144, height: 144),
                               from: .zero,
                               operation: .sourceOver,
                               fraction: 1)
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(using: .png, properties: [:]) else {
            print("could not render the menu bar icon")
            return
        }
        do {
            try png.write(to: url)
            print("wrote \(url.path) (\(Int(size.width * 2))x\(Int(size.height * 2)))")
        } catch {
            print("could not write \(url.path): \(error.localizedDescription)")
        }
    }

    /// Hosts a SwiftUI view in a real off-screen window and captures it with
    /// `cacheDisplay`, so AppKit draws the sliders, pickers, and switches itself
    /// instead of leaving placeholder glyphs.
    @MainActor
    private static func render(root: AnyView,
                               size: CGSize,
                               fitsHeight: Bool,
                               to url: URL) {
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = host
        window.backgroundColor = .windowBackgroundColor
        switch value(for: "--appearance") {
        case "dark": window.appearance = NSAppearance(named: .darkAqua)
        case "light": window.appearance = NSAppearance(named: .aqua)
        default: break
        }
        // Far off any display, so nothing flashes on screen while this runs.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        if fitsHeight {
            let fitting = host.fittingSize
            if fitting.height > 100 {
                host.frame = NSRect(x: 0, y: 0, width: size.width, height: fitting.height)
                window.setContentSize(host.frame.size)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            }
        }

        guard let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("could not render \(url.lastPathComponent)")
            return
        }
        host.cacheDisplay(in: host.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            print("could not encode \(url.lastPathComponent)")
            return
        }
        do {
            try png.write(to: url)
            print("wrote \(url.path) (\(Int(host.bounds.width))x\(Int(host.bounds.height)))")
        } catch {
            print("could not write \(url.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Self-check

    private static func value(for flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func report() -> (text: String, passed: Bool) {
        let script = JXAReader.defaultScriptURL()
        let scriptExists = FileManager.default.fileExists(atPath: script.path)
        var lines = [
            "Midtrack self-check",
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
