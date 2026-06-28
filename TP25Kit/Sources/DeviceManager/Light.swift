import Foundation
import BluetoothCore
import ProtocolEngine
import Observation

/// Operating modes mirrored from the TP25 manual.
public enum LightMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case cct = "CCT"
    case hsi = "HSI"
    case rgbcw = "RGBCW"
    case fx = "FX"
    public var id: String { rawValue }
}

/// The app-side state of one physical light. The source of truth we *send*;
/// read-back depends on protocol discovery of notify characteristics.
public struct LightState: Codable, Hashable, Sendable {
    public var isOn = true
    public var mode: LightMode = .cct
    public var brightness = 50                          // 0...100
    public var temperature = ColorTemperature(kelvin: 5600)
    public var color = LightColor(hue: 30, saturation: 0.8, intensity: 0.5)
    public var coolWhite: UInt8 = 0
    public var warmWhite: UInt8 = 0
    public var effectID = 0
    public var effectSpeed = 5

    public init() {}
}

/// One light: identity + grouping + live state.
/// Manual: TP25 supports 6 groups and 12 channels.
@Observable
public final class Light: Identifiable {
    public let id: UUID
    public var alias: String
    public var group: Int    // 1...6
    public var channel: Int  // 1...12
    public var state = LightState()
    public var batteryPercent: Int?   // populated if a battery characteristic is discovered

    public let session: BLEDeviceSession
    /// The identified model profile (capabilities, protocol, ranges).
    /// Set at connect time from the advertised name, refined after GATT discovery.
    public var profile: DeviceProfile

    public init(session: BLEDeviceSession, profile: DeviceProfile? = nil,
                alias: String? = nil, group: Int = 1, channel: Int = 1) {
        self.id = session.device.id
        self.session = session
        self.profile = profile ?? DeviceProfileRegistry.identify(name: session.device.name)
        self.alias = alias ?? session.device.name
        self.group = min(max(group, 1), 6)
        self.channel = min(max(channel, 1), 12)
    }

    public var capabilities: DeviceCapabilities { profile.capabilities }
    public func supports(_ capability: DeviceCapabilities) -> Bool {
        profile.capabilities.contains(capability)
    }

    /// Re-identify using the discovered GATT structure (battery, writables).
    public func refineProfile() {
        let hasBattery = session.services.contains { $0.id.uppercased().contains("180F") }
        profile = DeviceProfileRegistry.identify(
            name: session.device.name,
            serviceUUIDs: session.services.map(\.id),
            writableUUIDs: session.writableCharacteristics.map(\.characteristic),
            hasBattery: hasBattery)
    }

    public var name: String { alias }
    public var rssi: Int { session.device.rssi }
    public var isConnected: Bool { session.connectionState == .ready }
}
