import Foundation
import SwiftData
import ProtocolEngine
import ThemeEngine

// SwiftData models. All properties are optional or defaulted and there are no
// unique constraints — required for CloudKit-backed stores.

/// What a preset captures — encoded as JSON payload for forward compatibility.
public struct PresetPayload: Codable, Hashable, Sendable {
    public var mode: String = "hsi"                    // LightMode rawValue
    public var color: LightColor?
    public var temperatureKelvin: Int?
    public var brightness: Int?
    public var coolWhite: UInt8?
    public var warmWhite: UInt8?
    public var effectID: Int?
    public var effectSpeed: Int?
    public var themeID: UUID?                          // for theme-based scenes
    public var randomConfig: RandomColourEngine.Config?

    public init() {}
}

@Model
public final class Preset {
    public var name: String = "Untitled"
    public var createdAt: Date = Date.now
    public var modifiedAt: Date = Date.now
    public var isFavourite: Bool = false
    public var payloadData: Data?

    public var payload: PresetPayload {
        get {
            guard let payloadData,
                  let decoded = try? JSONDecoder().decode(PresetPayload.self, from: payloadData)
            else { return PresetPayload() }
            return decoded
        }
        set {
            payloadData = try? JSONEncoder().encode(newValue)
            modifiedAt = .now
        }
    }

    public init(name: String, payload: PresetPayload = PresetPayload()) {
        self.name = name
        self.payloadData = try? JSONEncoder().encode(payload)
    }
}

@Model
public final class CustomTheme {
    public var name: String = "Untitled Theme"
    public var createdAt: Date = Date.now
    public var themeData: Data?

    public var theme: Theme? {
        get {
            guard let themeData else { return nil }
            return try? JSONDecoder().decode(Theme.self, from: themeData)
        }
        set { themeData = try? JSONEncoder().encode(newValue) }
    }

    public init(theme: Theme) {
        self.name = theme.name
        self.themeData = try? JSONEncoder().encode(theme)
    }
}

/// User-facing identity for a physical light (synced across devices).
@Model
public final class DeviceAlias {
    public var deviceUUID: String = ""
    public var alias: String = ""
    public var group: Int = 1
    public var channel: Int = 1

    public init(deviceUUID: String, alias: String, group: Int = 1, channel: Int = 1) {
        self.deviceUUID = deviceUUID
        self.alias = alias
        self.group = group
        self.channel = channel
    }
}

/// A named set of lights ("Interview Kit", "Background Pair").
@Model
public final class SavedGroup {
    public var name: String = "Group"
    public var memberUUIDsJoined: String = ""          // comma-separated device UUIDs

    public var memberUUIDs: [String] {
        get { memberUUIDsJoined.split(separator: ",").map(String.init) }
        set { memberUUIDsJoined = newValue.joined(separator: ",") }
    }

    public init(name: String, memberUUIDs: [String] = []) {
        self.name = name
        self.memberUUIDsJoined = memberUUIDs.joined(separator: ",")
    }
}
