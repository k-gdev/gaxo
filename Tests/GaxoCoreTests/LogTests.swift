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
