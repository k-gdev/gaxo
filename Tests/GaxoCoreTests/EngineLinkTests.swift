import Foundation
import Testing
@testable import GaxoCore

/// Proves the vendored UxPlay engine compiles, links statically and can start
/// and stop through the C shim and its Swift wrapper.
@Suite struct EngineLinkTests {
    private func config(port: UInt16) -> EngineConfig {
        let keyfile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gaxo-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("identity.pem")
        return EngineConfig(name: "GaxoTest", deviceID: "02:11:22:33:44:55", keyfile: keyfile,
                            basePort: port, width: 1920, height: 1080, refreshRate: 60, maxFPS: 60,
                            pinOnce: false, advertise: false, logLevel: 0)
    }

    @Test func startsOnDynamicPortAndStops() throws {
        let config = config(port: 0)
        let engine = Engine(config: config)
        try engine.start()
        #expect(engine.port > 0)
        engine.stop()
        engine.stop() // idempotent
        #expect(FileManager.default.fileExists(atPath: config.keyfile.path))
    }

    /// Same mapping as `uxplay -p <base>`: TCP base = mirror data, base+1 = RTSP/HTTP.
    @Test func listensOnBasePlusOneLikeUxPlay() throws {
        let base = UInt16.random(in: 40_000...59_990)
        let engine = Engine(config: config(port: base))
        try engine.start()
        #expect(engine.port == base + 1)
        engine.stop()
    }

    @Test func secondEngineOnSamePortFails() throws {
        let base = UInt16.random(in: 40_000...59_990)
        let first = Engine(config: config(port: base))
        try first.start()
        defer { first.stop() }

        let second = Engine(config: config(port: base))
        #expect(throws: EngineError.portInUse(base)) { try second.start() }
    }

    @Test func keyIsReusedAcrossRestarts() throws {
        let config = config(port: 0)
        let first = Engine(config: config)
        try first.start()
        first.stop()
        let saved = try Data(contentsOf: config.keyfile)

        let second = Engine(config: config)
        try second.start()
        second.stop()
        #expect(try Data(contentsOf: config.keyfile) == saved)
    }
}
