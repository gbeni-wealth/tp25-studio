import Foundation

/// A light we've connected to before. Persisted locally so reconnecting is one
/// tap, the custom name sticks, and the same physical light never shows up as a
/// duplicate entry. Keyed by the CoreBluetooth peripheral UUID (stable per-Mac).
public struct KnownLight: Codable, Identifiable, Hashable, Sendable {
    public var id: String          // peripheral UUID string
    public var name: String        // user-chosen name (defaults to advertised name)
    public var modelName: String   // identified profile, for the registry list
    public var group: Int
    public var channel: Int
    public var lastConnected: Date

    public init(id: String, name: String, modelName: String = "",
                group: Int = 1, channel: Int = 1, lastConnected: Date = .now) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.group = group
        self.channel = channel
        self.lastConnected = lastConnected
    }
}

/// Persistent registry of lights the user has connected to. Backed by
/// UserDefaults (a small JSON blob) so it works without SwiftData/CloudKit and
/// survives relaunch. One entry per physical light — no duplicates.
/// Accessed only from the main thread (UI + CoreBluetooth main-queue callbacks).
@Observable
public final class KnownLightsStore {
    public static let shared = KnownLightsStore()

    private let defaultsKey = "tp25.knownLights.v1"
    private var byID: [String: KnownLight] = [:]

    public init() { load() }

    /// All known lights, most-recently-connected first.
    public var all: [KnownLight] {
        byID.values.sorted { $0.lastConnected > $1.lastConnected }
    }

    public func known(_ id: UUID) -> KnownLight? { byID[id.uuidString] }
    public func known(_ id: String) -> KnownLight? { byID[id] }

    /// Record (or refresh) a light on connect without clobbering a user name.
    public func record(id: UUID, defaultName: String, modelName: String,
                       group: Int, channel: Int) {
        let key = id.uuidString
        if var existing = byID[key] {
            existing.modelName = modelName
            existing.lastConnected = .now
            // Keep the user's name/group/channel; only fill blanks.
            if existing.name.isEmpty { existing.name = defaultName }
            byID[key] = existing
        } else {
            byID[key] = KnownLight(id: key, name: defaultName, modelName: modelName,
                                   group: group, channel: channel)
        }
        save()
    }

    public func rename(_ id: UUID, to name: String) {
        guard var entry = byID[id.uuidString] else { return }
        entry.name = name
        byID[id.uuidString] = entry
        save()
    }

    public func setGroup(_ id: UUID, group: Int) {
        guard var entry = byID[id.uuidString] else { return }
        entry.group = group
        byID[id.uuidString] = entry
        save()
    }

    public func setChannel(_ id: UUID, channel: Int) {
        guard var entry = byID[id.uuidString] else { return }
        entry.channel = channel
        byID[id.uuidString] = entry
        save()
    }

    public func forget(_ id: UUID) {
        byID.removeValue(forKey: id.uuidString)
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([KnownLight].self, from: data)
        else { return }
        byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(byID.values)) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
