import XCTest
@testable import DeveloperTools
@testable import BluetoothCore

final class ConsoleCommandTests: XCTestCase {
    func testHexParsing() {
        guard case .data(let data, _) = ConsoleCommand.parse("7E 00 04 01 EF") else {
            return XCTFail("hex should parse")
        }
        XCTAssertEqual([UInt8](data), [0x7E, 0x00, 0x04, 0x01, 0xEF])
    }

    func testUTF8Literal() {
        guard case .data(let data, _) = ConsoleCommand.parse("\"on\"") else {
            return XCTFail("quoted string should parse")
        }
        XCTAssertEqual(data, Data("on".utf8))

        guard case .data(let data2, _) = ConsoleCommand.parse("utf8:hello") else {
            return XCTFail("utf8: prefix should parse")
        }
        XCTAssertEqual(data2, Data("hello".utf8))
    }

    func testPresetCommands() {
        guard case .data(let data, _) = ConsoleCommand.parse("red@triones") else {
            return XCTFail("preset should parse")
        }
        XCTAssertEqual([UInt8](data), [0x56, 0xFF, 0x00, 0x00, 0x00, 0xF0, 0xAA])

        guard case .data(let bright, _) = ConsoleCommand.parse("bright-30@elk") else {
            return XCTFail("bright preset should parse")
        }
        XCTAssertEqual([UInt8](bright)[3], 30)
    }

    func testErrors() {
        guard case .error = ConsoleCommand.parse("") else { return XCTFail() }
        guard case .error = ConsoleCommand.parse("zz zz") else { return XCTFail() }
        guard case .error = ConsoleCommand.parse("red@unknownfamily") else { return XCTFail() }
        guard case .error = ConsoleCommand.parse("cct-5600@triones") else {
            return XCTFail("triones can't encode CCT — should error")
        }
    }
}

final class SessionExportTests: XCTestCase {
    func testCSVExport() {
        let packets = [
            BLEPacket(direction: .write, serviceUUID: "FFF0", characteristicUUID: "FFF3",
                      data: Data([0x7E, 0x00]), annotation: "test \"quoted\""),
            BLEPacket(direction: .notification, serviceUUID: "FFF0", characteristicUUID: "FFF4",
                      data: Data([0xAB])),
        ]
        let csv = SessionRecorder.csv(for: packets)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 3) // header + 2 rows
        XCTAssertTrue(lines[0].hasPrefix("timestamp,direction,service,characteristic,hex"))
        XCTAssertTrue(csv.contains("7E 00"))
        XCTAssertTrue(csv.contains("\"\"quoted\"\""), "quotes must be CSV-escaped")
        XCTAssertTrue(csv.contains("notification"))
    }
}
