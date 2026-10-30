import AppKit
import MidtrackKit
import SwiftUI

/// The conventional window offered alongside the menu bar panel. It exists so
/// Midtrack can be found from the Dock/Spotlight, the player deny-list has room,
/// diagnostics are readable, and Settings is one click away without hunting for
/// a menu bar icon.
struct MainWindowView: View {
    var model: AppModel
    var nowPlaying: NowPlayingStore
    var status: StatusStore
    var suppressWelcome = false
    /// Used by `--render-window` so a screenshot can show any tab without
    /// writing the user's real `MainTab` preference.
    var initialTab: MainTab? = nil

    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage("MainTab") private var tabRaw = MainTab.control.rawValue
    @State private var tabOverride: MainTab?
    @State private var showWelcome = false
    @State private var isSurfaceVisible = false

    private var selectedTab: MainTab {
        tabOverride ?? MainTab(rawValue: tabRaw) ?? .control
    }

    private var tabSelection: Binding<MainTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                // A render's `initialTab` is a preview only; never write it into
                // the user's real MainTab preference.
                if tabOverride != nil {
                    tabOverride = newValue
                } else {
                    tabRaw = newValue.rawValue
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 190)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 980, minHeight: 640)
        .onAppear {
            if let initialTab, tabOverride == nil { tabOverride = initialTab }
            if !isSurfaceVisible {
                isSurfaceVisible = true
                DockVisibility.showForWindow()
                model.uiAppeared()
            }
            NSApp.activate(ignoringOtherApps: true)
            model.refreshPlayers()
            if !suppressWelcome && !hasCompletedOnboarding {
                showWelcome = true
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed {
                focusMainWindow()
            } else if !suppressWelcome {
                showWelcome = true
            }
        }
        .onChange(of: showWelcome) { _, showing in
            if !showing { focusMainWindow() }
        }
        .onDisappear {
            if isSurfaceVisible {
                isSurfaceVisible = false
                DockVisibility.hideAfterWindow()
                model.uiDisappeared()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard isSurfaceVisible,
                  let window = notification.object as? NSWindow,
                  window.title == "Midtrack" else { return }
            isSurfaceVisible = false
            DockVisibility.hideAfterWindow()
            model.uiDisappeared()
        }
        .onReceive(NotificationCenter.default.publisher(for: .midtrackShowWelcome)) { _ in
            if !suppressWelcome { showWelcome = true }
        }
        .sheet(isPresented: $showWelcome) {
            OnboardingView(model: model)
        }
    }

    private var sidebar: some View {
        // Plain rows, no Section header: macOS renders sidebar sections with a
        // collapsible disclosure control, and a header would compete with the
        // window title. The title bar already identifies the app.
        List(selection: tabSelection) {
            ForEach(MainTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func focusMainWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.title == "Midtrack" }?.makeKeyAndOrderFront(nil)
        }
    }

    @ViewBuilder private var detail: some View {
        switch selectedTab {
        case .control:
            ScrollView {
                MidtrackControls(model: model, nowPlaying: nowPlaying, status: status, compact: false)
                    .frame(maxWidth: 960, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        case .players:
            PlayersView(model: model)
        case .diagnostics:
            DiagnosticsView(model: model)
        case .settings:
            SettingsView(model: model)
                .frame(maxWidth: 720, maxHeight: .infinity)
                .padding(24)
                .frame(maxWidth: .infinity)
        case .about:
            AboutView(version: model.appVersion, build: model.appBuild)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case control
    case players
    case diagnostics
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .control: return "Control"
        case .players: return "Players"
        case .diagnostics: return "Diagnostics"
        case .settings: return "Settings"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .control: return "slider.horizontal.3"
        case .players: return "person.wave.2"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct PlayersView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Players to ignore")
                        .font(.title2.bold())
                    Spacer()
                    Button {
                        model.refreshPlayers()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Re-read the players the reader has seen.")
                }

                Text("Every player that has held the system Now Playing session appears here. "
                    + "Ticked means ignored: Midtrack never jumps that player's tracks, and its "
                    + "session never becomes the baseline — so a browser tab or a video cannot make "
                    + "the song that is playing look like a new track. Unticked players are jumped "
                    + "normally.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    Label("Ticked = ignored", systemImage: "checkmark.square.fill")
                        .foregroundStyle(.orange)
                    Label("Unticked = jumped", systemImage: "square")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                if model.seenPlayers.isEmpty {
                    ContentUnavailableView(
                        "No players yet",
                        systemImage: "person.wave.2",
                        description: Text("Start playback in any player — YouTube Music, Spotify, Apple Music, or a browser tab. It will show up here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    PlayersSection(model: model, compact: false, showsHeading: false)
                    HStack {
                        let ignored = model.seenPlayers.filter { model.isIgnored($0) }.count
                        Text("\(ignored) of \(model.seenPlayers.count) ignored")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let active = model.activePlayer {
                            Text("Playing now: \(active)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diagnostics")
                    .font(.title2.bold())

                Text("Midtrack reads the system Now Playing session through osascript and writes a new "
                    + "position through MediaRemote. These values update while this window is open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Current status") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.statusText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        if model.infoLines.isEmpty {
                            Text("No status lines yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.infoLines, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let error = model.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let hint = model.hintMessage {
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                HStack(spacing: 8) {
                    Button("Open Log") { model.openLog() }
                    Button("Show in Finder") { model.revealLog() }
                    Button("Copy Report") { model.copyDiagnosticReport() }
                        .accessibilityHint("Copies status, reader, and rule information without any audio")
                }

                GroupBox("Full end-to-end check") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quit Midtrack, then run this from Terminal. It reports the bundle, the "
                            + "reader script, whether the private seek API is reachable, and one live "
                            + "now-playing snapshot.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("dist/Midtrack.app/Contents/MacOS/Midtrack --check")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("When running from a source build, use dist/Midtrack.app instead.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Log: \(AppLog.url.path)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                Text("The log contains lifecycle messages, player names, and track titles — never audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AboutView: View {
    let version: String
    let build: String

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Midtrack")
                .font(.largeTitle.bold())
            Text("Skip to the good part — automatically.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Midtrack watches the system Now Playing session and jumps each new track to "
                + "the spot you chose.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 4)

            HStack(spacing: 16) {
                Link("Repository", destination: URL(string: "https://github.com/xaepudin/midtrack-macos")!)
                Link("Report an issue", destination: URL(string: "https://github.com/xaepudin/midtrack-macos/issues")!)
                Link("GPL-3.0 license", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }
            .font(.callout)

            Text("Jumping uses MediaRemote, a private macOS API. Not for the App Store. "
                + "Midtrack is free software under GPL-3.0.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(30)
        .frame(minWidth: 520, minHeight: 380)
    }
}
