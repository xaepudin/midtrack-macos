import AppKit
import SongSeekerKit
import SwiftUI

@main
struct SongSeekerApp: App {
    @StateObject private var model: AppModel

    init() {
        // `--check` inspects the environment and exits; it must run before the
        // menu bar UI (and the reader it starts) exists.
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
            MainActor.assumeIsolated { model.start() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model, nowPlaying: model.nowPlaying, status: model.status)
        } label: {
            MenuBarLabel(status: model.status)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Isolated so that now-playing updates cannot invalidate the `MenuBarExtra`
/// scene: the label only watches the rarely-changing status.
private struct MenuBarLabel: View {
    @ObservedObject var status: StatusStore

    var body: some View {
        // Filled while seeking is on, outline while it is off — the same
        // semantics as the original hand-drawn menu bar triangle.
        Image(systemName: status.enabled ? "play.circle.fill" : "play.circle")
    }
}

/// Guards against a second launch notification starting a second reader.
private var launchHandled = false
