import Foundation
import CoreBluetooth

/// A device seen during scanning, with everything Phase 0 needs to display.
public struct DiscoveredDevice: Identifiable, Hashable {
    public let id: UUID                       // CoreBluetooth peripheral identifier
    public var name: String
    public var rssi: Int
    public var advertisementData: [String: String]
    public var manufacturerData: Data?
    public var serviceUUIDs: [String]
    public var isConnectable: Bool
    public var lastSeen: Date

    public init(id: UUID, name: String, rssi: Int, advertisementData: [String: String],
                manufacturerData: Data?, serviceUUIDs: [String], isConnectable: Bool,
                lastSeen: Date) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.advertisementData = advertisementData
        self.manufacturerData = manufacturerData
        self.serviceUUIDs = serviceUUIDs
        self.isConnectable = isConnectable
        self.lastSeen = lastSeen
    }

    public var manufacturerHex: String? { manufacturerData?.hexAsciiDump }

    /// Heuristic: does this look like a SuteFoto/SS LED-class light?
    /// "STX25RG…" is the observed advertised name of the SuteFoto TP25.
    public var looksLikeLight: Bool {
        let n = name.uppercased()
        return ["TP25", "STX25", "X25RG", "SUTEFOTO", "SS-", "SSLED", "SS LED", "NEEWER", "NW-"]
            .contains { n.contains($0) }
    }
}

public struct GATTCharacteristicInfo: Identifiable, Hashable {
    public let id: String                     // characteristic UUID string
    public let serviceUUID: String
    /// CBCharacteristicProperties isn't Hashable — store the raw value.
    public var propertiesRawValue: UInt
    public var lastValue: Data?
    public var isNotifying: Bool

    public var properties: CBCharacteristicProperties {
        CBCharacteristicProperties(rawValue: propertiesRawValue)
    }

    public init(id: String, serviceUUID: String, properties: CBCharacteristicProperties,
                lastValue: Data? = nil, isNotifying: Bool = false) {
        self.id = id
        self.serviceUUID = serviceUUID
        self.propertiesRawValue = properties.rawValue
        self.lastValue = lastValue
        self.isNotifying = isNotifying
    }

    public var propertyDescription: String {
        var parts: [String] = []
        if properties.contains(.read) { parts.append("read") }
        if properties.contains(.write) { parts.append("write") }
        if properties.contains(.writeWithoutResponse) { parts.append("writeNR") }
        if properties.contains(.notify) { parts.append("notify") }
        if properties.contains(.indicate) { parts.append("indicate") }
        if properties.contains(.broadcast) { parts.append("broadcast") }
        return parts.joined(separator: " · ")
    }

    public var isWritable: Bool {
        properties.contains(.write) || properties.contains(.writeWithoutResponse)
    }
}

public struct GATTServiceInfo: Identifiable, Hashable {
    public let id: String                     // service UUID string
    public var isPrimary: Bool
    public var characteristics: [GATTCharacteristicInfo]
}

/// One captured BLE operation — the unit of the packet monitor and recorder.
public struct BLEPacket: Identifiable, Hashable, Codable {
    public enum Direction: String, Codable {
        case write, writeNoResponse, read, notification
    }

    public let id: UUID
    public let timestamp: Date
    public let direction: Direction
    public let serviceUUID: String
    public let characteristicUUID: String
    public let data: Data
    public var annotation: String?           // e.g. "brightness sweep step 3"

    public init(direction: Direction, serviceUUID: String, characteristicUUID: String,
                data: Data, annotation: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.direction = direction
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.data = data
        self.annotation = annotation
    }

    public var hex: String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

public extension Data {
    /// "4C 00 10 05 | L..." style dump for advertisement payloads.
    var hexAsciiDump: String {
        let hex = map { String(format: "%02X", $0) }.joined(separator: " ")
        let ascii = map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
        return "\(hex) | \(ascii)"
    }
}
