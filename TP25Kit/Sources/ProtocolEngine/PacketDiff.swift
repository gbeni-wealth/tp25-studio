import Foundation

/// Byte-level comparison of captured packets — the core reverse-engineering tool.
/// Compare e.g. two brightness packets to find which byte carries the value.
public struct PacketDiff: Sendable {
    public struct ByteColumn: Identifiable, Sendable {
        public let id: Int            // byte offset
        public let values: [UInt8?]   // value in each packet (nil if packet shorter)
        public let isChanging: Bool
    }

    public let packets: [Data]
    public let columns: [ByteColumn]
    /// Offsets whose value differs across the compared packets.
    public let changingOffsets: [Int]
    /// Offsets identical in every packet (framing/header candidates).
    public let constantOffsets: [Int]

    public init(packets: [Data]) {
        self.packets = packets
        let maxLen = packets.map(\.count).max() ?? 0
        var cols: [ByteColumn] = []
        for offset in 0..<maxLen {
            let values: [UInt8?] = packets.map { $0.count > offset ? $0[$0.startIndex + offset] : nil }
            let distinct = Set(values.compactMap { $0 })
            cols.append(ByteColumn(id: offset, values: values, isChanging: distinct.count > 1 || values.contains(nil)))
        }
        self.columns = cols
        self.changingOffsets = cols.filter(\.isChanging).map(\.id)
        self.constantOffsets = cols.filter { !$0.isChanging }.map(\.id)
    }

    /// Heuristic: if exactly one byte changes monotonically with a swept parameter
    /// (e.g. brightness 10→50→90), it's almost certainly the parameter byte.
    public func likelyParameterOffsets(sweptValues: [Int]? = nil) -> [Int] {
        guard packets.count >= 2 else { return [] }
        guard let swept = sweptValues, swept.count == packets.count else { return changingOffsets }
        return changingOffsets.filter { offset in
            let bytes = packets.compactMap { $0.count > offset ? Int($0[$0.startIndex + offset]) : nil }
            guard bytes.count == swept.count else { return false }
            // Same ordering as the swept parameter?
            let sweptOrder = swept.enumerated().sorted { $0.element < $1.element }.map(\.offset)
            let byteOrder = bytes.enumerated().sorted { $0.element < $1.element }.map(\.offset)
            return sweptOrder == byteOrder
        }
    }

    /// Detect a trailing checksum byte across the packets.
    public func detectChecksum() -> CommandTemplate.ChecksumRule {
        guard packets.allSatisfy({ $0.count >= 2 }) else { return .none }
        let allSum = packets.allSatisfy { p in
            let bytes = [UInt8](p)
            return bytes.last == UInt8(bytes.dropLast().reduce(0) { ($0 + Int($1)) } & 0xFF)
        }
        if allSum { return .sumMod256LastByte }
        let allXor = packets.allSatisfy { p in
            let bytes = [UInt8](p)
            return bytes.last == bytes.dropLast().reduce(0, ^)
        }
        return allXor ? .xorLastByte : .none
    }

    /// Build a reusable template from the diff (base = first packet).
    public func makeTemplate(kind: CommandKind, notes: String = "") -> CommandTemplate? {
        guard let first = packets.first else { return nil }
        let checksum = detectChecksum()
        // Exclude the checksum byte from parameter slots.
        let offsets = changingOffsets.filter { checksum == .none || $0 != first.count - 1 }
        return CommandTemplate(kind: kind, base: [UInt8](first),
                               parameterOffsets: offsets, checksum: checksum, notes: notes)
    }
}

public extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Parse "7E 00 04 F0", "7e0004f0", "0x7E,0x00…" → Data. Nil on invalid input.
    init?(hexInput: String) {
        let cleaned = hexInput
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")
            .components(separatedBy: CharacterSet(charactersIn: " ,;:-\n\t"))
            .joined()
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return nil }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
