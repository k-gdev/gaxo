import Foundation
import Testing
@testable import GaxoCore

@Suite struct DeviceIdentityTests {
    @Test func randomIDIsLocallyAdministeredUnicast() throws {
        for _ in 0..<200 {
            let id = DeviceIdentity.randomDeviceID()
            #expect(id.wholeMatch(of: #/([0-9A-F]{2}:){5}[0-9A-F]{2}/#) != nil, "bad format: \(id)")
            let firstOctet = try #require(UInt8(id.prefix(2), radix: 16))
            #expect(firstOctet & 0x03 == 0x02, "not locally administered unicast: \(id)")
        }
    }

    @Test func identityPersists() throws {
        let defaults = MemoryPreferences()
        let first = DeviceIdentity.loadOrCreate(defaults: defaults)
        let second = DeviceIdentity.loadOrCreate(defaults: defaults)
        #expect(first.deviceID == second.deviceID)
    }
}
