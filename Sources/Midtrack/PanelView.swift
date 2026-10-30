import AppKit
import SwiftUI

/// The menu bar quick panel. It uses the same `MidtrackControls` as the main
/// window, plus just two entry points: open the full window, or quit.
struct PanelView: View {
    var model: AppModel
    var nowPlaying: NowPlayingStore
    var status: StatusStore

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MidtrackControls(model: model, nowPlaying: nowPlaying, status: status, compact: true)

            Divider()

            HStack(spacing: 6) {
                Button("Open Midtrack") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .help("Open the full Midtrack window.")
                .accessibilityHint("Opens the full Midtrack window")

                Spacer()

                Button("Quit Midtrack") { model.quit() }
                    .help("Stop watching now-playing and quit Midtrack.")
                    .accessibilityHint("Stops watching now-playing and quits Midtrack")
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 420)
        // The 10 Hz now-playing values only run while a surface is on screen.
        .onAppear { model.panelAppeared() }
        .onDisappear { model.panelDisappeared() }
    }
}
