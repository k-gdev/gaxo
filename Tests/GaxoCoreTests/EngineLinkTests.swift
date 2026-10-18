import Darwin
import Foundation
import Testing
@testable import GaxoCore

/// Proves the vendored UxPlay engine compiles, links statically and can start
/// and stop through the C shim and its Swift wrapper.
@Suite final class EngineLinkTests {
    /// This test's folder for the identity key, removed when the test ends.
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("gaxo-test-\(UUID().uuidString)", isDirectory: true)

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func config(port: UInt16) -> EngineConfig {
        EngineConfig(name: "GaxoTest", deviceID: "02:11:22:33:44:55",
                     keyfile: folder.appendingPathComponent("identity.pem"),
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
        #expect(throws: EngineError.portInUse(base + 1), "the RTSP port is the one that clashes") {
            try second.start()
        }
    }

    /// Holds a port like another app would.
    private func occupy(_ type: Int32, _ port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, type, 0)
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 { throw POSIXError(.EADDRINUSE) }
        if type == SOCK_STREAM { listen(fd, 1) }
        return fd
    }

    /// TCP base (mirror data) and the UDP ports are only bound when an iPhone connects;
    /// a clash must still be reported at start, not fail silently later.
    @Test func tcpMirrorPortTakenByAnotherAppIsReported() throws {
        let base = UInt16.random(in: 40_000...59_990)
        let held = try occupy(SOCK_STREAM, base)
        defer { close(held) }
        #expect(throws: EngineError.portInUse(base)) { try Engine(config: config(port: base)).start() }
    }

    @Test func udpPortTakenByAnotherAppIsReported() throws {
        let base = UInt16.random(in: 40_000...59_990)
        let held = try occupy(SOCK_DGRAM, base + 2)
        defer { close(held) }
        #expect(throws: EngineError.portInUse(base + 2)) { try Engine(config: config(port: base)).start() }
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
