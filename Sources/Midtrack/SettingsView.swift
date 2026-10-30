import AppKit
import SwiftUI

enum PreferenceKey {
    static let hasCompletedOnboarding = "HasCompletedOnboarding"
}

/// Window/Dock lifecycle. Midtrack is a menu bar agent whenever no window is
/// open. Opening the main window temporarily makes it a regular app so it
/// appears in the Dock and ⌘-Tab; closing the window returns it to the menu bar
/// only, while the reader keeps running.
enum DockVisibility {
    /// Called at launch before the main window appears.
    static func apply() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// The main window is on screen.
    static func showForWindow() {
        NSApp.setActivationPolicy(.regular)
    }

    /// The main window closed: disappear from the Dock and ⌘-Tab, keep running.
    static func hideAfterWindow() {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        Form {
            Section("Background") {
                Text("Closing the main window removes Midtrack from the Dock and ⌘-Tab, but the "
                    + "menu bar icon keeps running and the reader keeps watching what is playing. "
                    + "Open the main window from the menu bar, or launch Midtrack again; the "
                    + "running app is reused. Use Quit Midtrack in the menu bar panel to stop it "
                    + "completely.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Setup") {
                Button("Show the welcome screen again") {
                    hasCompletedOnboarding = false
                    NotificationCenter.default.post(name: .midtrackShowWelcome, object: nil)
                }
                .help("Show the welcome sheet over the main window now.")
                .accessibilityHint("Shows the welcome sheet over the main window now")

                Button("Open the log") {
                    model.openLog()
                }
                .help("Open ~/Library/Logs/Midtrack/app.log in the default text editor.")

                Button("Show log in Finder") {
                    model.revealLog()
                }
                .help("Reveal the log file in Finder.")

                Text("The welcome screen explains the menu bar icon, where Midtrack reads now-playing "
                    + "from, and what the first launch leaves alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("About") {
                LabeledContent("Version", value: "\(model.appVersion) (\(model.appBuild))")
                Text("Midtrack is free software under GPL-3.0. It uses the private MediaRemote "
                    + "API to jump playback, so it is not distributed on the App Store.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
