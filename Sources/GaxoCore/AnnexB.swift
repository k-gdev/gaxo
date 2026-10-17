import Foundation

/// SPS and PPS NAL units (without start codes).
public struct H264ParameterSets: Equatable {
    public var sps: Data
    public var pps: Data

    public init(sps: Data, pps: Data) {
        self.sps = sps
        self.pps = pps
    }
}

/// H.264 Annex-B helpers. The UxPlay engine hands over each frame as Annex-B
/// (00 00 00 01 start codes) with SPS + PPS in front of keyframes;
/// VideoToolbox wants 4-byte big-endian length prefixes (AVCC) instead.
public enum AnnexB {
    /// Payload ranges of the NAL units in `buf`, without their start codes.
    /// Accepts 3- and 4-byte start codes; bytes before the first start code are ignored.
    public static func nalUnits(_ buf: UnsafeRawBufferPointer) -> [Range<Int>] {
        let n = buf.count
        var units: [Range<Int>] = []
        var start: Int?
        var i = 0
        while i + 2 < n {
            if buf[i] == 0, buf[i + 1] == 0, buf[i + 2] == 1 {
                if let s = start {
                    var end = i
                    while end > s, buf[end - 1] == 0 { end -= 1 } // 4-byte code / trailing zeros
                    if end > s { units.append(s..<end) }
                }
                start = i + 3
                i += 3
            } else {
                i += 1
            }
        }
        if let s = start, s < n { units.append(s..<n) }
        return units
    }

    /// NAL unit type (low 5 bits of the first byte).
    public static func type(_ buf: UnsafeRawBufferPointer, _ unit: Range<Int>) -> UInt8 {
        buf[unit.lowerBound] & 0x1F
    }

    /// The NAL units of `buf` whose type is not in `types`, each prefixed with
    /// its length as a 4-byte big-endian integer.
    public static func avcc(_ buf: UnsafeRawBufferPointer, excluding types: Set<UInt8>) -> Data {
        var out = Data(capacity: buf.count)
        for unit in nalUnits(buf) where !types.contains(type(buf, unit)) {
            var length = UInt32(unit.count).bigEndian
            withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
            out.append(contentsOf: UnsafeRawBufferPointer(rebasing: buf[unit]))
        }
        return out
    }

    /// The first SPS (type 7) and PPS (type 8) in `buf`, if both are present.
    public static func parameterSets(in buf: UnsafeRawBufferPointer) -> H264ParameterSets? {
        var sps: Data?
        var pps: Data?
        for unit in nalUnits(buf) {
            switch type(buf, unit) {
            case 7 where sps == nil: sps = Data(UnsafeRawBufferPointer(rebasing: buf[unit]))
            case 8 where pps == nil: pps = Data(UnsafeRawBufferPointer(rebasing: buf[unit]))
            default: break
            }
        }
        guard let sps, let pps else { return nil }
        return H264ParameterSets(sps: sps, pps: pps)
    }
}
