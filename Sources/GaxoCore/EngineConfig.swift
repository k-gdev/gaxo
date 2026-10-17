import Foundation

/// Everything the engine needs to start. Fields mirror `gaxo_engine_config`.
public struct EngineConfig: Equatable {
    public var name: String
    public var deviceID: String
    public var keyfile: URL
    /// TCP/UDP base port; RTSP listens on `basePort + 1` (UxPlay `-p` mapping). 0 = dynamic.
    public var basePort: UInt16
    public var width: UInt16
    public var height: UInt16
    public var refreshRate: UInt16
    public var maxFPS: UInt16
    /// UxPlay `-pin` mode: a 4-digit code is asked the first time a device connects.
    public var pinOnce: Bool
    /// Register `_airplay._tcp` / `_raop._tcp` with Bonjour.
    public var advertise: Bool
    /// UxPlay `LOGGER_*` level (6 = info, 7 = debug).
    public var logLevel: Int32
    /// With `pinOnce`: always this code (0…9999). nil = a new random code each time,
    /// which UxPlay accepts only once (a mistyped entry then locks the iPhone out).
    public var fixedPIN: UInt16?

    public init(name: String, deviceID: String, keyfile: URL, basePort: UInt16,
                width: UInt16, height: UInt16, refreshRate: UInt16, maxFPS: UInt16,
                pinOnce: Bool, advertise: Bool, logLevel: Int32, fixedPIN: UInt16? = nil) {
        self.name = name
        self.deviceID = deviceID
        self.keyfile = keyfile
        self.basePort = basePort
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.maxFPS = maxFPS
        self.pinOnce = pinOnce
        self.advertise = advertise
        self.logLevel = logLevel
        self.fixedPIN = fixedPIN
    }
}
