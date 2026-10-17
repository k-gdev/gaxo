import CoreGraphics
import Darwin
import Foundation
import Testing
@testable import GaxoCore

/// Collects the engine's log lines; admits everyone.
private final class LogCapture: EngineDelegate {
    private let lock = NSLock()
    private var lines: [String] = []
    var all: [String] { lock.withLock { lines } }

    func engineLog(level: Int32, _ message: String) { lock.withLock { lines.append(message) } }
    func engineClientRequest(deviceID: String, model: String, name: String) -> Bool { true }
    func engineConnectionOpened() {}
    func engineConnectionClosed() {}
    func engineConnectionLost(reason: Int32) {}
    func engineFeedback() {}
    func engineVideoStopped() {}
    func engineVideoFrame(_ annexB: UnsafeRawBufferPointer, ntpNanos: UInt64) {}
    func engineVideoSize(source: CGSize, size: CGSize) {}
    func engineVideoFlush() {}
    func engineAudioFormat(codec: UInt8, samplesPerFrame: UInt16) {}
    func engineAudioFrame(_ data: UnsafeRawBufferPointer, codec: UInt8, ntpNanos: UInt64) {}
    func engineAudioFlush() {}
    func engineVolume(db: Float) {}
    func engineShowPIN(_ pin: String) {}
}

/// A minimal RTSP client over a blocking socket, enough to speak the iPhone's pairing steps.
private struct RTSPClient {
    let fd: Int32
    private var cseq = 0

    init(port: UInt16) throws {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 { throw POSIXError(.ECONNREFUSED) }
    }

    func close() { Darwin.close(fd) }

    /// Sends one POST and returns the status code and body.
    mutating func post(_ path: String, plist: [String: Any]? = nil) throws -> (status: Int, body: Data) {
        cseq += 1
        let body = try plist.map { try PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0) }
            ?? Data()
        var head = "POST \(path) RTSP/1.0\r\nCSeq: \(cseq)\r\nUser-Agent: AirPlay/960.13.1\r\n"
        if plist != nil { head += "Content-Type: application/x-apple-binary-plist\r\n" }
        head += "Content-Length: \(body.count)\r\n\r\n"
        let request = Data(head.utf8) + body
        _ = request.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            if let split = received.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: received[..<split.lowerBound], as: UTF8.self)
                let status = Int(header.split(separator: " ").dropFirst().first ?? "") ?? 0
                let length = header.split(separator: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                let bodyStart = split.upperBound
                if received.count - bodyStart >= length {
                    return (status, received.subdata(in: bodyStart..<bodyStart + length))
                }
            }
            let n = recv(fd, &buffer, buffer.count, 0)
            if n <= 0 { throw POSIXError(.ETIMEDOUT) }
            received.append(buffer, count: n)
        }
    }
}

@Suite(.serialized) struct PinPairingTests {
    /// iOS 26 sends a 20-byte SHA-1 proof in pair-setup-pin (UxPlay's SRP is SHA-1).
    /// UxPlay v1.73.7 rejected anything but 64 bytes, so the iPhone re-prompted for the
    /// code forever. The proof must reach SRP verification.
    @Test func twentyByteProofReachesVerification() throws {
        let keyfile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gaxo-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("identity.pem")
        let engine = Engine(config: EngineConfig(
            name: "GaxoPinTest", deviceID: "02:11:22:33:44:66", keyfile: keyfile, basePort: 0,
            width: 1920, height: 1080, refreshRate: 60, maxFPS: 60,
            pinOnce: true, advertise: false, logLevel: 6))
        let capture = LogCapture()
        engine.delegate = capture
        try engine.start()
        defer { engine.stop() }

        var client = try RTSPClient(port: engine.port)
        defer { client.close() }
        #expect(try client.post("/pair-pin-start").status == 200)

        let step1 = try client.post("/pair-setup-pin", plist: ["method": "pin", "user": "FE:C4:42:6E:68:F7"])
        #expect(step1.status == 200)
        let reply = try PropertyListSerialization.propertyList(from: step1.body, format: nil) as? [String: Any]
        #expect(reply?["pk"] is Data && reply?["salt"] is Data)

        let randomA = Data((0..<256).map { _ in UInt8.random(in: 1...255) })
        let shaOneProof = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
        _ = try? client.post("/pair-setup-pin", plist: ["pk": randomA, "proof": shaOneProof])

        let log = capture.all.joined(separator: "\n")
        #expect(!log.contains("client_proof_len 20 invalid"), "20-byte proof rejected by length")
        #expect(log.contains("client proof not validated"), "proof should reach SRP verification (and fail: it is random)")
    }
}
