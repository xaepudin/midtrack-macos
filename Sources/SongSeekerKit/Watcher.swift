import Foundation

/// Decides when a track change deserves a seek.
///
/// The rules mirror the Android app: baseline whatever is playing at launch, wait
/// for a length before jumping, never seek the same track twice, honour the
/// guardrails and per-player rules, and only trust a position that clearly
/// belongs to the new track.
public final class Watcher {
    public typealias Snapshot = JXAReader.Snapshot

    /// Called after a successful jump.
    public var onSeek: ((String, Double) -> Void)?
    /// Human-readable narration of every decision, shown in the panel and logged.
    public var onState: ((String) -> Void)?

    /// Injected so tests can observe the decisions without touching the real
    /// private API, the clock or the user's preferences.
    public var seek: (Double) -> Bool = { MediaRemote.seek(to: $0) }
    public var settings: () -> SeekSettings = { .current }
    public var isEnabled: () -> Bool = { Prefs.enabled }
    public var ignoresPlayer: (String?) -> Bool = { Prefs.ignoresPlayer($0) }
    public var now: () -> Date = Date.init
    public var recordJump: (String, Double) -> Void = { title, target in
        Prefs.lastJumpTitle = title
        Prefs.lastJumpAt = target
    }

    /// Reader ticks without media before the baseline is dropped. At the reader's
    /// ~0.15 s effective cadence, 30 ticks is roughly 4.5 s of real silence.
    public var noMediaResetTicks = 30
    /// How far past the target a trusted position may be before a manual skip is
    /// left alone instead of being yanked backwards.
    public var pastMargin: TimeInterval = 5
    /// The same track is not jumped twice inside this window (Android uses the
    /// same 30 s). It catches a track change reported twice a moment apart — a
    /// session handed back and forth is dealt with by the ignore list and by the
    /// position guard, not by remembering every track ever jumped to.
    public var dedupWindow: TimeInterval = 30

    private var lastKey: String?
    private var lastElapsed = 0.0
    private var lastDuration = 0.0
    private var pendingKey: String?
    private var pendingAutoNext = false
    private var pendingPreviousPosition = 0.0
    private var noMediaStreak = 0
    private var ignoredPlayer: String?
    private var lastSeekKey: String?
    private var lastSeekAt = Date.distantPast
    private var baselineTitle: String?
    private var baselineAt = Date.distantPast

    /// A metadata re-post carrying the same title this soon after the baseline is
    /// the same track, not a new one. Players publish a half-populated snapshot
    /// first (title before artist, or a provisional length), and the next line
    /// used to look like a brand-new track — which is how a jump could land a
    /// fifth of a second after launch. Android absorbs the same 3 s window.
    public var baselineAbsorbWindow: TimeInterval = 3

    public init() {}

    public func tick(_ snapshot: Snapshot?) {
        guard let snapshot, let key = snapshot.identity else {
            // Players (Chrome especially) briefly drop their now-playing session
            // during track transitions. Do not reset the baseline on transient
            // gaps — only after a few seconds of silence, so that the next track
            // still counts as a change and gets its jump.
            noMediaStreak += 1
            if noMediaStreak == 1, lastKey != nil {
                onState?("No media… (keeping baseline)")
            }
            if noMediaStreak >= noMediaResetTicks {
                if lastKey != nil { onState?("No media playing (baseline reset)") }
                lastKey = nil
                pendingKey = nil
                baselineTitle = nil
            }
            return
        }

        noMediaStreak = 0
        let appLabel = snapshot.app ?? ""

        // On the deny-list: ignore the session outright, and deliberately without
        // touching the baseline. That is what keeps a browser tab's video from
        // becoming the track we came from — and so from making the song that is
        // still playing look like a brand-new one when the session returns.
        guard !ignoresPlayer(snapshot.app) else {
            if ignoredPlayer != snapshot.app {
                ignoredPlayer = snapshot.app
                onState?("Ignoring \(snapshot.app ?? "a session with no player name") — on the ignore list")
            }
            return
        }
        ignoredPlayer = nil

        // A track that appeared before its length was known: judge it as soon as
        // the length shows up.
        if let pendingKey, pendingKey == key, SeekLogic.hasLength(snapshot.duration) {
            self.pendingKey = nil
            doSeek(snapshot, autoNext: pendingAutoNext, previousPosition: pendingPreviousPosition)
            return
        }

        guard let previous = lastKey else {
            // Baseline — never jump the track that was already playing at launch.
            lastKey = key
            lastElapsed = snapshot.elapsed
            lastDuration = snapshot.duration
            baselineTitle = snapshot.title
            baselineAt = now()
            onState?("Watching \(appLabel) · \(snapshot.title ?? "") (baseline)")
            return
        }

        if key == previous {
            lastElapsed = snapshot.elapsed
            if snapshot.duration > 0 { lastDuration = snapshot.duration }
            return
        }

        // Absorb a re-post of the baseline track, the way Android does: same
        // title, moments after the baseline — the identity churned (the artist
        // showed up, the length was corrected), the track did not change.
        if snapshot.title == baselineTitle, now().timeIntervalSince(baselineAt) < baselineAbsorbWindow {
            lastKey = key
            lastElapsed = snapshot.elapsed
            lastDuration = snapshot.duration
            onState?("Same track re-posted right after the baseline — absorbing (\(snapshot.title ?? ""))")
            return
        }

        // Track change. A track that ended on its own is judged differently from
        // one the user skipped away from.
        let autoNext = lastDuration > 0 && lastElapsed >= lastDuration - 3.0
        let previousPosition = lastElapsed
        if !SeekLogic.hasLength(snapshot.duration) {
            pendingKey = key
            pendingAutoNext = autoNext
            pendingPreviousPosition = previousPosition
            lastKey = key
            lastElapsed = snapshot.elapsed
            onState?("Track change: \(snapshot.title ?? "?") (waiting for duration)")
            return
        }
        lastKey = key
        doSeek(snapshot, autoNext: autoNext, previousPosition: previousPosition)
    }

    /// The panel's "Jump now": applies the rule to the song already playing, the
    /// way the Android app's notification button does.
    ///
    /// The minimum-length guardrail and the per-track dedup are deliberately
    /// bypassed — pressing the button is an explicit "do it anyway" — but a track
    /// with no known length is still refused, because no target can stay clear of
    /// the end. Returns the narration it posted.
    @discardableResult
    public func jumpNow(_ snapshot: Snapshot?) -> String {
        guard let snapshot, let key = snapshot.identity, let title = snapshot.title else {
            return "Nothing is playing."
        }
        guard isEnabled() else { return "Seek is off." }
        guard !ignoresPlayer(snapshot.app) else {
            return "\(snapshot.app ?? "That player") is on the ignore list."
        }
        guard SeekLogic.hasLength(snapshot.duration) else {
            return "No jump: track length unknown (live stream, ad, or no duration metadata)"
        }
        var rule = settings()
        rule.minDurationSeconds = 0
        guard let target = SeekLogic.computeTarget(duration: snapshot.duration, settings: rule) else {
            return "No jump: the rule has no usable target."
        }

        _ = seek(target)
        lastSeekKey = key
        lastSeekAt = now()
        recordJump(title, target)
        onSeek?(title, target)
        let message = "SEEK (manual) \(title) → \(SeekLogic.format(target)) "
            + "(dur \(Int(snapshot.duration))s, was \(Int(snapshot.elapsed))s)"
        onState?(message)
        return message
    }

    private func doSeek(_ snapshot: Snapshot, autoNext: Bool, previousPosition: Double) {
        guard let key = snapshot.identity else { return }
        let player = snapshot.app
        let title = snapshot.title ?? "?"

        // Master switch off: the baseline keeps tracking, so re-enabling mid-song
        // will not yank the current track — only the next change triggers a jump.
        guard isEnabled() else {
            remember(snapshot)
            onState?("Track change: \(title) — seek is off")
            return
        }

        let rule = settings()

        if autoNext, !rule.seekOnAutoNext {
            remember(snapshot)
            onState?("Track change: \(title) — auto-next seek is off")
            return
        }

        if let reason = SeekLogic.skipReason(duration: snapshot.duration, settings: rule) {
            remember(snapshot)
            onState?("Track change: \(title) — no jump: \(reason)")
            return
        }

        if key == lastSeekKey, now().timeIntervalSince(lastSeekAt) < dedupWindow {
            remember(snapshot)
            onState?("Track change: \(title) (dedup — already seeked)")
            return
        }

        guard let target = SeekLogic.computeTarget(duration: snapshot.duration, settings: rule) else {
            remember(snapshot)
            return
        }

        // "Already past the spot" — only for a manual skip, and only when the
        // position clearly belongs to the new track. A natural end leaves the
        // previous track's position behind and a paused skip leaves the pause
        // point, so in both cases the number says nothing about the new track.
        if !autoNext, positionBelongsToNewTrack(snapshot, previousPosition: previousPosition),
           snapshot.elapsed > target + pastMargin {
            remember(snapshot)
            onState?("Track change: \(title) — skip (already at \(Int(snapshot.elapsed))s > target \(Int(target))s)")
            return
        }

        _ = seek(target)
        lastSeekKey = key
        lastSeekAt = now()
        remember(snapshot)
        recordJump(title, target)
        onSeek?(title, target)
        onState?("SEEK \(title) → \(SeekLogic.format(target)) "
            + "(dur \(Int(snapshot.duration))s, was \(Int(snapshot.elapsed))s) [\(player ?? "")]")
    }

    /// Android's staleness test, expressed with the values MediaRemote gives us:
    /// a position that did not move since the change — or that does not fit inside
    /// the track at all — cannot be evidence that the new song is past the target.
    private func positionBelongsToNewTrack(_ snapshot: Snapshot, previousPosition: Double) -> Bool {
        guard snapshot.elapsed >= 0, snapshot.elapsed <= snapshot.duration else { return false }
        return abs(snapshot.elapsed - previousPosition) > 1
    }

    /// The position of the track that just changed becomes the baseline for
    /// deciding whether the *next* change was a natural end or a manual skip.
    private func remember(_ snapshot: Snapshot) {
        lastElapsed = snapshot.elapsed
        lastDuration = snapshot.duration
    }

}
