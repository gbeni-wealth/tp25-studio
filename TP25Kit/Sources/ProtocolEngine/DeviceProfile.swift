import Foundation

/// What a connected light can do. The UI shows only the supported features.
public struct DeviceCapabilities: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let power              = DeviceCapabilities(rawValue: 1 << 0)
    public static let brightness         = DeviceCapabilities(rawValue: 1 << 1)
    public static let cct                = DeviceCapabilities(rawValue: 1 << 2)
    public static let hsi                = DeviceCapabilities(rawValue: 1 << 3)
    public static let rgbcw              = DeviceCapabilities(rawValue: 1 << 4)
    public static let fx                 = DeviceCapabilities(rawValue: 1 << 5)
    public static let groups             = DeviceCapabilities(rawValue: 1 << 6)
    public static let channels           = DeviceCapabilities(rawValue: 1 << 7)
    public static let batteryReporting   = DeviceCapabilities(rawValue: 1 << 8)
    /// Model-specific extras (e.g. P100's additional parameters).
    public static let extendedParameters = DeviceCapabilities(rawValue: 1 << 9)

    /// The TP25/P100 baseline (power is physical-only, so not advertised as a
    /// BLE capability — it's synthesised from brightness).
    public static let suteFotoBaseline: DeviceCapabilities =
        [.brightness, .cct, .hsi, .rgbcw, .fx, .groups, .channels]

    public var labels: [String] {
        var out: [String] = []
        if contains(.brightness) { out.append("Brightness") }
        if contains(.cct) { out.append("CCT") }
        if contains(.hsi) { out.append("HSI") }
        if contains(.rgbcw) { out.append("RGBCW") }
        if contains(.fx) { out.append("FX") }
        if contains(.groups) { out.append("Groups") }
        if contains(.channels) { out.append("Channels") }
        if contains(.batteryReporting) { out.append("Battery") }
        if contains(.extendedParameters) { out.append("Extended") }
        return out
    }
}

/// A SuteFoto (or compatible) light model: how to talk to it, what it can do,
/// and how to recognise it. New models are added here — never hardcode a model
/// into the control or UI layers.
public struct DeviceProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: String { modelName }

    public var modelName: String
    /// Advertised-name prefixes that identify this model (case-insensitive).
    public var namePrefixes: [String]
    public var family: ProtocolFamily
    public var serviceUUID: String
    public var controlCharacteristicUUID: String
    public var capabilities: DeviceCapabilities
    public var cctRange: ClosedRange<Int>
    /// TP25-class lights power on/off via a hardware switch, not BLE.
    public var physicalPowerOnly: Bool
    /// FX effect IDs this model exposes (app grid order). Empty = use defaults.
    public var fxEffectIDs: [Int]
    /// `true` for profiles confirmed on real hardware; `false` = assumed
    /// (shares a sibling's protocol until verified by capture).
    public var verified: Bool

    public init(modelName: String, namePrefixes: [String],
                family: ProtocolFamily, serviceUUID: String, controlCharacteristicUUID: String,
                capabilities: DeviceCapabilities, cctRange: ClosedRange<Int>,
                physicalPowerOnly: Bool, fxEffectIDs: [Int] = Array(1...10),
                verified: Bool) {
        self.modelName = modelName
        self.namePrefixes = namePrefixes
        self.family = family
        self.serviceUUID = serviceUUID
        self.controlCharacteristicUUID = controlCharacteristicUUID
        self.capabilities = capabilities
        self.cctRange = cctRange
        self.physicalPowerOnly = physicalPowerOnly
        self.fxEffectIDs = fxEffectIDs
        self.verified = verified
    }

    /// Build the command map for this profile (shared FA family across models).
    public func makeProtocolMap() -> ProtocolMap {
        var map = ProtocolMap(deviceModel: modelName,
                              deviceNamePrefixes: namePrefixes,
                              cctRange: cctRange)
        var kinds: [CommandKind] = []
        if capabilities.contains(.cct) { kinds.append(.cct) }
        if capabilities.contains(.hsi) { kinds += [.hsi, .rgb] }
        if capabilities.contains(.rgbcw) { kinds.append(.rgbcw) }
        if capabilities.contains(.fx) { kinds.append(.effect) }
        for kind in kinds {
            map.record(ProtocolMapEntry(kind: kind, serviceUUID: serviceUUID,
                                        characteristicUUID: controlCharacteristicUUID,
                                        family: family,
                                        notes: verified ? "confirmed" : "assumed from \(modelName) family"))
        }
        return map
    }
}

// MARK: - Built-in profiles + registry

public enum SuteFotoProfiles {
    /// Confirmed by full BLE capture of the official app (2026-06-11).
    public static let tp25 = DeviceProfile(
        modelName: "SuteFoto TP25",
        namePrefixes: ["STX25", "TP25"],
        family: .suteFotoFA,
        serviceUUID: "FFE0", controlCharacteristicUUID: "FFE1",
        capabilities: DeviceCapabilities.suteFotoBaseline.union(.batteryReporting),
        cctRange: 2800...10000,
        physicalPowerOnly: true,
        verified: true
    )

    /// Assumed to share the TP25's FA…8A protocol (SuteFoto reuses firmware
    /// across models). Marked unverified until a P100 capture confirms it; the
    /// app will still try the shared command layer and the user confirms live.
    public static let p100 = DeviceProfile(
        modelName: "SuteFoto P100",
        namePrefixes: ["STX100", "SP100", "P100", "STXP100"],
        family: .suteFotoFA,
        serviceUUID: "FFE0", controlCharacteristicUUID: "FFE1",
        capabilities: DeviceCapabilities.suteFotoBaseline
            .union(.batteryReporting).union(.extendedParameters),
        cctRange: 2700...10000,
        physicalPowerOnly: false,   // higher-end models often support BLE power
        verified: false
    )

    public static let all: [DeviceProfile] = [tp25, p100]
}

/// Identifies the model of a connected/scanned device and builds its profile.
/// Unknown SuteFoto-looking devices get an auto-generated generic profile so
/// they're still usable and recordable for later refinement.
public enum DeviceProfileRegistry {
    /// Match by advertised name prefix.
    public static func profile(forName name: String) -> DeviceProfile? {
        let n = name.uppercased()
        return SuteFotoProfiles.all.first { p in
            p.namePrefixes.contains { n.contains($0.uppercased()) }
        }
    }

    /// Best-effort identification using the name first, then GATT structure.
    /// `serviceUUIDs` / `writableUUIDs` come from the connected session.
    public static func identify(name: String,
                                serviceUUIDs: [String] = [],
                                writableUUIDs: [String] = [],
                                hasBattery: Bool = false) -> DeviceProfile {
        if let known = profile(forName: name) {
            var p = known
            if hasBattery { p.capabilities.insert(.batteryReporting) }
            return p
        }
        // Unknown but SuteFoto-shaped (FFE0/FFE1 present) → generic FA profile.
        let upper = (serviceUUIDs + writableUUIDs).map { $0.uppercased() }
        let control = writableUUIDs.first { $0.uppercased().contains("FFE1") }
            ?? writableUUIDs.first ?? "FFE1"
        let looksSuteFoto = upper.contains { $0.contains("FFE0") || $0.contains("FFE1") }
        var caps: DeviceCapabilities = looksSuteFoto ? .suteFotoBaseline : [.brightness]
        if hasBattery { caps.insert(.batteryReporting) }
        return DeviceProfile(
            modelName: looksSuteFoto ? "SuteFoto (unknown model)" : "Unknown light",
            namePrefixes: [],
            family: looksSuteFoto ? .suteFotoFA : .custom,
            serviceUUID: serviceUUIDs.first ?? "FFE0",
            controlCharacteristicUUID: control,
            capabilities: caps,
            cctRange: ColorTemperature.assumedRange,
            physicalPowerOnly: true,
            verified: false
        )
    }
}
