import Foundation

/// A small append-only log, the same shape IRSVerb keeps: a menu bar accessory
/// has nowhere to print, so anything worth knowing goes to
/// `~/Library/Logs/SongSeeker/app.log`.
public enum AppLog {
    public static let url: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        let directory = base.appendingPathComponent("Logs/SongSeeker")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("app.log")
    }()

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    public static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
