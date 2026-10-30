import XCTest
@testable import MidtrackKit

/// The tests run against a throwaway preferences domain so they can never touch
/// the real settings of whoever runs them.
private let testSuite = "MidtrackKitTests"

private func resetPreferences() {
    Prefs.store = UserDefaults(suiteName: testSuite)!
    Prefs.store.removePersistentDomain(forName: testSuite)
}

final class SeekLogicTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetPreferences()
    }

    override func tearDown() {
        Prefs.store.removePersistentDomain(forName: testSuite)
        super.tearDown()
    }

    /// The guardrail toggle is on for the explicit-limit tests; 0 still means a
    /// limit is off, so the mode maths stays the focus.
    private func settings(mode: Prefs.Mode,
                          absoluteSeconds: Int = 120,
                          relativePercent: Int = 20,
                          randomMin: Int = 15,
                          randomMax: Int = 60,
                          guardrailsEnabled: Bool = true,
                          minDurationSeconds: Int = 0,
                          maxTargetPercent: Int = 0) -> SeekSettings {
        SeekSettings(mode: mode,
                     absoluteSeconds: absoluteSeconds,
                     relativePercent: relativePercent,
                     randomMin: randomMin,
                     randomMax: randomMax,
                     guardrailsEnabled: guardrailsEnabled,
                     minDurationSeconds: minDurationSeconds,
                     maxTargetPercent: maxTargetPercent)
    }

    func testPercentLandsAtTheChosenFraction() {
        let target = SeekLogic.computeTarget(duration: 200, settings: settings(mode: .relative))
        XCTAssertEqual(target!, 40, accuracy: 0.0001)
    }

    func testAbsoluteUsesTheFixedOffset() {
        let target = SeekLogic.computeTarget(duration: 200,
                                             settings: settings(mode: .absolute, absoluteSeconds: 95))
        XCTAssertEqual(target!, 95, accuracy: 0.0001)
    }

    func testTargetNeverLandsOnTheVeryEnd() {
        let target = SeekLogic.computeTarget(duration: 60,
                                             settings: settings(mode: .absolute, absoluteSeconds: 300))
        XCTAssertEqual(target!, 58, accuracy: 0.0001)
    }

    func testRandomDrawsInsideTheWindow() {
        let target = SeekLogic.computeTarget(duration: 200,
                                             settings: settings(mode: .random),
                                             randomPercent: 50)
        XCTAssertEqual(target!, 100, accuracy: 0.0001)
    }

    func testRandomWindowOrderDoesNotMatter() {
        let window = settings(mode: .random, randomMin: 60, randomMax: 15).window
        XCTAssertEqual(window, 15...60)
    }

    func testTracksWithoutALengthAreIgnored() {
        // No length, no safe spot to aim at — the Android app's stance too.
        XCTAssertNil(SeekLogic.computeTarget(duration: -1, settings: settings(mode: .relative)))
        XCTAssertNil(SeekLogic.computeTarget(duration: 0, settings: settings(mode: .relative)))
        XCTAssertNil(SeekLogic.computeTarget(duration: 1, settings: settings(mode: .relative)))
    }

    func testTimeFormatting() {
        XCTAssertEqual(SeekLogic.format(0), "0:00")
        XCTAssertEqual(SeekLogic.format(65), "1:05")
        XCTAssertEqual(SeekLogic.format(284.9), "4:44")
    }

    func testDescriptionFollowsTheMode() {
        XCTAssertEqual(SeekLogic.describe(settings(mode: .relative)), "Percent · jump to 20% of the track")
        XCTAssertEqual(SeekLogic.describe(settings(mode: .absolute, absoluteSeconds: 65)),
                       "Time · jump to 1:05")
        XCTAssertEqual(SeekLogic.describe(settings(mode: .random, randomMin: 15, randomMax: 60)),
                       "Random · jump somewhere between 15% and 60%")
    }

    func testModeLabels() {
        XCTAssertEqual(SeekLogic.modeLabel(settings(mode: .relative)), "20%")
        XCTAssertEqual(SeekLogic.modeLabel(settings(mode: .absolute, absoluteSeconds: 90)), "1:30")
        XCTAssertEqual(SeekLogic.modeLabel(settings(mode: .random, randomMin: 15, randomMax: 60)),
                       "random 15–60%")
    }

    // MARK: - Guardrails (borrowed from the Android app)

    func testMinLengthSkipsShortTracks() {
        let rule = settings(mode: .relative, minDurationSeconds: 90)
        XCTAssertNil(SeekLogic.computeTarget(duration: 26, settings: rule))
        XCTAssertEqual(SeekLogic.skipReason(duration: 26, settings: rule),
                       "track is 0:26 — shorter than the 1:30 minimum")
        XCTAssertEqual(SeekLogic.computeTarget(duration: 200, settings: rule)!, 40, accuracy: 0.0001)
    }

    func testUnknownLengthIsNeverSeeked() {
        let rule = settings(mode: .relative)
        XCTAssertEqual(SeekLogic.skipReason(duration: -1, settings: rule),
                       "track length unknown (live stream, ad, or no duration metadata)")
        XCTAssertNil(SeekLogic.computeTarget(duration: -1, settings: rule))
        XCTAssertFalse(SeekLogic.hasLength(0.5))
        XCTAssertTrue(SeekLogic.hasLength(90))
    }

    func testMaxJumpCapsWhereTheJumpCanLand() {
        let rule = settings(mode: .relative, relativePercent: 90, maxTargetPercent: 25)
        XCTAssertEqual(SeekLogic.computeTarget(duration: 200, settings: rule)!, 50, accuracy: 0.0001)
        // The cap never pushes the target onto the very end either.
        let late = settings(mode: .absolute, absoluteSeconds: 7000, maxTargetPercent: 99)
        XCTAssertEqual(SeekLogic.computeTarget(duration: 200, settings: late)!, 198, accuracy: 0.0001)
    }

    func testZeroTurnsAGuardrailOff() {
        let rule = settings(mode: .relative, minDurationSeconds: 0, maxTargetPercent: 0)
        XCTAssertEqual(SeekLogic.computeTarget(duration: 30, settings: rule)!, 6, accuracy: 0.0001)
        XCTAssertEqual(rule.guardrailSummary, "")
    }

    func testGuardrailSummaryReadsLikeTheAndroidLabel() {
        XCTAssertEqual(settings(mode: .relative, minDurationSeconds: 90, maxTargetPercent: 80)
            .guardrailSummary, " · >1:30, ≤80%")
    }

    func testDisabledGuardrailsAllowShortClipsAndLateJumps() {
        let rule = settings(mode: .relative,
                            relativePercent: 90,
                            guardrailsEnabled: false,
                            minDurationSeconds: 90,
                            maxTargetPercent: 25)

        XCTAssertNil(SeekLogic.skipReason(duration: 26, settings: rule))
        XCTAssertEqual(SeekLogic.computeTarget(duration: 26, settings: rule)!, 23.4, accuracy: 0.001)
        XCTAssertEqual(SeekLogic.computeTarget(duration: 200, settings: rule)!, 180, accuracy: 0.001)
        XCTAssertEqual(rule.guardrailSummary, " · guardrails off")
    }

    // MARK: - Preferences

    func testPreferencesAreClampedOnWriteAndRead() {
        Prefs.relativePercent = 150
        XCTAssertEqual(Prefs.relativePercent, 99)
        Prefs.relativePercent = 0
        XCTAssertEqual(Prefs.relativePercent, 1)
        Prefs.randomMin = -10
        XCTAssertEqual(Prefs.randomMin, 1)
        Prefs.minDurationSeconds = -5
        XCTAssertEqual(Prefs.minDurationSeconds, 0)
        Prefs.maxTargetPercent = 500
        XCTAssertEqual(Prefs.maxTargetPercent, 100)
        // A value written straight into the domain is clamped on read too.
        Prefs.store.set(9999, forKey: "absoluteSeconds")
        XCTAssertEqual(Prefs.absoluteSeconds, 7200)
    }

    func testFreshDomainHasTheDocumentedDefaults() {
        XCTAssertTrue(Prefs.enabled)
        XCTAssertEqual(Prefs.mode, .relative)
        XCTAssertEqual(Prefs.absoluteSeconds, 120)
        XCTAssertEqual(Prefs.relativePercent, 20)
        XCTAssertEqual(Prefs.randomMin, 15)
        XCTAssertEqual(Prefs.randomMax, 60)
        XCTAssertTrue(Prefs.seekOnAutoNext)
        XCTAssertFalse(Prefs.guardrailsEnabled)
        XCTAssertEqual(Prefs.minDurationSeconds, 90)
        XCTAssertEqual(Prefs.maxTargetPercent, 80)
    }

    func testTheIgnoreListMatchesExactNamesOnly() {
        XCTAssertFalse(Prefs.ignoresPlayer("Google Chrome"))
        Prefs.ignoredPlayers = ["Google Chrome"]

        XCTAssertTrue(Prefs.ignoresPlayer("Google Chrome"))
        XCTAssertFalse(Prefs.ignoresPlayer("YouTube Music"))
        XCTAssertFalse(Prefs.ignoresPlayer("Chrome"))
        // A session with no name cannot be matched, so it is never ignored: an
        // unknown name must not be able to silence the whole app.
        XCTAssertFalse(Prefs.ignoresPlayer(nil))
        XCTAssertFalse(Prefs.ignoresPlayer(""))

        Prefs.ignoredPlayers = []
        XCTAssertFalse(Prefs.ignoresPlayer("Google Chrome"))
    }

    func testSeenPlayersAreMostRecentFirstAndBounded() {
        Prefs.rememberPlayer("YouTube Music")
        Prefs.rememberPlayer("Google Chrome")
        Prefs.rememberPlayer("YouTube Music")
        XCTAssertEqual(Prefs.seenPlayers, ["YouTube Music", "Google Chrome"])

        for index in 0..<40 { Prefs.rememberPlayer("Player \(index)") }
        XCTAssertEqual(Prefs.seenPlayers.count, 24)
        XCTAssertEqual(Prefs.seenPlayers.first, "Player 39")
    }

    func testRetiredKeysAreDroppedButTheIgnoreListSurvives() {
        Prefs.store.set("selected", forKey: "playerScope")
        Prefs.store.set("v1;mode=relative", forKey: "playerRules")
        Prefs.ignoredPlayers = ["Google Chrome"]
        Prefs.rememberPlayer("Google Chrome")

        Prefs.forgetRetiredKeys()

        XCTAssertNil(Prefs.store.object(forKey: "playerScope"))
        XCTAssertNil(Prefs.store.object(forKey: "playerRules"))
        XCTAssertEqual(Prefs.ignoredPlayers, ["Google Chrome"])
        XCTAssertEqual(Prefs.seenPlayers, ["Google Chrome"])
    }

    func testSavingTheGlobalRuleRoundTrips() {
        var settings = Prefs.settings
        settings.mode = .random
        settings.randomMin = 10
        settings.randomMax = 40
        settings.guardrailsEnabled = true
        settings.minDurationSeconds = 120
        settings.maxTargetPercent = 60
        settings.seekOnAutoNext = false
        Prefs.save(settings)
        XCTAssertEqual(Prefs.settings, settings)
    }
}

final class WatcherTests: XCTestCase {
    private var watcher: Watcher!
    private var seeks: [Double] = []
    private var states: [String] = []
    private var currentDate = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        resetPreferences()
        Prefs.enabled = true
        Prefs.mode = .relative
        Prefs.relativePercent = 20
        Prefs.seekOnAutoNext = true
        // The guardrails have their own tests; the watcher tests exercise the
        // decision rules around them, with the limits themselves disabled.
        Prefs.guardrailsEnabled = true
        Prefs.minDurationSeconds = 0
        Prefs.maxTargetPercent = 0

        seeks = []
        states = []
        currentDate = Date(timeIntervalSince1970: 1_000_000)

        watcher = Watcher()
        watcher.seek = { [weak self] target in
            self?.seeks.append(target)
            return true
        }
        watcher.onState = { [weak self] text in self?.states.append(text) }
        watcher.now = { [weak self] in self?.currentDate ?? Date() }
        watcher.recordJump = { _, _ in }
    }

    override func tearDown() {
        Prefs.store.removePersistentDomain(forName: testSuite)
        super.tearDown()
    }

    private func snap(_ title: String,
                      _ duration: Double,
                      _ elapsed: Double,
                      rate: Double = 1,
                      app: String = "YouTube Music",
                      artist: String = "Artist") -> JXAReader.Snapshot {
        JXAReader.Snapshot(app: app,
                           title: title,
                           artist: artist,
                           duration: duration,
                           elapsed: elapsed,
                           rate: rate,
                           timestamp: currentDate.timeIntervalSince1970)
    }

    private func assertLogged(_ fragment: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(states.contains { $0.contains(fragment) },
                      "expected a state line containing \"\(fragment)\", got \(states)",
                      file: file, line: line)
    }

    // MARK: - The basics

    func testTheTrackPlayingAtLaunchIsNeverJumped() {
        watcher.tick(snap("A", 200, 30))
        XCTAssertTrue(seeks.isEmpty)
        assertLogged("(baseline)")
    }

    func testATrackChangeGetsItsJump() {
        watcher.tick(snap("A", 200, 30))
        watcher.tick(snap("B", 200, 0))
        XCTAssertEqual(seeks, [40])
        assertLogged("SEEK B")
    }

    func testATrackWithoutDurationWaitsForIt() {
        watcher.tick(snap("A", 200, 0))
        watcher.tick(snap("B", 0, 0))
        XCTAssertTrue(seeks.isEmpty)
        assertLogged("waiting for duration")

        watcher.tick(snap("B", 200, 0.4))
        XCTAssertEqual(seeks, [40])
    }

    func testTransientMediaGapsKeepTheBaseline() {
        watcher.tick(snap("A", 200, 0))
        watcher.tick(nil)
        assertLogged("keeping baseline")
        watcher.tick(snap("B", 200, 0))
        XCTAssertEqual(seeks, [40])
    }

    func testLongSilenceResetsTheBaseline() {
        watcher.tick(snap("A", 200, 0))
        for _ in 0..<watcher.noMediaResetTicks { watcher.tick(nil) }
        assertLogged("baseline reset")

        seeks = []
        watcher.tick(snap("B", 200, 0))
        XCTAssertTrue(seeks.isEmpty)
        assertLogged("(baseline)")
    }

    // MARK: - Auto-next

    func testNaturalEndCanBeExcluded() {
        Prefs.seekOnAutoNext = false

        watcher.tick(snap("A", 100, 0))
        watcher.tick(snap("A", 100, 99))
        watcher.tick(snap("B", 200, 0))
        XCTAssertTrue(seeks.isEmpty)
        assertLogged("auto-next seek is off")
    }

    func testAManualSkipIsSeekedEvenWhenNaturalEndsAreExcluded() {
        Prefs.seekOnAutoNext = false

        watcher.tick(snap("A", 100, 0))
        watcher.tick(snap("A", 100, 5))
        watcher.tick(snap("B", 200, 0))
        XCTAssertEqual(seeks, [40])
    }

    func testANaturalEndIsSeekedByDefault() {
        watcher.tick(snap("A", 100, 0))
        watcher.tick(snap("A", 100, 99))
        watcher.tick(snap("B", 200, 0))
        XCTAssertEqual(seeks, [40])
    }

    func testANaturalEndIsNotBlockedByThePreviousTracksPosition() {
        watcher.tick(snap("A", 200, 0))
        watcher.tick(snap("A", 200, 199))
        // The player still reports the finished track's position for a moment.
        watcher.tick(snap("B", 200, 199))
        XCTAssertEqual(seeks, [40])
    }

    // MARK: - Is the position trustworthy?

    func testAPositionThatMovedPastTheTargetIsLeftAlone() {
        watcher.tick(snap("A", 200, 0))
        watcher.tick(snap("B", 200, 150))
        XCTAssertTrue(seeks.isEmpty)
        assertLogged("already at 150s")
    }

    func testAPositionThatDidNotMoveIsNotTrusted() {
        // Track A paused at 1:51 and the user skips to B: the player keeps
        // reporting A's position for a moment, which says nothing about B.
        watcher.tick(snap("A", 200, 111))
        watcher.tick(snap("A", 200, 111))
        watcher.tick(snap("B", 200, 111))
        XCTAssertEqual(seeks, [40])
    }

    // MARK: - Dedup

    func testTheSameTrackIsNotJumpedTwiceInARow() {
        watcher.tick(snap("A", 200, 0))
        watcher.tick(snap("B", 0, 0))
        watcher.tick(snap("B", 200, 0.4))
        XCTAssertEqual(seeks, [40])

        // A glitch title that is already past its spot is skipped, which leaves B
        // as the last track we actually jumped to.
        watcher.tick(snap("glitch", 200, 150))
        watcher.tick(snap("B", 200, 0.6))
        XCTAssertEqual(seeks, [40])
        assertLogged("dedup")
    }

    /// The bug this whole change exists for: YouTube Music plays on while a
    /// browser tab grabs the now-playing session, then hands it back. The song
    /// used to be jumped a second time — backwards, mid-song.
    func testAVideoStealingTheSessionDoesNotJumpTheSongAgain() {
        watcher.tick(snap("Previous", 200, 5))                     // baseline
        watcher.tick(snap("Sudah", 265, 0))                        // change → 0:53
        XCTAssertEqual(seeks, [53])

        watcher.tick(snap("Sudah", 265, 56))                       // playing on
        watcher.tick(snap("X video", 26, 0, app: "Google Chrome"))  // steals the session
        XCTAssertEqual(seeks.count, 2, "the clip is jumped too while the min length is off")

        // The music session returns, reporting where the song actually is: far
        // past the target, so the position guard refuses to pull it back.
        watcher.tick(snap("Sudah", 265, 119))
        XCTAssertEqual(seeks.count, 2, "the returning song must not be jumped a second time")
        assertLogged("already at 119s")
    }

    func testTheDedupWindowExpires() {
        watcher.tick(snap("A", 200, 0))
        watcher.tick(snap("B", 200, 0))
        XCTAssertEqual(seeks.count, 1)

        currentDate = currentDate.addingTimeInterval(watcher.dedupWindow + 1)
        watcher.tick(snap("C", 200, 0))
        watcher.tick(snap("B", 200, 0))
        XCTAssertEqual(seeks.count, 3, "outside the window the track is a candidate again")
    }

    // MARK: - Guardrails

    func testShortClipsAreNeverJumped() {
        Prefs.minDurationSeconds = 90

        watcher.tick(snap("Sudah", 265, 0))                         // baseline
        watcher.tick(snap("X video", 26, 0, app: "Google Chrome"))
        XCTAssertTrue(seeks.isEmpty)
        assertLogged("shorter than the 1:30 minimum")
    }

    func testTheMaxJumpCeilingIsHonoured() {
        Prefs.relativePercent = 90
        Prefs.maxTargetPercent = 25

        watcher.tick(snap("A", 200, 5))
        watcher.tick(snap("B", 200, 0))
        XCTAssertEqual(seeks, [50], "90% of 3:20 would be 3:00 — the ceiling holds it at 0:50")
    }

    // MARK: - A session that gets stolen and handed back

    /// With no whitelist, the same hand-back: the returning song is mid-track and
    /// was never jumped (it was the baseline), so the position guard is what has
    /// to keep it from being yanked backwards.
    func testAReturningBaselineSongIsNotYankedBackwards() {
        watcher.tick(snap("Sudah", 265, 0))                          // baseline, no jump
        watcher.tick(snap("Sudah", 265, 90))                         // playing on
        currentDate = currentDate.addingTimeInterval(30)             // well past the absorb window
        watcher.tick(snap("X video", 26, 0, app: "Google Chrome"))   // grabs the session
        XCTAssertEqual(seeks, [5.2], "only the clip was jumped")

        watcher.tick(snap("Sudah", 265, 119))                        // the session comes back
        XCTAssertEqual(seeks, [5.2], "the song is left where it is")
        assertLogged("already at 119s")
    }

    /// The startup variant: the reader's first line for a track can arrive before
    /// the artist (or a corrected length) does, and the next line used to look
    /// like a brand-new track — a jump a fifth of a second after launch.
    func testASameTitleRepostRightAfterTheBaselineIsAbsorbed() {
        watcher.tick(snap("Titik Nadir", 245, 0, artist: ""))        // baseline, no artist yet
        currentDate = currentDate.addingTimeInterval(0.2)
        watcher.tick(snap("Titik Nadir", 304, 61))                   // same song, fuller metadata

        XCTAssertTrue(seeks.isEmpty)
        assertLogged("absorbing")
    }

    func testTheAbsorbWindowDoesNotSwallowALaterTrackChange() {
        watcher.tick(snap("Titik Nadir", 245, 0, artist: ""))
        currentDate = currentDate.addingTimeInterval(watcher.baselineAbsorbWindow + 1)
        watcher.tick(snap("Titik Nadir", 304, 61))

        XCTAssertEqual(seeks, [60.8], "0.2 × 304 s")
    }

    // MARK: - The ignore list

    /// The structural fix: a session from an ignored player never becomes the
    /// baseline, so when the song's session comes back its key is unchanged and
    /// no track change — and no jump — is even considered.
    func testAnIgnoredPlayerNeverDisturbsTheBaseline() {
        Prefs.ignoredPlayers = ["Google Chrome"]

        watcher.tick(snap("Sudah", 265, 0))                          // baseline
        watcher.tick(snap("X video", 26, 0, app: "Google Chrome"))   // ignored outright
        XCTAssertTrue(seeks.isEmpty)
        assertLogged("Ignoring Google Chrome — on the ignore list")

        watcher.tick(snap("Sudah", 265, 40))                         // still the baseline track
        XCTAssertTrue(seeks.isEmpty)
    }

    func testAnIgnoredPlayerIsNotJumpedEvenForALongItem() {
        Prefs.ignoredPlayers = ["Google Chrome"]

        watcher.tick(snap("Song A", 200, 0))                         // baseline
        watcher.tick(snap("Song B", 200, 0))                         // change → jumped
        XCTAssertEqual(seeks, [40])

        // Five minutes long, so Min length would allow it — the ignore list is
        // what refuses it. Without the list this would be a jump to 1:00.
        watcher.tick(snap("A long video", 300, 0, app: "Google Chrome"))
        XCTAssertEqual(seeks, [40])
        assertLogged("Ignoring Google Chrome")
    }

    // MARK: - Jump now

    func testJumpNowIgnoresTheDedupAndThePastGuard() {
        watcher.tick(snap("A", 200, 0))
        watcher.tick(snap("B", 200, 0))
        XCTAssertEqual(seeks, [40])

        let message = watcher.jumpNow(snap("B", 200, 150))
        XCTAssertTrue(message.hasPrefix("SEEK (manual)"), message)
        XCTAssertEqual(seeks, [40, 40])
    }

    func testJumpNowBypassesTheMinimumLengthButNotAnUnknownLength() {
        Prefs.minDurationSeconds = 90
        watcher.tick(snap("Sudah", 265, 0))

        XCTAssertTrue(watcher.jumpNow(snap("X video", 26, 0)).hasPrefix("SEEK (manual)"))
        XCTAssertEqual(seeks, [5.2], "20% of the 26 s clip, which the guardrail would normally refuse")
        XCTAssertTrue(watcher.jumpNow(snap("Live stream", -1, 30)).contains("length unknown"))
        XCTAssertEqual(seeks, [5.2])
    }

    func testJumpNowRefusesAnIgnoredPlayer() {
        Prefs.ignoredPlayers = ["Google Chrome"]
        XCTAssertEqual(watcher.jumpNow(snap("X video", 200, 10, app: "Google Chrome")),
                       "Google Chrome is on the ignore list.")
        XCTAssertTrue(seeks.isEmpty)
    }

    func testJumpNowIsRefusedWhileSeekIsOff() {
        Prefs.enabled = false
        XCTAssertEqual(watcher.jumpNow(snap("Sudah", 200, 10)), "Seek is off.")
        XCTAssertTrue(seeks.isEmpty)
    }

    func testSeekingOffStillTracksTheBaseline() {
        Prefs.enabled = false
        watcher.tick(snap("A", 200, 0))
        watcher.tick(snap("B", 200, 0))
        XCTAssertTrue(seeks.isEmpty)
        assertLogged("seek is off")

        Prefs.enabled = true
        watcher.tick(snap("C", 200, 0))
        XCTAssertEqual(seeks, [40])
    }

    func testTheDefaultRecorderStoresTheJump() {
        watcher.recordJump = Watcher().recordJump
        watcher.tick(snap("A", 200, 0))
        watcher.tick(snap("B", 200, 0))
        XCTAssertEqual(Prefs.lastJumpTitle, "B")
        XCTAssertEqual(Prefs.lastJumpAt, 40, accuracy: 0.0001)
    }
}
