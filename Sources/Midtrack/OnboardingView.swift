import AppKit
import SwiftUI

/// First-run explanation, shown as a sheet over the main window. The app is a
/// menu bar utility, but the main window keeps the welcome content visible while
/// the user reads it and after it is dismissed.
struct OnboardingView: View {
    @ObservedObject var model: AppModel

    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            Divider()

            Text("Midtrack lives in the menu bar. Click the waveform icon to pause or start it, "
                + "choose where every track should begin, and jump the song already playing. "
                + "The main window appears in the Dock while it is open; closing it returns "
                + "Midtrack to the menu bar and keeps watching.")
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                Text("Before you start")
                    .font(.headline)

                OnboardingRow(
                    icon: "music.note.list",
                    title: "Reads what is already playing",
                    detail: "Midtrack asks macOS for the Now Playing session — the same information "
                        + "as the Now Playing widget. It does not capture audio and does not need "
                        + "the microphone."
                )

                Divider()

                OnboardingRow(
                    icon: "forward.end.fill",
                    title: "Pick the moment",
                    detail: "The first track is only a baseline. From the next track on, Midtrack "
                        + "jumps to the time, percentage, or random window you choose."
                )

                Divider()

                OnboardingRow(
                    icon: "lock.fill",
                    title: "Stay on this Mac",
                    detail: "No account, no network, no telemetry. The rule, the players you "
                        + "ignore, and the log never leave the machine."
                )
            }
            .cardSurface(padding: 18)

            Text("Jumping uses MediaRemote, a private macOS API — the same call the system's own "
                + "Now Playing widget makes. A future macOS release may change it. The reader runs "
                + "under osascript, so no extra helper is installed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Open the log") { model.openLog() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("Opens Midtrack's log in the default text editor")

                Spacer()

                Button("Not now") {
                    closeAndFocusMainWindow()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Closes this sheet. It will appear again next time Midtrack opens the main window.")

                Button("Open Midtrack") {
                    hasCompletedOnboarding = true
                    model.start()
                    closeAndFocusMainWindow()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Closes the welcome sheet and opens Midtrack")
            }
        }
        .padding(32)
        .frame(width: 600)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func closeAndFocusMainWindow() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.title == "Midtrack" }?.makeKeyAndOrderFront(nil)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Midtrack")
                    .font(.largeTitle.bold())
                Text("Skip to the good part — automatically.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
