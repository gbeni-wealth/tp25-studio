import XCTest
@testable import ProtocolEngine

final class LightColorTests: XCTestCase {
    func testRGBRoundTrip() {
        let red = LightColor(red: 1, green: 0, blue: 0)
        XCTAssertEqual(red.hue, 0, accuracy: 0.5)
        XCTAssertEqual(red.saturation, 1, accuracy: 0.01)
        XCTAssertEqual(red.intensity, 1, accuracy: 0.01)

        let bytes = red.rgbBytes
        XCTAssertEqual(bytes.red, 255)
        XCTAssertEqual(bytes.green, 0)
        XCTAssertEqual(bytes.blue, 0)
    }

    func testHexParsing() {
        XCTAssertEqual(LightColor(hexString: "#FF0000")?.hexString, "FF0000")
        XCTAssertEqual(LightColor(hexString: "00ff00")?.hexString, "00FF00")
        XCTAssertNil(LightColor(hexString: "GGGGGG"))
        XCTAssertNil(LightColor(hexString: "FFF"))
    }

    func testLerpTakesShortestHuePath() {
        let a = LightColor(hue: 350, saturation: 1, intensity: 1)
        let b = LightColor(hue: 10, saturation: 1, intensity: 1)
        let mid = LightColor.lerp(a, b, t: 0.5)
        // Shortest path 350→10 crosses 0, midpoint = 0, not 180.
        XCTAssertEqual(mid.hue, 0, accuracy: 0.5)
    }

    func testDistanceSymmetricAndZeroForSelf() {
        let a = LightColor(hue: 120, saturation: 0.5, intensity: 0.8)
        let b = LightColor(hue: 300, saturation: 1.0, intensity: 0.2)
        XCTAssertEqual(a.distance(to: a), 0, accuracy: 0.0001)
        XCTAssertEqual(a.distance(to: b), b.distance(to: a), accuracy: 0.0001)
    }
}

final class HexDataTests: XCTestCase {
    func testHexInputVariants() {
        let expected = Data([0x7E, 0x00, 0x04, 0xEF])
        XCTAssertEqual(Data(hexInput: "7E 00 04 EF"), expected)
        XCTAssertEqual(Data(hexInput: "7e0004ef"), expected)
        XCTAssertEqual(Data(hexInput: "0x7E,0x00,0x04,0xEF"), expected)
        XCTAssertNil(Data(hexInput: "7E 0"))      // odd nibbles
        XCTAssertNil(Data(hexInput: "ZZ"))
        XCTAssertNil(Data(hexInput: ""))
    }
}

final class ProtocolFamilyTests: XCTestCase {
    func testNeewerChecksum() throws {
        let packet = try ProtocolFamily.neewerStyle.encode(.power(on: true))
        let bytes = [UInt8](packet)
        XCTAssertEqual(bytes.first, 0x78)
        let checksum = UInt8(bytes.dropLast().reduce(0) { ($0 + Int($1)) } & 0xFF)
        XCTAssertEqual(bytes.last, checksum)
    }

    func testElkFraming() throws {
        let packet = try ProtocolFamily.elkBledom.encode(.rgb(red: 255, green: 0, blue: 0))
        let bytes = [UInt8](packet)
        XCTAssertEqual(bytes.first, 0x7E)
        XCTAssertEqual(bytes.last, 0xEF)
        XCTAssertTrue(bytes.contains(0xFF))
    }

    func testTrionesColour() throws {
        let packet = try ProtocolFamily.triones.encode(.rgb(red: 1, green: 2, blue: 3))
        XCTAssertEqual([UInt8](packet), [0x56, 1, 2, 3, 0x00, 0xF0, 0xAA])
    }

    func testUnsupportedThrows() {
        XCTAssertThrowsError(try ProtocolFamily.triones.encode(
            .cct(temperature: .init(kelvin: 5600), brightness: 50)))
    }

    func testProbesAreNonEmptyForKnownFamilies() {
        for family in ProtocolFamily.allCases where family != .custom {
            XCTAssertFalse(family.probes.isEmpty, "\(family) should have probes")
            for probe in family.probes {
                XCTAssertFalse(probe.data.isEmpty, "\(family) probe \(probe.label) empty")
            }
        }
    }
}

final class PacketDiffTests: XCTestCase {
    func testChangingOffsetsDetected() {
        let diff = PacketDiff(packets: [
            Data([0x7E, 0x00, 0x01, 0x10, 0xEF]),
            Data([0x7E, 0x00, 0x01, 0x32, 0xEF]),
            Data([0x7E, 0x00, 0x01, 0x5A, 0xEF]),
        ])
        XCTAssertEqual(diff.changingOffsets, [3])
        XCTAssertEqual(diff.constantOffsets, [0, 1, 2, 4])
    }

    func testMonotonicParameterDetection() {
        let diff = PacketDiff(packets: [
            Data([0xAA, 0x10, 0x05]),
            Data([0xAA, 0x32, 0x09]),
            Data([0xAA, 0x5A, 0x02]),
        ])
        // Byte 1 follows the swept order 16<50<90; byte 2 doesn't.
        XCTAssertEqual(diff.likelyParameterOffsets(sweptValues: [16, 50, 90]), [1])
    }

    func testChecksumDetection() {
        func sumPacket(_ payload: [UInt8]) -> Data {
            Data(payload + [UInt8(payload.reduce(0) { ($0 + Int($1)) } & 0xFF)])
        }
        let diff = PacketDiff(packets: [
            sumPacket([0x78, 0x82, 0x01, 0x10]),
            sumPacket([0x78, 0x82, 0x01, 0x40]),
        ])
        XCTAssertEqual(diff.detectChecksum(), .sumMod256LastByte)
    }

    func testTemplateRenderWithChecksum() {
        let template = CommandTemplate(kind: .brightness,
                                       base: [0x78, 0x82, 0x01, 0x10, 0x0B],
                                       parameterOffsets: [3],
                                       checksum: .sumMod256LastByte)
        let rendered = [UInt8](template.render(parameters: [0x40]))
        XCTAssertEqual(rendered[3], 0x40)
        XCTAssertEqual(rendered[4], UInt8((0x78 + 0x82 + 0x01 + 0x40) & 0xFF))
    }
}

final class ProtocolMapTests: XCTestCase {
    func testEncodeViaFamilyEntry() throws {
        var map = ProtocolMap()
        map.record(ProtocolMapEntry(kind: .rgb, serviceUUID: "FFD5",
                                    characteristicUUID: "FFD9", family: .triones))
        let (data, characteristic) = try map.encode(.rgb(red: 9, green: 8, blue: 7))
        XCTAssertEqual(characteristic, "FFD9")
        XCTAssertEqual([UInt8](data), [0x56, 9, 8, 7, 0x00, 0xF0, 0xAA])
    }

    func testHSIFallsBackToRGBEntry() throws {
        var map = ProtocolMap()
        map.record(ProtocolMapEntry(kind: .rgb, serviceUUID: "FFD5",
                                    characteristicUUID: "FFD9", family: .triones))
        let (data, _) = try map.encode(.hsi(color: LightColor(hue: 0, saturation: 1, intensity: 1)))
        XCTAssertEqual([UInt8](data).first, 0x56)
    }

    func testUnmappedKindThrows() {
        let map = ProtocolMap()
        XCTAssertThrowsError(try map.encode(.power(on: true)))
        XCTAssertFalse(map.isUsable)
    }

    func testPersistenceRoundTrip() throws {
        var map = ProtocolMap(deviceModel: "TP25-test")
        map.record(ProtocolMapEntry(kind: .power, serviceUUID: "FFF0",
                                    characteristicUUID: "FFF3", family: .elkBledom))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("map-\(UUID().uuidString).json")
        try ProtocolMapStore.save(map, to: url)
        let loaded = ProtocolMapStore.load(from: url)
        XCTAssertEqual(loaded?.deviceModel, "TP25-test")
        XCTAssertEqual(loaded?.entries.count, 1)
        XCTAssertEqual(loaded?.entry(for: .power)?.characteristicUUID, "FFF3")
        try? FileManager.default.removeItem(at: url)
    }
}

final class DocGeneratorTests: XCTestCase {
    func testMarkdownContainsConfirmedCommands() {
        var map = ProtocolMap()
        map.record(ProtocolMapEntry(kind: .brightness, serviceUUID: "FFF0",
                                    characteristicUUID: "FFF3", family: .elkBledom,
                                    exampleHex: "7E 00 01 32 EF"))
        let md = ProtocolDocGenerator.markdown(map: map)
        XCTAssertTrue(md.contains("BRIGHTNESS"))
        XCTAssertTrue(md.contains("FFF3"))
        XCTAssertTrue(md.contains("7E 00 01 32 EF"))
    }
}
