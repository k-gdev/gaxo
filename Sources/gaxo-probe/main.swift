// gaxo-probe — milestone 1: run the UxPlay engine without any window and
// report what arrives from the iPhone (connection, video, audio).
//
//   swift run gaxo-probe [--name "Gaxo Probe"] [--port 7100] [--seconds N] [--debug]

import CoreGraphics
import Foundation
import GaxoCore

struct Options {
    var name = "Gaxo Probe"
    var port: UInt16 = 7100
    var seconds: Double = 0
    var debug = false

    init(_ args: [String]) {
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--name": name = it.next() ?? name
            case "--port": port = it.next().flatMap(UInt16.init) ?? port
            case "--seconds": seconds = it.next().flatMap(Double.init) ?? seconds
            case "--debug": debug = true
            case "-h", "--help":
                print("usage: gaxo-probe [--name NAME] [--port BASE] [--seconds N] [--debug]")
                exit(0)
            default:
                FileHandle.standardError.write(Data("unknown option \(arg)\n".utf8))
                exit(2)
            }
        }
    }
}

/// Counts what the engine delivers.
final class CountingSink: MediaSink {
    private let lock = NSLock()
    private(set) var videoFrames = 0
    private(set) var videoBytes = 0
    private(set) var size = CGSize.zero
    private(set) var audioCodec: UInt8 = 0
    private(set) var audioFrames = 0
    private(set) var volumeDB: Float?

    func videoFrame(_ annexB: UnsafeRawBufferPointer, ntpNanos: UInt64) {
        lock.withLock {
            videoFrames += 1
            videoBytes += annexB.count
        }
    }

    func videoSize(source: CGSize, size: CGSize) { lock.withLock { self.size = size } }
    func videoFlush() {}
    func audioFormat(codec: UInt8, samplesPerFrame: UInt16) { lock.withLock { audioCodec = codec } }
    func audioFrame(_ data: UnsafeRawBufferPointer, codec: UInt8, ntpNanos: UInt64) {
        lock.withLock { audioFrames += 1 }
    }
    func audioFlush() {}
    func volume(db: Float) { lock.withLock { volumeDB = db } }

    var summary: String {
        lock.withLock {
            let kb = videoBytes / 1024
            let vol = volumeDB.map { String(format: "%.1f dB", $0) } ?? "-"
            return "video \(videoFrames) frames (\(kb) KB) size \(Int(size.width))×\(Int(size.height)) | "
                + "audio ct=\(audioCodec) \(audioFrames) frames | volume \(vol)"
        }
    }
}

let options = Options(Array(CommandLine.arguments.dropFirst()))
Log.echoToStderr = true

let defaults = UserDefaults(suiteName: "com.gaxo.probe")!
let identity = DeviceIdentity.loadOrCreate(defaults: defaults)
let config = EngineConfig(
    name: options.name,
    deviceID: identity.deviceID,
    keyfile: GaxoPaths.appSupport.appendingPathComponent("probe-identity.pem"),
    basePort: options.port,
    width: 1920, height: 1080, refreshRate: 60, maxFPS: 60,
    pinOnce: false,
    advertise: true,
    logLevel: options.debug ? 7 : 6)

let sink = CountingSink()
let session = SessionController()
session.media = sink
session.onStateChange = { state in print("state: \(state)") }

print("gaxo-probe: \"\(config.name)\" device ID \(config.deviceID), base port \(config.basePort) (RTSP on \(config.basePort + 1))")
print("log file: \(GaxoPaths.logFile.path)")
session.start(config: config)

let report = DispatchSource.makeTimerSource(queue: .main)
report.schedule(deadline: .now() + 2, repeating: 2)
report.setEventHandler { print("\(session.state) | \(sink.summary)") }
report.resume()

func shutdown() {
    session.stop()
    SessionController.controlQueue.async {
        print("final: \(sink.summary)")
        exit(0)
    }
}

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler { shutdown() }
sigint.resume()

if options.seconds > 0 {
    DispatchQueue.main.asyncAfter(deadline: .now() + options.seconds) { shutdown() }
}

dispatchMain()
