import Foundation
import Testing
@testable import GaxoCore

@Suite struct AnnexBTests {
    private func units(_ bytes: [UInt8]) -> [[UInt8]] {
        bytes.withUnsafeBytes { buf in
            AnnexB.nalUnits(buf).map { Array(bytes[$0]) }
        }
    }

    @Test func splitsThreeAndFourByteStartCodes() {
        let stream: [UInt8] = [0, 0, 0, 1, 0x67, 0xAA, 0xBB,
                               0, 0, 1, 0x68, 0xCC,
                               0, 0, 0, 1, 0x65, 0x01, 0x02, 0x03]
        #expect(units(stream) == [[0x67, 0xAA, 0xBB], [0x68, 0xCC], [0x65, 0x01, 0x02, 0x03]])
    }

    @Test func emptyAndGarbageGiveNoUnits() {
        #expect(units([]).isEmpty)
        #expect(units([0x12, 0x34, 0x56]).isEmpty)
        #expect(units([0, 0, 0, 1]).isEmpty)
    }

    @Test func avccPrefixesLengthsBigEndian() {
        let stream: [UInt8] = [0, 0, 0, 1, 0x67, 0xAA,
                               0, 0, 0, 1, 0x68, 0xBB,
                               0, 0, 0, 1, 0x65, 0x01, 0x02]
        let avcc = stream.withUnsafeBytes { AnnexB.avcc($0, excluding: [7, 8]) }
        #expect(Array(avcc) == [0, 0, 0, 3, 0x65, 0x01, 0x02])
    }

    @Test func findsSpsAndPps() {
        let stream: [UInt8] = [0, 0, 0, 1, 0x67, 0xAA, 0xBB,
                               0, 0, 0, 1, 0x68, 0xCC,
                               0, 0, 0, 1, 0x65, 0x01]
        let sets = stream.withUnsafeBytes { AnnexB.parameterSets(in: $0) }
        #expect(sets == H264ParameterSets(sps: Data([0x67, 0xAA, 0xBB]), pps: Data([0x68, 0xCC])))
        let none: [UInt8] = [0, 0, 0, 1, 0x41, 0x01]
        #expect(none.withUnsafeBytes { AnnexB.parameterSets(in: $0) } == nil)
    }
}
