import Foundation

/// Persisted settings for Midtrack's rule, ignore list, and last jump.
public enum Prefs {
    public enum Mode: String, CaseIterable, Identifiable {
        case absolute
        case relative
        case random

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .absolute: return "Time"
            case .relative: return "Percent"
            case .random: return "Random"
            }
        }
    }

    public static let suiteName = "com.xaepudin.midtrack"

    /// Swappable so the test suite writes to a throwaway domain instead of the
    /// real preferences of whoever runs the tests.
    static var store: UserDefaults = {
        // The app's own bundle identifier is already the standard domain; asking
        // UserDefaults for it as a suite is rejected by Foundation.
        if Bundle.main.bundleIdentifier == suiteName { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }()

    /// Copies the preferences of the previous bundle identifier
    /// (`com.asep.midtrack`) into this one on first launch. The identifier is
    /// the only thing that changed, so the rule, ignore list, onboarding state,
    /// and window frame should survive the move.
    public static func migratePreviousBundleIdentifierIfNeeded() {
        let marker = "migratedFromPreviousBundleIdentifier"
        guard !store.bool(forKey: marker) else { return }
        store.set(true, forKey: marker)
        guard store.object(forKey: Key.enabled) == nil else { return }

        let previous = "com.asep.midtrack"
        guard let legacy = UserDefaults(suiteName: previous),
              let domain = legacy.persistentDomain(forName: previous) else { return }
        for (key, value) in domain where store.object(forKey: key) == nil {
            store.set(value, forKey: key)
        }
    }

    /// Guardrail defaults, the same as the Android app. They only apply while
    /// `guardrailsEnabled` is on.
    public static let defaultMinDurationSeconds = 90
    public static let defaultMaxTargetPercent = 80

    private enum Key {
        static let enabled = "enabled"
        static let mode = "mode"
        static let absoluteSeconds = "absoluteSeconds"
        static let relativePercent = "relativePercent"
        static let randomMin = "randomMin"
        static let randomMax = "randomMax"
        static let seekOnAutoNext = "seekOnAutoNext"
        static let guardrailsEnabled = "guardrailsEnabled"
        static let minDurationSeconds = "minDurationSeconds"
        static let maxTargetPercent = "maxTargetPercent"
        static let lastJumpTitle = "lastJumpTitle"
        static let lastJumpAt = "lastJumpAt"
        static let ignoredPlayers = "ignoredPlayers"
        static let seenPlayers = "seenPlayers"
    }

    /// Master switch. When off the watcher still tracks track changes so that
    /// re-enabling mid-song does not yank the track that is playing.
    public static var enabled: Bool {
        get { store.object(forKey: Key.enabled) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.enabled) }
    }

    public static var mode: Mode {
        get { Mode(rawValue: store.string(forKey: Key.mode) ?? "") ?? .relative }
        set { store.set(newValue.rawValue, forKey: Key.mode) }
    }

    /// Fixed offset from the start of a track, in seconds.
    public static var absoluteSeconds: Int {
        get { integer(Key.absoluteSeconds, fallback: 120, range: 1...7200) }
        set { store.set(clamp(newValue, 1...7200), forKey: Key.absoluteSeconds) }
    }

    /// Fraction of the track to jump to.
    public static var relativePercent: Int {
        get { integer(Key.relativePercent, fallback: 20, range: 1...99) }
        set { store.set(clamp(newValue, 1...99), forKey: Key.relativePercent) }
    }

    /// Window the random mode picks from, as percentages of the track.
    public static var randomMin: Int {
        get { integer(Key.randomMin, fallback: 15, range: 1...99) }
        set { store.set(clamp(newValue, 1...99), forKey: Key.randomMin) }
    }

    public static var randomMax: Int {
        get { integer(Key.randomMax, fallback: 60, range: 1...99) }
        set { store.set(clamp(newValue, 1...99), forKey: Key.randomMax) }
    }

    /// Whether a track that ended by itself is seeked too, or only tracks the
    /// user skipped to.
    public static var seekOnAutoNext: Bool {
        get { store.object(forKey: Key.seekOnAutoNext) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.seekOnAutoNext) }
    }

    /// Whether Min length and Max jump are applied at all. Off by default: a
    /// fresh install jumps every track of known length, and the guardrails are
    /// opt-in. The values below are kept while the switch is off, so turning it
    /// back on restores the previous limits.
    public static var guardrailsEnabled: Bool {
        get { store.object(forKey: Key.guardrailsEnabled) as? Bool ?? false }
        set { store.set(newValue, forKey: Key.guardrailsEnabled) }
    }

    /// Skip anything shorter than this. 0 turns the guardrail off.
    public static var minDurationSeconds: Int {
        get { integer(Key.minDurationSeconds, fallback: defaultMinDurationSeconds, range: 0...7200) }
        set { store.set(clamp(newValue, 0...7200), forKey: Key.minDurationSeconds) }
    }

    /// Never jump past this percent of a track. 0 turns the guardrail off.
    public static var maxTargetPercent: Int {
        get { integer(Key.maxTargetPercent, fallback: defaultMaxTargetPercent, range: 0...100) }
        set { store.set(clamp(newValue, 0...100), forKey: Key.maxTargetPercent) }
    }

    public static var lastJumpTitle: String? {
        get { store.string(forKey: Key.lastJumpTitle) }
        set { store.set(newValue, forKey: Key.lastJumpTitle) }
    }

    public static var lastJumpAt: Double {
        get { store.object(forKey: Key.lastJumpAt) as? Double ?? 0 }
        set { store.set(newValue, forKey: Key.lastJumpAt) }
    }

    // MARK: - Which players to leave alone

    /// Players whose sessions are never touched: nothing they publish is jumped,
    /// and — just as important — a session from one of them cannot become the
    /// baseline, so it cannot make the song that is playing look like a new track
    /// when the session comes back.
    public static var ignoredPlayers: Set<String> {
        get { Set(store.stringArray(forKey: Key.ignoredPlayers) ?? []) }
        set { store.set(Array(newValue).sorted(), forKey: Key.ignoredPlayers) }
    }

    /// Every player seen holding the now-playing session, most recent first, so
    /// the ignore list can be built from names that actually occur.
    public static var seenPlayers: [String] {
        get { store.stringArray(forKey: Key.seenPlayers) ?? [] }
        set { store.set(Array(newValue.prefix(24)), forKey: Key.seenPlayers) }
    }

    public static func rememberPlayer(_ player: String?) {
        guard let player, !player.isEmpty else { return }
        var players = seenPlayers
        players.removeAll { $0 == player }
        players.insert(player, at: 0)
        seenPlayers = players
    }

    /// Whether this session owner is on the deny-list.
    ///
    /// A session that reports no player name cannot be matched, so it is never
    /// ignored: an unknown name must not be able to turn the app into a silent
    /// no-op.
    public static func ignoresPlayer(_ player: String?) -> Bool {
        guard let player, !player.isEmpty else { return false }
        return ignoredPlayers.contains(player)
    }

    // MARK: - The rule

    public static var settings: SeekSettings {
        SeekSettings(mode: mode,
                     absoluteSeconds: absoluteSeconds,
                     relativePercent: relativePercent,
                     randomMin: randomMin,
                     randomMax: randomMax,
                     seekOnAutoNext: seekOnAutoNext,
                     guardrailsEnabled: guardrailsEnabled,
                     minDurationSeconds: minDurationSeconds,
                     maxTargetPercent: maxTargetPercent)
    }

    /// Writes the rule back, field by field (each one clamped on the way).
    public static func save(_ settings: SeekSettings) {
        mode = settings.mode
        absoluteSeconds = settings.absoluteSeconds
        relativePercent = settings.relativePercent
        randomMin = settings.randomMin
        randomMax = settings.randomMax
        seekOnAutoNext = settings.seekOnAutoNext
        guardrailsEnabled = settings.guardrailsEnabled
        minDurationSeconds = settings.minDurationSeconds
        maxTargetPercent = settings.maxTargetPercent
    }

    // MARK: - Helpers

    /// Keys of features this build no longer has (the per-player rules). Dropped
    /// once on launch so an upgraded preferences file stays legible. The ignore
    /// list and the seen-player list are current features and stay untouched.
    private static let retiredKeys = ["playerScope", "selectedPlayers", "playerRules"]

    public static func forgetRetiredKeys() {
        for key in retiredKeys where store.object(forKey: key) != nil {
            store.removeObject(forKey: key)
        }
    }

    private static func integer(_ key: String, fallback: Int, range: ClosedRange<Int>) -> Int {
        guard let stored = store.object(forKey: key) as? Int else { return fallback }
        return clamp(stored, range)
    }
}
