import Foundation
import Testing
@testable import GaxoCore

@Suite(.serialized) struct LogTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gaxo-log-\(UUID().uuidString).log")
    }

    /// The app, the probe and the tests may all write the log at once; no line may be lost.
    @Test func twoWritersNeverOverwriteEachOther() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = LogFile(url: url)
        let second = LogFile(url: url)
        first.append("a1\n")
        second.append("b1\n")
        first.append("a2\n")
        second.append("b2\n")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == "a1\nb1\na2\nb2\n")
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + ".1"))
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    /// The log must not grow forever: at the limit it becomes gaxo.log.1 and a new file starts.
    @Test func fullFileBecomesDotOne() throws {
        let url = tempFile()
        defer { remove(url) }
        let log = LogFile(url: url, maxBytes: 10)
        log.append("0123456789\n")
        log.append("next\n")
        #expect(try read(url.path) == "next\n")
        #expect(try read(url.path + ".1") == "0123456789\n")
    }

    @Test func onlyOneOldFileIsKept() throws {
        let url = tempFile()
        defer { remove(url) }
        let log = LogFile(url: url, maxBytes: 10)
        log.append("first-0123\n")
        log.append("second-012\n")
        log.append("third\n")
        #expect(try read(url.path) == "third\n")
        #expect(try read(url.path + ".1") == "second-012\n")
        #expect(!FileManager.default.fileExists(atPath: url.path + ".2"))
    }

    /// The app and the probe share the file: after one of them rotates it, the other
    /// writes to the new file, not on into gaxo.log.1.
    @Test func otherWriterFollowsARotation() throws {
        let url = tempFile()
        defer { remove(url) }
        let first = LogFile(url: url, maxBytes: 10)
        let second = LogFile(url: url, maxBytes: 10)
        second.append("b1\n")
        first.append("a-01234567\n") // fills the file: first rotates it
        second.append("b2\n")
        #expect(try read(url.path) == "b2\n")
        #expect(try read(url.path + ".1") == "b1\na-01234567\n")
    }

    /// Only the app and the probe write ~/Library/Logs/Gaxo/gaxo.log; tests must not.
    @Test func writesToFileOnlyWhenEnabled() throws {
        let url = tempFile()
        defer {
            Log.disableFile()
            try? FileManager.default.removeItem(at: url)
        }
        Log.info("before enabling")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        Log.enableFile(at: url)
        Log.info("hello")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("[INFO] hello"))
        #expect(!text.contains("before enabling"))
    }
}
