import Foundation
import Observation

/// Records an entire reverse-engineering session — device metadata, GATT
/// structure, and all BLE traffic — and exports it as JSON or CSV.
@Observable
public final class SessionRecorder {
    public struct Session: Codable, Identifiable {
        public var id: UUID
        public var startedAt: Date
        public var endedAt: Date?
        public var deviceName: String
        public var deviceUUID: String
        public var advertisement: [String: String]
        public var services: [ServiceSnapshot]
        public var packets: [BLEPacket]
        public var notes: String

        public struct ServiceSnapshot: Codable {
            public var uuid: String
            public var characteristics: [CharacteristicSnapshot]
        }
        public struct CharacteristicSnapshot: Codable {
            public var uuid: String
            public var properties: String
            public var lastValueHex: String?
        }
    }

    public private(set) var current: Session?
    public private(set) var savedSessions: [URL] = []
    public var isRecording: Bool { current != nil && current?.endedAt == nil }

    public static var sessionsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TP25Studio/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public init() {
        refreshSavedSessions()
    }

    public func start(device: DiscoveredDevice, services: [GATTServiceInfo]) {
        current = Session(
            id: UUID(),
            startedAt: Date(),
            endedAt: nil,
            deviceName: device.name,
            deviceUUID: device.id.uuidString,
            advertisement: device.advertisementData,
            services: services.map { service in
                .init(uuid: service.id, characteristics: service.characteristics.map {
                    .init(uuid: $0.id, properties: $0.propertyDescription,
                          lastValueHex: $0.lastValue?.map { String(format: "%02X", $0) }.joined(separator: " "))
                })
            },
            packets: [],
            notes: ""
        )
    }

    public func capture(_ packets: [BLEPacket]) {
        current?.packets = packets
    }

    @discardableResult
    public func stopAndSave(notes: String = "") throws -> URL? {
        guard var session = current else { return nil }
        session.endedAt = Date()
        session.notes = notes
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let name = "session-\(Int(session.startedAt.timeIntervalSince1970)).json"
        let url = Self.sessionsDirectory.appendingPathComponent(name)
        try encoder.encode(session).write(to: url, options: .atomic)
        current = nil
        refreshSavedSessions()
        return url
    }

    public func discard() { current = nil }

    public func refreshSavedSessions() {
        savedSessions = (try? FileManager.default.contentsOfDirectory(
            at: Self.sessionsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }

    public static func load(_ url: URL) -> Session? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Session.self, from: data)
    }

    // MARK: Export

    public static func csv(for packets: [BLEPacket]) -> String {
        var csv = "timestamp,direction,service,characteristic,hex,annotation\n"
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for p in packets {
            let annotation = (p.annotation ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(df.string(from: p.timestamp)),\(p.direction.rawValue),"
                + "\(p.serviceUUID),\(p.characteristicUUID),\(p.hex),\"\(annotation)\"\n"
        }
        return csv
    }

    @discardableResult
    public static func exportCSV(packets: [BLEPacket], to url: URL? = nil) throws -> URL {
        let target = url ?? sessionsDirectory
            .appendingPathComponent("packets-\(Int(Date().timeIntervalSince1970)).csv")
        try csv(for: packets).data(using: .utf8)!.write(to: target, options: .atomic)
        return target
    }
}
