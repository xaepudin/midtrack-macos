import Foundation

/// Persistent now-playing reader.
///
/// Runs `reader.js` under `osascript`, which is Apple-signed and therefore still
/// allowed to read the private MediaRemote now-playing info on macOS releases
/// that gate it to Apple processes. The child prints one JSON line per snapshot:
/// on every MediaRemote change notification plus a 0.1 s fallback poll.
public final class JXAReader {
    public struct Snapshot {
        public let app: String?
        public let title: String?
        public let artist: String?
        public let duration: Double
        public let elapsed: Double
        public let rate: Double
        public let timestamp: Double

        public init(app: String?,
                    title: String?,
                    artist: String?,
                    duration: Double,
                    elapsed: Double,
                    rate: Double,
                    timestamp: Double) {
            self.app = app
            self.title = title
            self.artist = artist
            self.duration = duration
            self.elapsed = elapsed
            self.rate = rate
            self.timestamp = timestamp
        }

        /// What makes two snapshots "the same track".
        public var identity: String? {
            guard let title, !title.isEmpty else { return nil }
            return "\(title)|\(artist ?? "")"
        }
    }

    /// Where `reader.js` lives: inside the app bundle when running as a bundled
    /// app, otherwise next to the sources (so `swift run` works while developing).
    public static func defaultScriptURL() -> URL {
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("reader.js")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("ytm-radio-seek-macos/reader.js")
    }

    /// Parses one JSON line from the reader. Exposed for the `--check` report.
    public static func parse(_ line: Data) -> Snapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        return Snapshot(app: object["app"] as? String,
                        title: object["t"] as? String,
                        artist: object["a"] as? String,
                        duration: (object["d"] as? NSNumber)?.doubleValue ?? -1,
                        elapsed: (object["e"] as? NSNumber)?.doubleValue ?? -1,
                        rate: (object["r"] as? NSNumber)?.doubleValue ?? 0,
                        timestamp: (object["ts"] as? NSNumber)?.doubleValue ?? -1)
    }

    /// Pushed on every parsed snapshot. Set it before calling `start()`.
    public var onSnapshot: ((Snapshot) -> Void)?

    private let scriptPath: String
    private var process: Process?
    private var buffer = Data()
    private var lastRespawn = Date.distantPast

    public init(scriptPath: String) {
        self.scriptPath = scriptPath
    }

    public func start() {
        spawn()
        Thread.detachNewThread { [weak self] in
            self?.readLoop()
        }
    }

    public func stop() {
        process?.terminate()
        process = nil
    }

    private func spawn() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", scriptPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return }
        self.process = process
        lastRespawn = Date()
    }

    private func readLoop() {
        while true {
            guard let process, let pipe = process.standardOutput as? Pipe else {
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty {
                // The child ended — respawn, but not in a tight loop.
                if Date().timeIntervalSince(lastRespawn) > 2 {
                    spawn()
                }
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if let snapshot = JXAReader.parse(line) {
                    onSnapshot?(snapshot)
                }
            }
        }
    }
}
