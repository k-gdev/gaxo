import Darwin
import Foundation
import os

/// Logging to the unified log (subsystem `com.gaxo`) and, once enabled, to
/// `~/Library/Logs/Gaxo/gaxo.log`, so a silent refusal from the iPhone can be
/// read back and compared with UxPlay's own debug output.
public enum Log {
    private static let app = Logger(subsystem: "com.gaxo", category: "app")
    private static let engineLog = Logger(subsystem: "com.gaxo", category: "engine")
    private static let fileLock = NSLock()
    nonisolated(unsafe) private static var file: LogFile?

    /// The app and the probe write a log file; tests and libraries do not unless asked.
    public static func enableFile(at url: URL = GaxoPaths.logFile) {
        fileLock.withLock { file = LogFile(url: url) }
    }

    public static func disableFile() {
        fileLock.withLock { file = nil }
    }

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
        fileLock.withLock { file }?.append(line)
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

/// Append-only log file, safe to use from engine threads and from several
/// processes at once (O_APPEND: every write lands at the current end of file).
final class LogFile: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var fd: Int32 = -1

    init(url: URL) {
        self.url = url
    }

    deinit {
        if fd >= 0 { close(fd) }
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if fd < 0 {
            fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        }
        guard fd >= 0 else { return }
        Data(line.utf8).withUnsafeBytes { bytes in
            _ = Darwin.write(fd, bytes.baseAddress, bytes.count)
        }
    }
}
