import XCTest
@testable import ProtocolEngine

final class DeviceProfileTests: XCTestCase {
    func testTP25ProfileIsConfirmedAndComplete() {
        let p = SuteFotoProfiles.tp25
        XCTAssertTrue(p.verified)
        XCTAssertTrue(p.physicalPowerOnly)
        XCTAssertEqual(p.controlCharacteristicUUID, "FFE1")
        XCTAssertEqual(p.family, .suteFotoFA)
        for cap in [DeviceCapabilities.cct, .hsi, .rgbcw, .fx] {
            XCTAssertTrue(p.capabilities.contains(cap))
        }
        XCTAssertTrue(p.makeProtocolMap().isUsable)
    }

    func testIdentifyByNamePrefix() {
        XCTAssertEqual(DeviceProfileRegistry.identify(name: "STX25RGB-DJ4A52").modelName,
                       "SuteFoto TP25")
        XCTAssertEqual(DeviceProfileRegistry.identify(name: "SP100-ABCDEF").modelName,
                       "SuteFoto P100")
    }

    func testUnknownSuteFotoGetsGenericFAProfile() {
        // Unknown name but FFE0/FFE1 present → generic SuteFoto FA profile.
        let p = DeviceProfileRegistry.identify(
            name: "MysteryLight",
            serviceUUIDs: ["FFE0", "180F"],
            writableUUIDs: ["FFE1"],
            hasBattery: true)
        XCTAssertEqual(p.family, .suteFotoFA)
        XCTAssertTrue(p.capabilities.contains(.hsi))
        XCTAssertTrue(p.capabilities.contains(.batteryReporting))
        XCTAssertFalse(p.verified)
    }

    func testTrulyUnknownDeviceIsConservative() {
        let p = DeviceProfileRegistry.identify(name: "RandomBLE",
                                               serviceUUIDs: ["1809"],
                                               writableUUIDs: ["2A00"])
        XCTAssertEqual(p.family, .custom)
        XCTAssertFalse(p.capabilities.contains(.hsi))
    }

    func testP100SharesProtocolButIsUnverified() {
        let p = SuteFotoProfiles.p100
        XCTAssertEqual(p.family, .suteFotoFA)           // reuses the command layer
        XCTAssertFalse(p.verified)                       // until a P100 capture confirms
        XCTAssertTrue(p.capabilities.contains(.extendedParameters))
        XCTAssertTrue(p.makeProtocolMap().isUsable)
    }

    func testCapabilitiesDriveProtocolMapKinds() {
        var profile = SuteFotoProfiles.tp25
        profile.capabilities = [.hsi]   // HSI-only hypothetical
        let map = profile.makeProtocolMap()
        XCTAssertNotNil(map.entry(for: .hsi))
        XCTAssertNil(map.entry(for: .rgbcw))
        XCTAssertNil(map.entry(for: .effect))
    }
}
