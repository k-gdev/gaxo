import Foundation
import os

/// Logging to the unified log (subsystem `com.gaxo`) and to
/// `~/Library/Logs/Gaxo/gaxo.log`, so a silent refusal from the iPhone can be
/// read back and compared with UxPlay's own debug output.
public enum Log {
    private static let app = Logger(subsystem: "com.gaxo", category: "app")
    private static let engineLog = Logger(subsystem: "com.gaxo", category: "engine")
    private static let file = LogFile(url: GaxoPaths.logFile)

    /// Also echo every line to stderr (the probe turns this on).
    nonisolated(unsafe) public static var echoToStderr = false

    public static func info(_ message: String) {
        app.info("\(message, privacy: .public)")
        write("INFO", message)
    }

    public static func error(_ message: String) {
        app.error("\(message, privacy: .public)")
        write("ERROR", message)
    }

    public static func debug(_ message: String) {
        app.debug("\(message, privacy: .public)")
        write("DEBUG", message)
    }

    /// A line from the UxPlay engine; `level` is UxPlay's LOGGER_* level.
    public static func engine(level: Int32, _ message: String) {
        let trimmed = message.trimmingCharacters(in: .newlines)
        switch level {
        case ...3: engineLog.error("\(trimmed, privacy: .public)")
        case 4...6: engineLog.info("\(trimmed, privacy: .public)")
        default: engineLog.debug("\(trimmed, privacy: .public)")
        }
        write("UXPLAY/\(level)", trimmed)
    }

    private static func write(_ tag: String, _ message: String) {
        let line = "\(timestamp()) [\(tag)] \(message)\n"
        file.append(line)
        if echoToStderr {
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}

/// Append-only log file, safe to use from engine threads.
private final class LogFile: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?

    init(url: URL) {
        self.url = url
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
        }
        try? handle?.write(contentsOf: Data(line.utf8))
    }
}
