import Foundation
import BluetoothCore
import ProtocolEngine

/// Sends high-level commands to one light through the discovered ProtocolMap.
/// Also adapts the BLE session to ProtocolEngine's CommandTransport so the
/// discovery assistant can drive the same connection.
public final class LightController: CommandTransport {
    public let light: Light
    public var map: ProtocolMap

    public init(light: Light, map: ProtocolMap) {
        self.light = light
        self.map = map
    }

    // MARK: CommandTransport

    public var writableCharacteristics: [(service: String, characteristic: String, writeWithoutResponse: Bool)] {
        light.session.writableCharacteristics
    }

    public func write(_ data: Data, toCharacteristic uuid: String) async throws {
        try await light.session.write(data, characteristicUUID: uuid)
    }

    // MARK: High-level control

    /// Encode via the protocol map, send, and update local state on success.
    public func send(_ command: LightCommand, annotation: String? = nil) async throws {
        let effective = resolve(command)
        let (data, characteristicUUID) = try map.encode(effective)
        try await light.session.write(data, characteristicUUID: characteristicUUID,
                                      annotation: annotation ?? effective.kind.rawValue)
        apply(command, to: &light.state)   // keep UI state in terms of the original intent
    }

    /// The TP25 has no standalone power or brightness command — both are the
    /// *intensity field of the active mode*. Translate them into a full
    /// mode command using the light's current state.
    private func resolve(_ command: LightCommand) -> LightCommand {
        switch command {
        case .power(let on):
            guard map.entry(for: .power) == nil else { return command }
            let level = on ? (light.state.brightness > 0 ? light.state.brightness : 100) : 0
            return resolve(.brightness(percent: level))

        case .brightness(let percent):
            guard map.entry(for: .brightness) == nil else { return command }
            // Re-issue the active mode at the new intensity.
            switch light.state.mode {
            case .cct:
                return .cct(temperature: light.state.temperature, brightness: percent)
            case .hsi:
                var c = light.state.color
                c.intensity = Double(percent) / 100
                return .hsi(color: c)
            case .rgbcw:
                return .rgbcw(red: light.state.color.rgbBytes.red,
                              green: light.state.color.rgbBytes.green,
                              blue: light.state.color.rgbBytes.blue,
                              cool: light.state.coolWhite, warm: light.state.warmWhite)
            case .fx:
                return .effect(id: light.state.effectID, speed: light.state.effectSpeed,
                               brightness: percent)
            }

        default:
            return command
        }
    }

    private func apply(_ command: LightCommand, to state: inout LightState) {
        switch command {
        case .power(let on):
            state.isOn = on
        case .brightness(let p):
            state.brightness = p
            state.color.intensity = Double(p) / 100
        case .cct(let t, let b):
            state.mode = .cct
            state.temperature = t
            state.brightness = b
        case .hsi(let c):
            state.mode = .hsi
            state.color = c
            state.brightness = Int(c.intensity * 100)
        case .rgb(let r, let g, let b):
            state.mode = .hsi
            state.color = LightColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        case .rgbcw(let r, let g, let b, let cw, let ww):
            state.mode = .rgbcw
            state.color = LightColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
            state.coolWhite = cw
            state.warmWhite = ww
        case .effect(let id, let speed, let brightness):
            state.mode = .fx
            state.effectID = id
            state.effectSpeed = speed
            state.brightness = brightness
        case .channel(let g, let c):
            light.group = g
            light.channel = c
        case .raw:
            break
        }
    }
}
