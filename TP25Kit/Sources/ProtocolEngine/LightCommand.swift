import Foundation

/// High-level intents the app can express. The ProtocolMap + family encoder
/// turn these into raw BLE packets — nothing above this layer touches bytes.
public enum LightCommand: Hashable, Sendable {
    case power(on: Bool)
    case brightness(percent: Int)                       // 0...100
    case cct(temperature: ColorTemperature, brightness: Int)
    case hsi(color: LightColor)
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
    case rgbcw(red: UInt8, green: UInt8, blue: UInt8, cool: UInt8, warm: UInt8)
    case effect(id: Int, speed: Int, brightness: Int)   // FX mode
    case channel(group: Int, channel: Int)              // 6 groups / 12 channels per docs
    case raw(Data)                                      // escape hatch for the Protocol Lab

    public var kind: CommandKind {
        switch self {
        case .power: .power
        case .brightness: .brightness
        case .cct: .cct
        case .hsi: .hsi
        case .rgb: .rgb
        case .rgbcw: .rgbcw
        case .effect: .effect
        case .channel: .channel
        case .raw: .raw
        }
    }
}

/// Categories used by the protocol map and discovery assistant.
public enum CommandKind: String, Codable, CaseIterable, Sendable {
    case power, brightness, cct, hsi, rgb, rgbcw, effect, channel, raw
}
