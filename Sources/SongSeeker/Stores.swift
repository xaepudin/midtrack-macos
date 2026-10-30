import Foundation
import SongSeekerKit
import SwiftUI

/// Rarely-changing status, kept apart from `AppModel` so the menu bar icon can
/// update without dragging the rest of the scene with it.
final class StatusStore: ObservableObject {
    @Published var enabled = Prefs.enabled
}

/// The ~10 Hz now-playing values the panel draws.
///
/// Deliberately not part of `AppModel`: the `MenuBarExtra` scene observes that
/// object, and every `@Published` change there re-renders the whole scene — even
/// while the panel is closed. IRSVerb measured that pattern at ~12% of a CPU core
/// doing nothing, so the fast values live in their own store that only the
/// panel's status rows observe.
final class NowPlayingStore: ObservableObject {
    @Published var app = ""
    @Published var title = ""
    @Published var artist = ""
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var rate: Double = 0
    /// Where the next jump will land, when the rule names a single spot.
    @Published var marker: Double?
    /// The whole range a random jump can land in, when the rule does not.
    @Published var band: ClosedRange<Double>?

    var hasTrack: Bool { !title.isEmpty }

    func update(with snapshot: JXAReader.Snapshot?, settings: SeekSettings) {
        guard let snapshot, snapshot.identity != nil else {
            reset()
            return
        }
        app = snapshot.app ?? ""
        title = snapshot.title ?? ""
        artist = snapshot.artist ?? ""
        elapsed = max(0, snapshot.elapsed)
        duration = max(0, snapshot.duration)
        rate = snapshot.rate

        guard duration > 2 else {
            marker = nil
            band = nil
            return
        }
        switch settings.mode {
        case .absolute, .relative:
            marker = SeekLogic.computeTarget(duration: duration, settings: settings)
            band = nil
        case .random:
            let window = settings.window
            marker = nil
            band = (duration * Double(window.lowerBound) / 100)...(duration * Double(window.upperBound) / 100)
        }
    }

    func reset() {
        app = ""
        title = ""
        artist = ""
        elapsed = 0
        duration = 0
        rate = 0
        marker = nil
        band = nil
    }
}
