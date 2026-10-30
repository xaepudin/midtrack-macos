import AppKit
import MidtrackKit
import SwiftUI

extension View {
    /// A subtle raised surface used by the main window's cards. The menu bar
    /// panel deliberately stays flat and compact.
    func cardSurface(padding: CGFloat = 0, cornerRadius: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

struct InfoContent {
    let title: String
    let message: String
}

/// A visible ⓘ affordance. Clicking opens a popover; hovering also shows the
/// short title as a standard tooltip.
struct InfoButton: View {
    let title: String
    let message: String

    @State private var isShowing = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    Color.primary.opacity(isHovering ? 0.12 : 0.06),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("About \(title)")
        .accessibilityLabel("About \(title)")
        .accessibilityHint(message)
        .popover(isPresented: $isShowing, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 300, alignment: .leading)
        }
    }
}

/// One section title. Compact surfaces get the quiet caption style; the main
/// window gets a full headline with the icon.
struct SectionHeader: View {
    let title: String
    let systemImage: String
    var info: InfoContent? = nil
    var compact = true

    var body: some View {
        HStack(spacing: 6) {
            if compact {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            if let info {
                InfoButton(title: info.title, message: info.message)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A horizontal track-position meter: how far into the song playback is, plus
/// where the next jump lands — a marker for Time/Percent, a band for Random.
struct TrackMeter: View {
    let elapsed: Double
    let duration: Double
    let marker: Double?
    let band: ClosedRange<Double>?

    private var valueText: String {
        guard duration > 0 else { return SeekLogic.format(elapsed) }
        return "\(SeekLogic.format(elapsed)) / \(SeekLogic.format(duration))"
    }

    private var accessibilityValue: String {
        var parts = ["\(SeekLogic.format(elapsed)) of \(SeekLogic.format(duration))"]
        if let marker {
            parts.append("next jump at \(SeekLogic.format(marker))")
        } else if let band {
            parts.append("jump window \(SeekLogic.format(band.lowerBound)) to \(SeekLogic.format(band.upperBound))")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Pos")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    if let band {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.22))
                            .frame(width: max(1, width * fraction(band.upperBound - band.lowerBound)))
                            .offset(x: width * fraction(band.lowerBound))
                    }
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, width * fraction(elapsed)))
                    if let marker {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.orange)
                            .frame(width: 2, height: 10)
                            .offset(x: max(0, min(width - 2, width * fraction(marker))))
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            Text(valueText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Track position")
        .accessibilityValue(accessibilityValue)
        .help(band == nil
              ? "How far into the track playback is. The orange tick is where the next jump lands."
              : "How far into the track playback is. The shaded band is the window a random jump can land in.")
    }

    private func fraction(_ seconds: Double) -> Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, seconds / duration))
    }
}

struct StatusHeader: View {
    @ObservedObject var model: AppModel
    @ObservedObject var status: StatusStore
    var compact: Bool = false

    var body: some View {
        let content = HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(status.enabled ? Color.green.opacity(0.14) : Color.secondary.opacity(0.10))
                    .frame(width: 42, height: 42)
                Image(systemName: status.enabled ? "forward.end.circle.fill" : "forward.end.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(status.enabled ? Color.green : Color.secondary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Midtrack")
                    .font(.headline)
                if !compact {
                    Text("Skip to the good part — automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(status.enabled ? Color.green : Color.secondary.opacity(0.55))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(status.enabled ? "Running" : "Paused")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            // The label itself stays in the primary text colour so it keeps its
            // contrast on the translucent menu bar material; the dot and tint
            // carry the green/grey meaning.
            .foregroundStyle(.primary)
            .background(
                status.enabled ? Color.green.opacity(0.16) : Color.secondary.opacity(0.11),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    status.enabled ? Color.green.opacity(0.32) : Color.clear,
                    lineWidth: 1
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status")
            .accessibilityValue(status.enabled ? "Running" : "Paused")

            Button(status.enabled ? "Pause" : "Start") {
                model.toggleEnabled()
            }
            .controlSize(compact ? .small : .regular)
            .buttonStyle(.bordered)
            .tint(status.enabled ? .red : .accentColor)
            .accessibilityHint(status.enabled
                ? "Pauses jumping. Midtrack keeps watching tracks so resuming mid-song does not jump the wrong one."
                : "Starts jumping new tracks")
        }

        if compact {
            content
        } else {
            content.cardSurface(padding: 16)
        }
    }
}

struct NowPlayingSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nowPlaying: NowPlayingStore
    var compact: Bool = true

    var body: some View {
        let content = VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionHeader(title: "Now playing", systemImage: "music.note", compact: compact)
                Button("Jump now") { model.jumpNow() }
                    .controlSize(compact ? .small : .regular)
                    .disabled(!model.status.enabled || !nowPlaying.hasTrack)
                    .help(jumpNowHelp)
                    .accessibilityHint(jumpNowHelp)
            }

            if nowPlaying.hasTrack {
                Text(nowPlaying.title)
                    .font(compact ? .callout.weight(.medium) : .title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(nowPlaying.title)
                Text(performer)
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                TrackMeter(elapsed: nowPlaying.elapsed,
                           duration: nowPlaying.duration,
                           marker: nowPlaying.marker,
                           band: nowPlaying.band)
                HStack(spacing: 8) {
                    Text(model.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : 2)
                        .truncationMode(.tail)
                        .help(model.statusText)
                    Spacer(minLength: 0)
                    Text(jump)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No media playing")
                        .font(compact ? .callout : .title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Start something in any player — Midtrack picks it up from the system Now Playing session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if compact {
            content
        } else {
            content.cardSurface(padding: 16)
        }
    }

    /// Why "Jump now" cannot be pressed, said before it is pressed rather than
    /// after — a silent refusal was the whole problem with the first version.
    private var jumpNowHelp: String {
        if !model.status.enabled { return "Start Midtrack first — jumping is paused" }
        if !nowPlaying.hasTrack { return "Nothing is playing" }
        return "Apply the rule to the song already playing — ignores the dedup and the min-length guardrail"
    }

    private var performer: String {
        [nowPlaying.artist, nowPlaying.app]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
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

private extension Binding where Value == SeekSettings {
    /// A slider binding onto one integer field of the rule.
    func int(_ keyPath: WritableKeyPath<SeekSettings, Int>) -> Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue[keyPath: keyPath]) },
            set: { wrappedValue[keyPath: keyPath] = Int($0.rounded()) }
        )
    }

    /// The integer-valued form, for controls that work in whole percent.
    func integer(_ keyPath: WritableKeyPath<SeekSettings, Int>) -> Binding<Int> {
        Binding<Int>(
            get: { wrappedValue[keyPath: keyPath] },
            set: { wrappedValue[keyPath: keyPath] = $0 }
        )
    }
}

struct RuleSlider: View {
    let label: String
    let value: String
    let binding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let info: InfoContent
    var compact: Bool = true

    private var labelFont: Font {
        compact ? .caption.weight(.medium) : .subheadline.weight(.medium)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(labelFont)
                InfoButton(title: info.title, message: info.message)
                Spacer()
                Text(value)
                    .font(compact ? .caption.monospacedDigit() : .subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            // The binding snaps to `step`; the slider itself stays continuous so
            // macOS does not draw a tick mark for every integer.
            Slider(value: snapped, in: range)
                .help(info.message)
                .accessibilityLabel(label)
                .accessibilityValue(value)
        }
    }

    private var snapped: Binding<Double> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                let stepped = (newValue / step).rounded() * step
                binding.wrappedValue = min(max(stepped, range.lowerBound), range.upperBound)
            }
        )
    }
}

/// A two-thumb slider for the random window. SwiftUI's `Slider` is
/// single-value, so this draws one track with two draggable thumbs. The handles
/// may cross each other; the window is always the ordered range between them.
struct PercentRangeSlider: View {
    @Binding var start: Int
    @Binding var end: Int
    var tint: Color = .accentColor

    private let bounds = 1...99
    private let thumbSize: CGFloat = 22
    private let trackHeight: CGFloat = 4
    private let spaceName = "percentRangeSlider"

    var body: some View {
        GeometryReader { geometry in
            let usable = max(1, geometry.size.width - thumbSize)
            let startX = thumbSize / 2 + usable * fraction(start)
            let endX = thumbSize / 2 + usable * fraction(end)
            let lowX = min(startX, endX)
            let highX = max(startX, endX)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)

                Capsule()
                    .fill(tint)
                    .frame(width: max(0, highX - lowX), height: trackHeight)
                    .offset(x: lowX)

                thumb(at: startX, isStart: true, usable: usable)
                thumb(at: endX, isStart: false, usable: usable)
            }
            .coordinateSpace(name: spaceName)
        }
        .frame(height: thumbSize)
        .accessibilityElement(children: .contain)
        .help("Drag either handle. They may cross; the window is the range between them.")
    }

    private func thumb(at x: CGFloat, isStart: Bool, usable: CGFloat) -> some View {
        let value = isStart ? start : end
        let other = isStart ? end : start
        let role = value <= other ? "lower" : "upper"

        return Circle()
            .fill(.white)
            .overlay(
                Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .frame(width: thumbSize, height: thumbSize)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .offset(x: x - thumbSize / 2)
            .gesture(dragGesture(isStart: isStart, usable: usable))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Random window \(role) bound")
            .accessibilityValue("\(value) percent")
            .accessibilityHint("Drag or adjust to move this handle; handles may cross")
            .accessibilityAdjustableAction { direction in
                adjust(isStart: isStart, by: direction == .increment ? 1 : -1)
            }
    }

    private func dragGesture(isStart: Bool, usable: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(spaceName))
            .onChanged { drag in
                let value = value(at: drag.location.x, usable: usable)
                if isStart {
                    if value != start { start = value }
                } else if value != end {
                    end = value
                }
            }
    }

    private func value(at x: CGFloat, usable: CGFloat) -> Int {
        let x = min(max(x - thumbSize / 2, 0), usable)
        let span = CGFloat(bounds.upperBound - bounds.lowerBound)
        let stepped = Int((x / usable * span).rounded()) + bounds.lowerBound
        return min(max(stepped, bounds.lowerBound), bounds.upperBound)
    }

    private func adjust(isStart: Bool, by delta: Int) {
        if isStart {
            start = min(max(start + delta, bounds.lowerBound), bounds.upperBound)
        } else {
            end = min(max(end + delta, bounds.lowerBound), bounds.upperBound)
        }
    }

    private func fraction(_ value: Int) -> CGFloat {
        let span = CGFloat(bounds.upperBound - bounds.lowerBound)
        let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
        return CGFloat(clamped - bounds.lowerBound) / span
    }
}

struct PercentRangeRow: View {
    @Binding var start: Int
    @Binding var end: Int
    let info: InfoContent
    var compact = true

    private var lower: Int { min(start, end) }
    private var upper: Int { max(start, end) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Random window")
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                InfoButton(title: info.title, message: info.message)
                Spacer()
                Text("\(lower)% – \(upper)%")
                    .font(compact ? .caption.monospacedDigit() : .subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            PercentRangeSlider(start: $start, end: $end)
        }
    }
}

struct JumpTargetSection: View {
    @ObservedObject var model: AppModel
    var compact: Bool = true

    private let modeInfo = InfoContent(
        title: "Jump target",
        message: "Where every new track starts. Time jumps to a fixed offset, Percent lands at a "
            + "fraction of the track, and Random picks a fresh spot inside a window for every song."
    )

    var body: some View {
        let content = VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            SectionHeader(title: "Jump target", systemImage: "forward.end", info: modeInfo, compact: compact)

            Picker("Mode", selection: $model.settings.mode) {
                ForEach(Prefs.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(compact ? .regular : .large)
            .accessibilityLabel("Jump mode")

            switch model.settings.mode {
            case .absolute:
                RuleSlider(
                    label: "Seconds into the song",
                    value: SeekLogic.format(Double(model.settings.absoluteSeconds)),
                    binding: $model.settings.int(\.absoluteSeconds),
                    range: 0...max(600, Double(model.settings.absoluteSeconds)),
                    step: 5,
                    info: InfoContent(
                        title: "Seconds into the song",
                        message: "A fixed number of seconds from the start of every track."
                    ),
                    compact: compact
                )
            case .relative:
                RuleSlider(
                    label: "Percent into the song",
                    value: "\(model.settings.relativePercent)%",
                    binding: $model.settings.int(\.relativePercent),
                    range: 1...99,
                    step: 1,
                    info: InfoContent(
                        title: "Percent into the song",
                        message: "Jumps to the same fraction of every track, so a long song and a "
                            + "short one both start at the same point in their shape."
                    ),
                    compact: compact
                )
            case .random:
                PercentRangeRow(
                    start: $model.settings.integer(\.randomMin),
                    end: $model.settings.integer(\.randomMax),
                    info: InfoContent(
                        title: "Random window",
                        message: "Random picks a fresh spot inside this window for every track. "
                            + "Drag either handle; they may cross, and the window is always the "
                            + "range between them."
                    ),
                    compact: compact
                )
            }

            HStack(spacing: 6) {
                Toggle("Also seek on natural end", isOn: $model.settings.seekOnAutoNext)
                    .toggleStyle(.switch)
                    .controlSize(compact ? .small : .regular)
                    .help("Off = only seek tracks you skipped to. Tracks that ended by themselves are left alone.")
                    .accessibilityHint("Off only seeks tracks you skipped to; tracks that ended by themselves are left alone")
                InfoButton(
                    title: "Natural end",
                    message: "Off means only songs you skipped away from are jumped. A track that played "
                        + "to the end on its own is left alone."
                )
            }

            if !compact {
                Text("The first track Midtrack sees is a baseline and is never jumped.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if compact {
            content
        } else {
            content.cardSurface(padding: 16)
        }
    }
}

struct GuardrailsSection: View {
    @ObservedObject var model: AppModel
    var compact: Bool = true

    static let info = InfoContent(
        title: "Guardrails",
        message: "Min length skips short items — an ad, a jingle, a 26-second video in a browser "
            + "tab. Max jump keeps a jump away from the outro. A track with no known length is "
            + "never jumped. Off by default; turning this on applies both limits."
    )

    var body: some View {
        let content = VStack(alignment: .leading, spacing: compact ? 8 : 16) {
            SectionHeader(title: "Guardrails", systemImage: "shield.lefthalf.filled",
                          info: Self.info, compact: compact)

            HStack(spacing: 6) {
                Toggle("Enable guardrails", isOn: $model.settings.guardrailsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(compact ? .small : .regular)
                    .help("Applies Min length and Max jump. Off by default.")
                    .accessibilityHint("Turns the min length and max jump limits on or off")
                InfoButton(
                    title: "Enable guardrails",
                    message: "When off, Min length and Max jump are ignored and their sliders cannot "
                        + "be changed. A track with no known length is still never jumped."
                )
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: compact ? 8 : 16) {
                RuleSlider(
                    label: "Min length",
                    value: model.settings.minDurationSeconds == 0
                        ? "off"
                        : SeekLogic.format(Double(model.settings.minDurationSeconds)),
                    binding: $model.settings.int(\.minDurationSeconds),
                    range: 0...300,
                    step: 15,
                    info: InfoContent(
                        title: "Min length",
                        message: "Nothing shorter than this is jumped. It keys on the track's length, "
                            + "not on which app is playing. 0 turns it off."
                    ),
                    compact: compact
                )

                RuleSlider(
                    label: "Max jump",
                    value: model.settings.maxTargetPercent == 0 ? "off" : "\(model.settings.maxTargetPercent)%",
                    binding: $model.settings.int(\.maxTargetPercent),
                    range: 0...100,
                    step: 5,
                    info: InfoContent(
                        title: "Max jump",
                        message: "Never land past this percent of a track, so a long jump cannot drop "
                            + "you into the outro. 0 turns it off."
                    ),
                    compact: compact
                )
            }
            .disabled(!model.settings.guardrailsEnabled)
            .opacity(model.settings.guardrailsEnabled ? 1 : 0.42)

            Text(model.settings.guardrailsEnabled
                ? "0 = off · unknown track lengths are never jumped"
                : "Off — limits below are ignored · unknown lengths still skipped")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if compact {
            content
        } else {
            content.cardSurface(padding: 16)
        }
    }
}

struct PlayersSection: View {
    @ObservedObject var model: AppModel
    var compact: Bool = true
    var showsHeading: Bool = true

    static let info = InfoContent(
        title: "Players to ignore",
        message: "Ticked = ignored. Midtrack never jumps a ticked player's tracks, and that "
            + "player's session never becomes the baseline — so a browser tab or a video cannot "
            + "disturb the song that is playing. Unticked = jumped normally."
    )

    var body: some View {
        let content = VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            if showsHeading {
                SectionHeader(title: "Players to ignore", systemImage: "person.wave.2",
                              info: Self.info, compact: compact)
            }

            if compact || showsHeading {
                Text(compact
                    ? "Ticked = ignored (never jumped, never the baseline) · unticked = jumped."
                    : "Ticked = ignored: Midtrack never jumps that player's tracks, and its session "
                        + "never becomes the baseline. Unticked = jumped normally.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.seenPlayers.isEmpty {
                Text("Nothing seen yet — play something and it shows up here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: compact ? 2 : 6) {
                    ForEach(Array(model.seenPlayers.prefix(compact ? 6 : 24)), id: \.self) { player in
                        row(player)
                    }
                }
                if compact, model.seenPlayers.count > 6 {
                    Text("+\(model.seenPlayers.count - 6) more — open Midtrack for the full list.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if compact {
            content
        } else {
            content.cardSurface(padding: 16)
        }
    }

    private func row(_ player: String) -> some View {
        let ignored = model.isIgnored(player)
        var tags: [String] = []
        if player == model.activePlayer { tags.append("playing now") }
        if ignored { tags.append("ignored") }

        return HStack(spacing: 8) {
            Toggle(player, isOn: Binding(get: { model.isIgnored(player) },
                                         set: { model.setIgnored($0, forPlayer: player) }))
                .toggleStyle(.checkbox)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(ignored
                      ? "This player is ignored: Midtrack leaves its tracks alone. Click to jump them again."
                      : "This player is jumped normally. Click to ignore it.")
                .accessibilityHint(ignored
                    ? "Ignored: Midtrack leaves this player's tracks alone"
                    : "Jumped: Midtrack may jump this player's tracks")
            if !tags.isEmpty {
                Text(tags.joined(separator: " · "))
                    .font(.caption2.weight(.medium))
                    // Primary text keeps "ignored" legible on the orange tint;
                    // the tint and border carry the warning colour.
                    .foregroundStyle(ignored ? Color.primary : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        ignored ? Color.orange.opacity(0.16) : Color.secondary.opacity(0.10),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            ignored ? Color.orange.opacity(0.38) : Color.clear,
                            lineWidth: 1
                        )
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

struct StatusMessages: View {
    @ObservedObject var model: AppModel
    var compact: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if let hint = model.hintMessage {
                message(icon: "exclamationmark.triangle.fill", tint: .orange, text: hint)
            }
            if let error = model.errorMessage {
                message(icon: "xmark.octagon.fill", tint: .red, text: error)
            }
        }
    }

    @ViewBuilder private func message(icon: String, tint: Color, text: String) -> some View {
        let content = HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(compact ? tint : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                Button("Open Log") { model.openLog() }
                    .controlSize(.small)
                    .accessibilityHint("Opens Midtrack's log in the default text editor")
            }
            Spacer(minLength: 0)
        }

        if compact {
            content
        } else {
            content.cardSurface(padding: 14)
        }
    }
}

struct InfoFooter: View {
    @ObservedObject var model: AppModel
    var compact: Bool = true

    var body: some View {
        let lines = compact ? Array(model.infoLines.prefix(2)) : model.infoLines
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(compact ? .caption2 : .caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Last jump: \(model.lastJumpText)")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .help("Last jump: \(model.lastJumpText)")
        }
    }
}

/// The shared control surface used by both the menu bar panel and the main
/// window. Keeping one implementation means the two entry points cannot drift
/// apart in behaviour or accessibility.
struct MidtrackControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nowPlaying: NowPlayingStore
    @ObservedObject var status: StatusStore
    var compact: Bool = true

    var body: some View {
        Group {
            if compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusHeader(model: model, status: status, compact: true)
            Divider()
            NowPlayingSection(model: model, nowPlaying: nowPlaying, compact: true)
            Divider()
            JumpTargetSection(model: model, compact: true)
            Divider()
            PlayersSection(model: model, compact: true)
            StatusMessages(model: model, compact: true)
            Divider()
            InfoFooter(model: model, compact: true)
        }
    }

    private var regularLayout: some View {
        VStack(spacing: 16) {
            StatusHeader(model: model, status: status, compact: false)
            NowPlayingSection(model: model, nowPlaying: nowPlaying, compact: false)
            JumpTargetSection(model: model, compact: false)
            GuardrailsSection(model: model, compact: false)
            StatusMessages(model: model, compact: false)
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Status", systemImage: "info.circle", compact: false)
                InfoFooter(model: model, compact: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 16)
        }
    }
}
