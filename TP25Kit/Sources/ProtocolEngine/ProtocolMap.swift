import Foundation

/// A learned command template: a byte pattern with parameter slots,
/// captured during discovery (e.g. from diffing brightness packets).
public struct CommandTemplate: Codable, Hashable, Sendable {
    public var kind: CommandKind
    /// Base packet bytes.
    public var base: [UInt8]
    /// Byte offsets that vary with the parameter (e.g. brightness byte at index 3).
    public var parameterOffsets: [Int]
    /// Optional checksum rule applied after substitution.
    public var checksum: ChecksumRule?
    public var notes: String

    public enum ChecksumRule: String, Codable, Sendable {
        case none
        case sumMod256LastByte   // last byte = sum of preceding bytes & 0xFF
        case xorLastByte         // last byte = XOR of preceding bytes
    }

    public init(kind: CommandKind, base: [UInt8], parameterOffsets: [Int] = [],
                checksum: ChecksumRule? = nil, notes: String = "") {
        self.kind = kind
        self.base = base
        self.parameterOffsets = parameterOffsets
        self.checksum = checksum
        self.notes = notes
    }

    /// Substitute parameter bytes (in offset order) and re-checksum.
    public func render(parameters: [UInt8]) -> Data {
        var bytes = base
        for (i, offset) in parameterOffsets.enumerated() where i < parameters.count && offset < bytes.count {
            bytes[offset] = parameters[i]
        }
        switch checksum {
        case .sumMod256LastByte where bytes.count > 1:
            bytes[bytes.count - 1] = UInt8(bytes.dropLast().reduce(0) { ($0 + Int($1)) } & 0xFF)
        case .xorLastByte where bytes.count > 1:
            bytes[bytes.count - 1] = bytes.dropLast().reduce(0, ^)
        default:
            break
        }
        return Data(bytes)
    }
}

/// One confirmed mapping: this command kind works on this characteristic.
public struct ProtocolMapEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: CommandKind
    public var serviceUUID: String
    public var characteristicUUID: String
    /// Family encoder to use, or `.custom` with a learned template.
    public var family: ProtocolFamily
    public var template: CommandTemplate?
    public var exampleHex: String
    public var confirmedAt: Date
    public var notes: String

    public init(kind: CommandKind, serviceUUID: String, characteristicUUID: String,
                family: ProtocolFamily, template: CommandTemplate? = nil,
                exampleHex: String = "", notes: String = "") {
        self.id = UUID()
        self.kind = kind
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.family = family
        self.template = template
        self.exampleHex = exampleHex
        self.confirmedAt = Date()
        self.notes = notes
    }
}

/// The discovered protocol for one device model (e.g. "SuteFoto TP25").
/// Built up by the discovery assistant; persisted as JSON; exported as markdown.
public struct ProtocolMap: Codable, Sendable {
    public var deviceModel: String
    public var deviceNamePrefixes: [String]
    public var entries: [ProtocolMapEntry]
    public var cctRange: ClosedRange<Int>
    public var updatedAt: Date

    public init(deviceModel: String = "SuteFoto TP25",
                deviceNamePrefixes: [String] = [],
                entries: [ProtocolMapEntry] = [],
                cctRange: ClosedRange<Int> = ColorTemperature.assumedRange) {
        self.deviceModel = deviceModel
        self.deviceNamePrefixes = deviceNamePrefixes
        self.entries = entries
        self.cctRange = cctRange
        self.updatedAt = Date()
    }

    public func entry(for kind: CommandKind) -> ProtocolMapEntry? {
        entries.first { $0.kind == kind }
    }

    /// The confirmed SuteFoto TP25 protocol (FA … 8A on FFE1), decoded from a
    /// real capture of the official app. Derived from the device profile so
    /// every model stays in sync with one source of truth.
    public static var suteFotoTP25: ProtocolMap {
        SuteFotoProfiles.tp25.makeProtocolMap()
    }

    public var isUsable: Bool {
        entry(for: .power) != nil || entry(for: .rgb) != nil
            || entry(for: .hsi) != nil || entry(for: .brightness) != nil
    }

    public mutating func record(_ entry: ProtocolMapEntry) {
        entries.removeAll { $0.kind == entry.kind }
        entries.append(entry)
        updatedAt = Date()
    }

    /// Encode a high-level command using the confirmed entry for its kind.
    /// Returns the packet and the target characteristic UUID.
    public func encode(_ command: LightCommand) throws -> (data: Data, characteristicUUID: String) {
        if case .raw(let data) = command {
            guard let target = entries.first else { throw ProtocolEncodingError.noLearnedTemplate(.raw) }
            return (data, target.characteristicUUID)
        }
        guard let entry = entry(for: command.kind) ?? fallbackEntry(for: command.kind) else {
            throw ProtocolEncodingError.noLearnedTemplate(command.kind)
        }
        if entry.family != .custom {
            return (try entry.family.encode(command), entry.characteristicUUID)
        }
        guard let template = entry.template else {
            throw ProtocolEncodingError.noLearnedTemplate(command.kind)
        }
        return (template.render(parameters: parameters(for: command)), entry.characteristicUUID)
    }

    /// HSI/RGB are interchangeable fallbacks for one another.
    private func fallbackEntry(for kind: CommandKind) -> ProtocolMapEntry? {
        switch kind {
        case .rgb: entry(for: .hsi)
        case .hsi: entry(for: .rgb)
        default: nil
        }
    }

    private func parameters(for command: LightCommand) -> [UInt8] {
        switch command {
        case .power(let on): [on ? 1 : 0]
        case .brightness(let p): [UInt8(clamping: p)]
        case .cct(let t, let b): [UInt8(clamping: b), UInt8(clamping: t.kelvin / 100)]
        case .hsi(let c):
            [UInt8(Int(c.hue.rounded()) & 0xFF), UInt8((Int(c.hue.rounded()) >> 8) & 0xFF),
             UInt8(clamping: Int(c.saturation * 100)), UInt8(clamping: Int(c.intensity * 100))]
        case .rgb(let r, let g, let b): [r, g, b]
        case .rgbcw(let r, let g, let b, let cw, let ww): [r, g, b, cw, ww]
        case .effect(let id, let speed, let b):
            [UInt8(clamping: id), UInt8(clamping: speed), UInt8(clamping: b)]
        case .channel(let g, let c): [UInt8(clamping: g), UInt8(clamping: c)]
        case .raw(let d): [UInt8](d)
        }
    }
}

// MARK: - Persistence

public enum ProtocolMapStore {
    public static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TP25Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("protocol-map.json")
    }

    public static func load(from url: URL = defaultURL) -> ProtocolMap? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProtocolMap.self, from: data)
    }

    public static func save(_ map: ProtocolMap, to url: URL = defaultURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(map).write(to: url, options: .atomic)
    }
}
