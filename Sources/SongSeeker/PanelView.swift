import SongSeekerKit
import SwiftUI

/// Position bar: how far into the track playback is, plus where the next jump
/// lands — a marker for Time/Percent mode, or the whole window for Random mode.
struct TrackMeter: View {
    let elapsed: Double
    let duration: Double
    let marker: Double?
    let band: ClosedRange<Double>?

    var body: some View {
        HStack(spacing: 8) {
            Text("Pos")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.12))
                    if let band {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: max(1, width * fraction(band.upperBound - band.lowerBound)))
                            .offset(x: width * fraction(band.lowerBound))
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green)
                        .frame(width: max(0, width * fraction(elapsed)))
                    if let marker {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2, height: 9)
                            .offset(x: max(0, min(width - 2, width * fraction(marker))))
                    }
                }
            }
            .frame(height: 6)
        }
    }

    private func fraction(_ seconds: Double) -> Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, seconds / duration))
    }
}

// MARK: - The rule form

private extension Binding where Value == SeekSettings {
    /// A slider binding onto one integer field of the rule.
    func int(_ keyPath: WritableKeyPath<SeekSettings, Int>) -> Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue[keyPath: keyPath]) },
            set: { wrappedValue[keyPath: keyPath] = Int($0.rounded()) }
        )
    }
}

private struct RuleSlider: View {
    let label: String
    let value: String
    let binding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: binding, in: range, step: step)
        }
    }
}

/// The Android app's "Guardrails" card: minimum length, jump ceiling, and the
/// rule that a track with no known length is never touched.
private struct GuardrailForm: View {
    @Binding var settings: SeekSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RuleSlider(label: "Min length",
                       value: settings.minDurationSeconds == 0
                           ? "off"
                           : SeekLogic.format(Double(settings.minDurationSeconds)),
                       binding: $settings.int(\.minDurationSeconds),
                       range: 0...300,
                       step: 15)
            RuleSlider(label: "Max jump",
                       value: settings.maxTargetPercent == 0 ? "off" : "\(settings.maxTargetPercent)%",
                       binding: $settings.int(\.maxTargetPercent),
                       range: 0...100,
                       step: 5)
            Text("0 = off · unknown track lengths are never seeked")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("Min length skips short tracks; max jump keeps a jump away from the outro. "
                      + "A track with no known length — a live stream or an ad — is never seeked. "
                      + "0 turns a guardrail off.")
        }
    }
}

// MARK: - Panel

struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nowPlaying: NowPlayingStore
    @ObservedObject var status: StatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            Divider()
            nowPlayingSection
            if let hint = model.hintMessage { note(hint, color: .orange) }
            if let error = model.errorMessage { note(error, color: .red) }
            Divider()
            targetSection
            Divider()
            guardrailSection
            Divider()
            ignoreSection
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 380)
        // The reader keeps pushing ~10 Hz values into `nowPlaying`; mirror them
        // only while the panel is actually on screen.
        .onAppear { model.panelAppeared() }
        .onDisappear { model.panelDisappeared() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.enabled ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text("Song Seeker")
                .font(.headline)
            Spacer()
            Button(status.enabled ? "Turn Off" : "Turn On") { model.toggleEnabled() }
                .controlSize(.small)
        }
    }

    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Now playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Jump now") { model.jumpNow() }
                    .controlSize(.small)
                    .disabled(!status.enabled || !nowPlaying.hasTrack)
                    .help(jumpNowHelp)
            }
            if nowPlaying.hasTrack {
                Text(nowPlaying.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(performer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                TrackMeter(elapsed: nowPlaying.elapsed,
                           duration: nowPlaying.duration,
                           marker: nowPlaying.marker,
                           band: nowPlaying.band)
                HStack(spacing: 6) {
                    Text(position)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(jump)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No media playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(model.statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(model.statusText)
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jump target")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Mode", selection: $model.settings.mode) {
                ForEach(Prefs.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch model.settings.mode {
            case .absolute:
                RuleSlider(label: "Seconds into the song",
                           value: SeekLogic.format(Double(model.settings.absoluteSeconds)),
                           binding: $model.settings.int(\.absoluteSeconds),
                           range: 0...max(600, Double(model.settings.absoluteSeconds)),
                           step: 5)
            case .relative:
                RuleSlider(label: "Percent into the song",
                           value: "\(model.settings.relativePercent)%",
                           binding: $model.settings.int(\.relativePercent),
                           range: 1...99,
                           step: 1)
            case .random:
                RuleSlider(label: "From",
                           value: "\(model.settings.randomMin)%",
                           binding: $model.settings.int(\.randomMin),
                           range: 1...99,
                           step: 1)
                RuleSlider(label: "To",
                           value: "\(model.settings.randomMax)%",
                           binding: $model.settings.int(\.randomMax),
                           range: 1...99,
                           step: 1)
            }

            Toggle("Also seek on natural end", isOn: $model.settings.seekOnAutoNext)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var guardrailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Guardrails")
                .font(.caption)
                .foregroundStyle(.secondary)
            GuardrailForm(settings: $model.settings)
        }
    }

    /// The deny-list: the one place Song Seeker looks at *which* app owns the
    /// session rather than what it is playing.
    private var ignoreSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ignore players")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.seenPlayers.isEmpty {
                Text("Nothing seen yet — play something and it shows up here.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                // Deliberately not a ScrollView: a menu bar window that cannot be
                // as tall as the panel squeezes the only flexible view to zero,
                // which made this list vanish instead of scrolling.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.seenPlayers.prefix(4)), id: \.self) { player in
                        ignoreRow(player)
                    }
                }
            }

            Text("Ticked players are ignored entirely.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("A ticked player is never jumped, and its sessions stay out of the "
                      + "baseline — so a browser tab cannot yank the song that is playing.")
        }
    }

    private func ignoreRow(_ player: String) -> some View {
        HStack(spacing: 6) {
            // A labelled checkbox: the whole row reads as one control, rather
            // than a small box floating next to some text.
            Toggle(player, isOn: Binding(get: { model.isIgnored(player) },
                                         set: { model.setIgnored($0, forPlayer: player) }))
                .toggleStyle(.checkbox)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.isIgnored(player)
                      ? "Never jump anything published by \(player)"
                      : "Leave \(player) alone")
            if player == model.activePlayer {
                Text("playing now")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.infoLines, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A title can be arbitrarily long; keep it from stretching the panel.
            Text("Last jump: \(model.lastJumpText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .help("Last jump: \(model.lastJumpText)")
            HStack {
                Button("Log") { model.revealLog() }
                    .controlSize(.small)
                Spacer()
                Button("Quit Song Seeker") { model.quit() }
                    .controlSize(.small)
            }
            .padding(.top, 2)
        }
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Why "Jump now" cannot be pressed, said before it is pressed rather than
    /// after — a silent refusal was the whole problem with the first version.
    private var jumpNowHelp: String {
        if !status.enabled { return "Turn seek on first — the master switch is off" }
        if !nowPlaying.hasTrack { return "Nothing is playing" }
        return "Apply the rule to the song already playing — ignores the dedup and the min-length guardrail"
    }

    private var performer: String {
        [nowPlaying.artist, nowPlaying.app]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var position: String {
        guard nowPlaying.duration > 0 else { return SeekLogic.format(nowPlaying.elapsed) }
        return "\(SeekLogic.format(nowPlaying.elapsed)) / \(SeekLogic.format(nowPlaying.duration))"
    }

    private var jump: String {
        if let marker = nowPlaying.marker {
            return "jump → \(SeekLogic.format(marker))"
        }
        if let band = nowPlaying.band {
            return "jump \(SeekLogic.format(band.lowerBound))–\(SeekLogic.format(band.upperBound))"
        }
        return ""
    }
}
