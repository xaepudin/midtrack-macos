import AppKit
import MidtrackKit
import SwiftUI

extension Notification.Name {
    /// Posted when the app is reopened (Dock click, Spotlight, Finder) with no
    /// visible windows. The menu bar label listens and opens the main window.
    static let midtrackOpenMainWindow = Notification.Name("MidtrackOpenMainWindow")
    /// Posted by Settings to bring the welcome sheet back even when the stored
    /// "completed" flag is already false (so `onChange` would not fire).
    static let midtrackShowWelcome = Notification.Name("MidtrackShowWelcome")
}

/// Midtrack is a menu bar agent with a Dock icon while its window is open.
/// AppKit's default "terminate after the last window closes" policy would kill
/// it as soon as the main window is closed, taking the menu bar item with it,
/// so opt out.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .midtrackOpenMainWindow, object: nil)
        }
        return true
    }
}

@main
struct MidtrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    private let suppressWelcomeAtLaunch = CommandLine.arguments.contains("--show-main")

    init() {
        // `--check` and the render modes inspect the environment and exit; they
        // must run before the menu bar UI (and the reader it starts) exists.
        Diagnostics.runIfRequested()

        let model = AppModel()
        _model = StateObject(wrappedValue: model)

        // Starting the reader during App.init is too early: the app has not
        // finished launching. Wait for the launch notification, exactly once.
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification,
                                              object: nil,
                                              queue: .main) { _ in
            guard !launchHandled else { return }
            launchHandled = true
            // The notification is delivered on the main queue.
            MainActor.assumeIsolated {
                DockVisibility.apply()
                model.start()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model, nowPlaying: model.nowPlaying, status: model.status)
        } label: {
            MenuBarLabel(status: model.status)
        }
        .menuBarExtraStyle(.window)

        Window("Midtrack", id: "main") {
            MainWindowView(model: model,
                           nowPlaying: model.nowPlaying,
                           status: model.status,
                           suppressWelcome: suppressWelcomeAtLaunch)
        }
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    UserDefaults.standard.set(MainTab.settings.rawValue, forKey: "MainTab")
                    NotificationCenter.default.post(name: .midtrackOpenMainWindow, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // The standard Quit would terminate without stopping the osascript
            // reader; route it through the model like the panel does.
            CommandGroup(replacing: .appTermination) {
                Button("Quit Midtrack") {
                    model.quit()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

/// Isolated so that now-playing updates cannot invalidate the `MenuBarExtra`
/// scene: the label only watches the rarely-changing status.
private struct MenuBarLabel: View {
    @ObservedObject var status: StatusStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // The same mark as the app icon, as a template image so the menu bar
        // tints it for light and dark. Paused dims it rather than switching to
        // a different symbol.
        Image(nsImage: MenuBarIcon.image)
            .renderingMode(.template)
            .opacity(status.enabled ? 1 : 0.45)
            .accessibilityLabel("Midtrack")
            .accessibilityValue(status.enabled ? "Running" : "Paused")
            .accessibilityHint("Opens the Midtrack controls")
            .onReceive(NotificationCenter.default.publisher(for: .midtrackOpenMainWindow)) { _ in
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

/// Guards against a second launch notification starting a second reader.
private var launchHandled = false
