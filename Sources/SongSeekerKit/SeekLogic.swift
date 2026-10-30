import Foundation

/// The values that decide where a track is jumped to.
///
/// Everything except the master switch lives here, so a single player can carry
/// its own copy of the whole rule (the Android app's per-app rules) without any
/// special cases in the seek logic.
public struct SeekSettings: Equatable {
    public var mode: Prefs.Mode
    public var absoluteSeconds: Int
    public var relativePercent: Int
    public var randomMin: Int
    public var randomMax: Int
    public var seekOnAutoNext: Bool
    /// Skip tracks shorter than this many seconds. 0 turns the guardrail off.
    public var minDurationSeconds: Int
    /// Never jump past this percent of the track. 0 turns the guardrail off.
    public var maxTargetPercent: Int

    public init(mode: Prefs.Mode,
                absoluteSeconds: Int,
                relativePercent: Int,
                randomMin: Int,
                randomMax: Int,
                seekOnAutoNext: Bool = true,
                minDurationSeconds: Int = 0,
                maxTargetPercent: Int = 0) {
        self.mode = mode
        self.absoluteSeconds = absoluteSeconds
        self.relativePercent = relativePercent
        self.randomMin = randomMin
        self.randomMax = randomMax
        self.seekOnAutoNext = seekOnAutoNext
        self.minDurationSeconds = minDurationSeconds
        self.maxTargetPercent = maxTargetPercent
    }

    /// The global default rule, as configured in the panel.
    public static var current: SeekSettings { Prefs.settings }

    /// The random window as a percentage range, always ordered and in bounds.
    public var window: ClosedRange<Int> {
        let low = clamp(min(randomMin, randomMax), 1...99)
        return low...clamp(max(randomMin, randomMax), low...99)
    }

    /// " · >1:30, ≤80%" — the guardrails in force, or "" when both are off.
    public var guardrailSummary: String {
        var parts: [String] = []
        if minDurationSeconds > 0 { parts.append(">\(SeekLogic.format(Double(minDurationSeconds)))") }
        if (1...99).contains(maxTargetPercent) { parts.append("≤\(maxTargetPercent)%") }
        return parts.isEmpty ? "" : " · " + parts.joined(separator: ", ")
    }
}

/// Where to jump. Kept free of any media plumbing so it can be tested directly.
///
/// Three guardrails borrowed from the Android app stop a jump from ruining a
/// song: a minimum length, a ceiling on how far in a jump may land, and the rule
/// that a track whose length is unknown is never touched — a live stream, an ad
/// or a video clip has no "safe spot" to aim at.
public enum SeekLogic {
    /// A track needs a usable length before anything can be aimed at.
    public static func hasLength(_ duration: Double) -> Bool { duration > 1 }

    /// Why this track gets no jump at all, or `nil` when it is a candidate. The
    /// watcher narrates this, so "nothing happened" is always explainable.
    public static func skipReason(duration: Double, settings: SeekSettings) -> String? {
        guard hasLength(duration) else {
            return "track length unknown (live stream, ad, or no duration metadata)"
        }
        if settings.minDurationSeconds > 0, duration < Double(settings.minDurationSeconds) {
            return "track is \(format(duration)) — shorter than the "
                + "\(format(Double(settings.minDurationSeconds))) minimum"
        }
        return nil
    }

    /// The target offset for a track of `duration` seconds, or `nil` when the
    /// guardrails rule the track out.
    ///
    /// `randomPercent` is injectable so tests can pin the random draw.
    public static func computeTarget(duration: Double,
                                     settings: SeekSettings = .current,
                                     randomPercent: Int? = nil) -> Double? {
        guard skipReason(duration: duration, settings: settings) == nil else { return nil }
        let target: Double
        switch settings.mode {
        case .absolute:
            target = Double(clamp(settings.absoluteSeconds, 1...7200))
        case .relative:
            target = duration * Double(clamp(settings.relativePercent, 1...99)) / 100
        case .random:
            let window = settings.window
            let pick = randomPercent.map { clamp($0, window) } ?? Int.random(in: window)
            target = duration * Double(pick) / 100
        }
        guard target.isFinite, target > 0 else { return nil }
        // Never the very end, and never past the user's ceiling.
        var ceiling = duration - 2
        if (1...99).contains(settings.maxTargetPercent) {
            ceiling = min(ceiling, duration * Double(settings.maxTargetPercent) / 100)
        }
        return min(max(target, 0.5), max(ceiling, 1))
    }

    /// `m:ss`, the same shape the original menu used.
    public static func format(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// "20%" / "1:30" / "random 15–60%" — one short label for every surface.
    public static func modeLabel(_ settings: SeekSettings) -> String {
        switch settings.mode {
        case .absolute: return format(Double(clamp(settings.absoluteSeconds, 1...7200)))
        case .relative: return "\(clamp(settings.relativePercent, 1...99))%"
        case .random:
            let window = settings.window
            return "random \(window.lowerBound)–\(window.upperBound)%"
        }
    }

    /// One-line summary of the active rule for the panel footer.
    public static func describe(_ settings: SeekSettings) -> String {
        switch settings.mode {
        case .absolute:
            return "Time · jump to \(format(Double(clamp(settings.absoluteSeconds, 1...7200))))"
        case .relative:
            return "Percent · jump to \(clamp(settings.relativePercent, 1...99))% of the track"
        case .random:
            let window = settings.window
            return "Random · jump somewhere between \(window.lowerBound)% and \(window.upperBound)%"
        }
    }
}

/// Shared bounds helper.
func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
    min(max(value, range.lowerBound), range.upperBound)
}
