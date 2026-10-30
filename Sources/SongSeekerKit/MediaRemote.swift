import Foundation

/// The private API the system Now Playing widget itself uses.
///
/// On recent macOS the *read* side of MediaRemote is gated to Apple-signed
/// processes, which is why now-playing info comes from `reader.js` running under
/// `osascript`. Only the write side — the seek — is called from this process.
public enum MediaRemote {
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private static let setElapsed: SetElapsedFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteSetElapsedTime") else { return nil }
        return unsafeBitCast(symbol, to: SetElapsedFn.self)
    }()

    public static var isAvailable: Bool { setElapsed != nil }

    @discardableResult
    public static func seek(to seconds: Double) -> Bool {
        guard let setElapsed else { return false }
        setElapsed(max(0, seconds))
        return true
    }
}
