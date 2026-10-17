import Foundation
import Testing
import UxPlayEngine

/// Proves the vendored UxPlay engine compiles, links statically and can start
/// and stop through the C shim.
@Suite struct EngineLinkTests {
    private func tempKeyfile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gaxo-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("identity.pem")
    }

    private func startEngine(port: UInt16, keyfile: URL, into engine: inout OpaquePointer?) -> Int32 {
        try? FileManager.default.createDirectory(
            at: keyfile.deletingLastPathComponent(), withIntermediateDirectories: true)
        return "GaxoTest".withCString { name in
            "02:11:22:33:44:55".withCString { deviceID in
                keyfile.path.withCString { key in
                    var config = gaxo_engine_config()
                    config.name = name
                    config.device_id = deviceID
                    config.keyfile = key
                    config.base_port = port
                    config.width = 1920
                    config.height = 1080
                    config.refresh_rate = 60
                    config.max_fps = 60
                    config.pin_once = false
                    config.advertise = false
                    config.log_level = 0
                    var callbacks = gaxo_engine_callbacks()
                    return gaxo_engine_start(&config, &callbacks, &engine)
                }
            }
        }
    }

    @Test func startsOnDynamicPortAndStops() {
        let keyfile = tempKeyfile()
        var engine: OpaquePointer?
        let result = startEngine(port: 0, keyfile: keyfile, into: &engine)
        #expect(result == GAXO_OK)
        #expect(engine != nil)
        #expect(gaxo_engine_port(engine) > 0)
        gaxo_engine_stop(engine)
        #expect(FileManager.default.fileExists(atPath: keyfile.path))
    }

    /// Same mapping as `uxplay -p <base>`: TCP base = mirror data, base+1 = RTSP/HTTP.
    @Test func listensOnBasePlusOneLikeUxPlay() {
        let base = UInt16.random(in: 40_000...59_990)
        var engine: OpaquePointer?
        #expect(startEngine(port: base, keyfile: tempKeyfile(), into: &engine) == GAXO_OK)
        #expect(gaxo_engine_port(engine) == base + 1)
        gaxo_engine_stop(engine)
    }

    @Test func secondEngineOnSamePortFails() {
        let base = UInt16.random(in: 40_000...59_990)
        var first: OpaquePointer?
        #expect(startEngine(port: base, keyfile: tempKeyfile(), into: &first) == GAXO_OK)

        var second: OpaquePointer?
        #expect(startEngine(port: base, keyfile: tempKeyfile(), into: &second) == GAXO_ERR_PORT)
        #expect(second == nil)

        gaxo_engine_stop(first)
    }
}
