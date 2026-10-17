import CoreGraphics
import Foundation
import UxPlayEngine

public enum EngineError: Error, Equatable {
    case dnssdInit
    case raopInit
    case portInUse(UInt16)
    case registerFailed
}

/// Receives the engine's events. **Called on engine threads.**
public protocol EngineDelegate: AnyObject {
    func engineClientRequest(deviceID: String, model: String, name: String) -> Bool
    func engineConnectionOpened()
    func engineConnectionClosed()
    func engineConnectionLost(reason: Int32)
    func engineFeedback()
    func engineVideoStopped()
    func engineVideoFrame(_ annexB: UnsafeRawBufferPointer, ntpNanos: UInt64)
    func engineVideoSize(source: CGSize, size: CGSize)
    func engineVideoFlush()
    func engineAudioFormat(codec: UInt8, samplesPerFrame: UInt16)
    func engineAudioFrame(_ data: UnsafeRawBufferPointer, codec: UInt8, ntpNanos: UInt64)
    func engineAudioFlush()
    func engineVolume(db: Float)
    func engineShowPIN(_ pin: String)
    func engineLog(level: Int32, _ message: String)
}

public protocol EngineProtocol: AnyObject {
    var delegate: EngineDelegate? { get set }
    var port: UInt16 { get }
    func start() throws
    func stop()
    func dropClients()
}

/// The UxPlay engine behind the `gaxo_engine` C shim.
public final class Engine: EngineProtocol {
    public weak var delegate: EngineDelegate?
    private let config: EngineConfig
    private var handle: OpaquePointer?
    /// Retained while the C engine runs, so callbacks never see a freed object.
    private var retainedSelf: Unmanaged<Engine>?

    public init(config: EngineConfig) {
        self.config = config
    }

    deinit {
        if let handle { gaxo_engine_stop(handle) }
    }

    public var port: UInt16 {
        gaxo_engine_port(handle)
    }

    public func start() throws {
        precondition(handle == nil, "engine already started")
        try? FileManager.default.createDirectory(
            at: config.keyfile.deletingLastPathComponent(), withIntermediateDirectories: true)

        let unmanaged = Unmanaged.passRetained(self)
        var callbacks = Self.callbacks
        callbacks.ctx = unmanaged.toOpaque()

        var out: OpaquePointer?
        let result = config.name.withCString { name in
            config.deviceID.withCString { deviceID in
                config.keyfile.path.withCString { keyfile in
                    var c = gaxo_engine_config()
                    c.name = name
                    c.device_id = deviceID
                    c.keyfile = keyfile
                    c.base_port = config.basePort
                    c.width = config.width
                    c.height = config.height
                    c.refresh_rate = config.refreshRate
                    c.max_fps = config.maxFPS
                    c.pin_once = config.pinOnce
                    c.advertise = config.advertise
                    c.log_level = config.logLevel
                    c.fixed_pin = config.fixedPIN.map { Int32($0) } ?? -1
                    return gaxo_engine_start(&c, &callbacks, &out)
                }
            }
        }

        guard Int(result) == GAXO_OK, let out else {
            unmanaged.release()
            switch Int(result) {
            case GAXO_ERR_DNSSD_INIT: throw EngineError.dnssdInit
            case GAXO_ERR_PORT: throw EngineError.portInUse(config.basePort)
            case GAXO_ERR_REGISTER: throw EngineError.registerFailed
            default: throw EngineError.raopInit
            }
        }
        handle = out
        retainedSelf = unmanaged
    }

    public func stop() {
        guard let handle else { return }
        self.handle = nil
        gaxo_engine_stop(handle) // joins engine threads: no callbacks after this
        retainedSelf?.release()
        retainedSelf = nil
    }

    public func dropClients() {
        guard let handle else { return }
        gaxo_engine_drop_clients(handle)
    }

    // MARK: - C callbacks

    private static func delegate(_ ctx: UnsafeMutableRawPointer?) -> EngineDelegate? {
        guard let ctx else { return nil }
        return Unmanaged<Engine>.fromOpaque(ctx).takeUnretainedValue().delegate
    }

    private static func string(_ s: UnsafePointer<CChar>?) -> String {
        s.map { String(cString: $0) } ?? ""
    }

    private static let callbacks: gaxo_engine_callbacks = {
        var cb = gaxo_engine_callbacks()
        cb.log = { ctx, level, msg in
            delegate(ctx)?.engineLog(level: level, string(msg))
        }
        cb.client_request = { ctx, deviceID, model, name, admit in
            let allowed = delegate(ctx)?.engineClientRequest(
                deviceID: string(deviceID), model: string(model), name: string(name)) ?? true
            admit?.pointee = allowed
        }
        cb.conn_opened = { ctx in delegate(ctx)?.engineConnectionOpened() }
        cb.conn_closed = { ctx in delegate(ctx)?.engineConnectionClosed() }
        cb.conn_lost = { ctx, reason in delegate(ctx)?.engineConnectionLost(reason: reason) }
        cb.feedback = { ctx in delegate(ctx)?.engineFeedback() }
        cb.video_stopped = { ctx in delegate(ctx)?.engineVideoStopped() }
        cb.video_frame = { ctx, data, len, ntp in
            guard let data, len > 0 else { return }
            delegate(ctx)?.engineVideoFrame(UnsafeRawBufferPointer(start: data, count: Int(len)), ntpNanos: ntp)
        }
        cb.video_size = { ctx, sw, sh, w, h in
            delegate(ctx)?.engineVideoSize(source: CGSize(width: CGFloat(sw), height: CGFloat(sh)),
                                           size: CGSize(width: CGFloat(w), height: CGFloat(h)))
        }
        cb.video_flush = { ctx in delegate(ctx)?.engineVideoFlush() }
        cb.audio_format = { ctx, ct, spf in delegate(ctx)?.engineAudioFormat(codec: ct, samplesPerFrame: spf) }
        cb.audio_frame = { ctx, data, len, ct, ntp in
            guard let data, len > 0 else { return }
            delegate(ctx)?.engineAudioFrame(UnsafeRawBufferPointer(start: data, count: Int(len)), codec: ct, ntpNanos: ntp)
        }
        cb.audio_flush = { ctx in delegate(ctx)?.engineAudioFlush() }
        cb.volume = { ctx, db in delegate(ctx)?.engineVolume(db: db) }
        cb.show_pin = { ctx, pin in delegate(ctx)?.engineShowPIN(string(pin)) }
        return cb
    }()
}
