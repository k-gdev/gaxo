import Foundation

/// The video size Gaxo asks the iPhone for.
public enum Resolution: String, CaseIterable, Codable {
    case hd720, hd1080, qhd1440

    public var size: (width: UInt16, height: UInt16) {
        switch self {
        case .hd720: (1280, 720)
        case .hd1080: (1920, 1080)
        case .qhd1440: (2560, 1440)
        }
    }

    public var label: String {
        "\(size.width) × \(size.height)"
    }
}

/// User settings (mockup screen 4).
public struct Settings: Codable, Equatable {
    public var name: String
    public var openAtLogin: Bool
    public var showStatusWindowAtLaunch: Bool
    public var resolution: Resolution
    public var frameRate: Int
    public var keepOnTop: Bool
    public var closeWindowWhenMirroringStops: Bool
    public var playSound: Bool
    public var requireCode: Bool
    /// The fixed 4-digit code (0…9999) the iPhone must enter when `requireCode` is on.
    public var pairingCode: Int?

    public static let `default` = Settings(
        name: "Gaxo",
        openAtLogin: false,
        showStatusWindowAtLaunch: true,
        resolution: .hd1080,
        frameRate: 60,
        keepOnTop: false,
        closeWindowWhenMirroringStops: true,
        playSound: true,
        requireCode: false,
        pairingCode: nil)

    /// These settings with a code assigned when one is needed; an existing code is kept.
    public func ensuringPairingCode(_ random: () -> Int = { Int.random(in: 0...9999) }) -> Settings {
        guard requireCode, pairingCode == nil else { return self }
        var settings = self
        settings.pairingCode = random()
        return settings
    }

    public static func codeText(_ code: Int) -> String {
        String(format: "%04d", code)
    }

    /// The receiver name as shown on the iPhone: trimmed, at most 40 characters and
    /// 50 UTF-8 bytes (Bonjour allows 63 for "<MAC>@<name>"), never empty.
    public static func cleanName(_ raw: String) -> String {
        var name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        while name.utf8.count > 50 { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Settings.default.name : name
    }
}

/// Where settings and the device ID are kept: UserDefaults in the app, memory in tests.
public protocol PreferenceStore: AnyObject {
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferenceStore {}

extension Settings {
    /// These settings with `draft` as the name, or nil when that changes nothing.
    public func applyingNameDraft(_ draft: String) -> Settings? {
        let clean = Settings.cleanName(draft)
        guard clean != name else { return nil }
        var settings = self
        settings.name = clean
        return settings
    }
}

/// Loads and saves `Settings` in user defaults and derives the engine config.
public final class SettingsStore {
    /// Gaxo's network base port (TCP/UDP 7100–7102); the Mac's own receiver keeps 7000.
    public static let basePort: UInt16 = 7100
    static let defaultsKey = "settings"

    private let defaults: PreferenceStore

    public init(defaults: PreferenceStore = UserDefaults.standard) {
        self.defaults = defaults
    }

    public var settings: Settings {
        get {
            guard let data = defaults.data(forKey: Self.defaultsKey),
                  let saved = try? JSONDecoder().decode(Settings.self, from: data)
            else { return .default }
            return saved
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.defaultsKey)
            }
        }
    }

    public func engineConfig(identity: DeviceIdentity, logLevel: Int32 = 6) -> EngineConfig {
        let s = settings
        return EngineConfig(
            name: Settings.cleanName(s.name),
            deviceID: identity.deviceID,
            keyfile: GaxoPaths.keyfile,
            basePort: Self.basePort,
            width: s.resolution.size.width,
            height: s.resolution.size.height,
            refreshRate: 60,
            maxFPS: UInt16(s.frameRate),
            pinOnce: s.requireCode,
            advertise: true,
            logLevel: logLevel,
            fixedPIN: s.requireCode ? s.pairingCode.map { UInt16($0 % 10000) } : nil)
    }

    /// Changes the iPhone sees (name, video format, pairing) need an engine restart.
    public static func requiresEngineRestart(_ old: Settings, _ new: Settings) -> Bool {
        old.name != new.name
            || old.resolution != new.resolution
            || old.frameRate != new.frameRate
            || old.requireCode != new.requireCode
            || old.pairingCode != new.pairingCode
    }
}
