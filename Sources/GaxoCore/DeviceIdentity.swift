import Foundation

/// The receiver's AirPlay device ID: a random, locally administered MAC address,
/// generated once and kept, so it never collides with the Mac's own receiver
/// (which uses the real hardware address).
public struct DeviceIdentity: Equatable {
    public let deviceID: String

    public init(deviceID: String) {
        self.deviceID = deviceID
    }

    static let defaultsKey = "deviceID"

    public static func loadOrCreate(defaults: PreferenceStore = UserDefaults.standard) -> DeviceIdentity {
        if let saved = defaults.string(forKey: defaultsKey), !saved.isEmpty {
            return DeviceIdentity(deviceID: saved)
        }
        let id = randomDeviceID()
        defaults.set(id, forKey: defaultsKey)
        return DeviceIdentity(deviceID: id)
    }

    /// "XX:XX:XX:XX:XX:XX", first octet with the locally-administered bit set and
    /// the multicast bit clear.
    public static func randomDeviceID() -> String {
        var bytes = (0..<6).map { _ in UInt8.random(in: 0...255) }
        bytes[0] = (bytes[0] & 0xFC) | 0x02
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// Where Gaxo keeps its files. Directories are created on first access.
public enum GaxoPaths {
    public static var appSupport: URL {
        directory(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gaxo", isDirectory: true))
    }

    /// The engine's persisted Ed25519 identity key.
    public static var keyfile: URL {
        appSupport.appendingPathComponent("identity.pem")
    }

    public static var logFile: URL {
        directory(FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Gaxo", isDirectory: true))
            .appendingPathComponent("gaxo.log")
    }

    private static func directory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
