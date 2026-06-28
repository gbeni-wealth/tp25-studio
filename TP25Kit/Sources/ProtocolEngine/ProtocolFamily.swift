import Foundation

/// Known BLE LED-light protocol families seen in consumer RGB lights.
/// These are *candidates to probe* during discovery — never assumed.
/// The SuteFoto "SS LED Video Light" app drives TP25-class panels; until a
/// session is captured we test each family's safe probes and let the user
/// confirm visually.
public enum ProtocolFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Neewer-style: write char 69400002-…, packets `78 <tag> <len> <payload…> <checksum>`
    /// where checksum = sum of all preceding bytes & 0xFF. Many video panels clone this.
    case neewerStyle
    /// ELK-BLEDOM style: service FFF0, write FFF3, packets framed `7E … EF`.
    case elkBledom
    /// Triones / HappyLighting style: service FFD5, write FFD9, `56 RR GG BB 00 F0 AA`.
    case triones
    /// SuteFoto TP25 ("SS LED Video Light"): service FFE0, write/notify FFE1.
    /// Frame `FA <cmd> 00 00 00 <data…> <checksum> 8A`, checksum = sum(cmd…data)&0xFF.
    /// Decoded from a real capture: 06=CCT, 07=HSI, 08=RGBCW, 09=FX. (See
    /// docs/REVERSE_ENGINEERING_GUIDE.md.)
    case suteFotoFA
    /// Unknown — discovered empirically; encoders come from learned templates only.
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .neewerStyle: "Neewer-style (0x78 + checksum)"
        case .elkBledom: "ELK-BLEDOM (7E … EF)"
        case .triones: "Triones / HappyLighting (0x56)"
        case .suteFotoFA: "SuteFoto TP25 (FA … 8A)"
        case .custom: "Custom (learned templates)"
        }
    }

    /// Service/characteristic UUID fragments commonly associated with this family.
    /// Matching is a *hint* for probe ordering, not proof.
    public var hintUUIDs: [String] {
        switch self {
        case .neewerStyle: ["69400001", "69400002", "69400003"]
        case .elkBledom: ["FFF0", "FFF3", "FFF4"]
        case .triones: ["FFD5", "FFD9", "FFD0", "FFD4"]
        // FFE0/FFE1: confirmed control service/characteristic on the SuteFoto TP25.
        case .suteFotoFA: ["FFE0", "FFE1"]
        case .custom: []
        }
    }
}

// MARK: - Family encoders

public enum ProtocolEncodingError: Error, Sendable {
    case unsupported(CommandKind, ProtocolFamily)
    case noLearnedTemplate(CommandKind)
}

public extension ProtocolFamily {
    /// Encode a high-level command into the family's wire format.
    /// `custom` requires learned templates and is handled by ProtocolMap.
    func encode(_ command: LightCommand) throws -> Data {
        switch self {
        case .neewerStyle: return try encodeNeewer(command)
        case .elkBledom: return try encodeElk(command)
        case .triones: return try encodeTriones(command)
        case .suteFotoFA: return try encodeSuteFoto(command)
        case .custom: throw ProtocolEncodingError.noLearnedTemplate(command.kind)
        }
    }

    /// Safe, low-impact probe packets used by the discovery assistant.
    /// Each should produce a *visible but harmless* change if the family matches.
    var probes: [(label: String, expectedEffect: String, data: Data)] {
        switch self {
        case .neewerStyle:
            return [
                ("CCT 5600K @ 30%", "Light switches to white ~5600K at low brightness",
                 (try? encodeNeewer(.cct(temperature: .init(kelvin: 5600), brightness: 30))) ?? Data()),
                ("HSI red @ 30%", "Light turns red at low brightness",
                 (try? encodeNeewer(.hsi(color: LightColor(hue: 0, saturation: 1, intensity: 0.3)))) ?? Data()),
                ("Power on", "Light turns on",
                 (try? encodeNeewer(.power(on: true))) ?? Data()),
            ]
        case .elkBledom:
            return [
                ("Brightness 30%", "Brightness drops/changes to ~30%",
                 (try? encodeElk(.brightness(percent: 30))) ?? Data()),
                ("RGB red", "Light turns red",
                 (try? encodeElk(.rgb(red: 255, green: 0, blue: 0))) ?? Data()),
                ("Power on", "Light turns on",
                 (try? encodeElk(.power(on: true))) ?? Data()),
            ]
        case .triones:
            return [
                ("RGB red", "Light turns red",
                 (try? encodeTriones(.rgb(red: 255, green: 0, blue: 0))) ?? Data()),
                ("Power on", "Light turns on",
                 (try? encodeTriones(.power(on: true))) ?? Data()),
            ]
        case .suteFotoFA:
            return [
                ("CCT 5600K @ 30%", "Light turns white ~5600K at low brightness",
                 (try? encodeSuteFoto(.cct(temperature: .init(kelvin: 5600), brightness: 30))) ?? Data()),
                ("HSI red @ 30%", "Light turns red at low brightness",
                 (try? encodeSuteFoto(.hsi(color: LightColor(hue: 0, saturation: 1, intensity: 0.3)))) ?? Data()),
            ]
        case .custom:
            return []
        }
    }
}

// MARK: SuteFoto TP25 (FA … 8A)

private extension ProtocolFamily {
    /// Build a `FA <cmd> 00 00 00 <data…> <checksum> 8A` frame.
    /// Checksum = sum of every byte from `cmd` through the last data byte, & 0xFF.
    static func faFrame(_ cmd: UInt8, _ data: [UInt8]) -> Data {
        let body: [UInt8] = [cmd, 0x00, 0x00, 0x00] + data
        let checksum = UInt8(body.reduce(0) { ($0 + Int($1)) } & 0xFF)
        return Data([0xFA] + body + [checksum, 0x8A])
    }

    /// Scale a 0…255 channel to the TP25's 0…100 range.
    static func to100(_ v: UInt8) -> UInt8 { UInt8(Int(v) * 100 / 255) }

    func encodeSuteFoto(_ command: LightCommand) throws -> Data {
        switch command {
        case .cct(let temp, let brightness):
            // 06: intensity(0-100), CCT kelvin (2 bytes BE), green/magenta (signed, 0=neutral)
            let k = min(max(temp.kelvin, 2800), 10000)
            return Self.faFrame(0x06, [
                UInt8(clamping: brightness),
                UInt8((k >> 8) & 0xFF), UInt8(k & 0xFF),
                0x00,
            ])

        case .hsi(let color):
            // 07: intensity(0-100), hue (2 bytes BE, 0-360), saturation(0-100)
            let hue = min(max(Int(color.hue.rounded()), 0), 360)
            return Self.faFrame(0x07, [
                UInt8(clamping: Int(color.intensity * 100)),
                UInt8((hue >> 8) & 0xFF), UInt8(hue & 0xFF),
                UInt8(clamping: Int(color.saturation * 100)),
            ])

        case .rgb(let r, let g, let b):
            // TP25 has native HSI; convert RGB → HSI and send 0x07.
            return try encodeSuteFoto(.hsi(color: LightColor(
                red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)))

        case .rgbcw(let r, let g, let b, let cw, let ww):
            // 08: R,G,B,LessWarm(cool),MoreWarm(warm) — each 0-100
            return Self.faFrame(0x08, [Self.to100(r), Self.to100(g), Self.to100(b),
                                       Self.to100(cw), Self.to100(ww)])

        case .effect(let id, let speed, let brightness):
            // 09: effectID(1-10), frequency, intensity(0-100)
            return Self.faFrame(0x09, [UInt8(clamping: id), UInt8(clamping: speed),
                                       UInt8(clamping: brightness)])

        case .brightness, .power, .channel:
            // Brightness/power have no standalone frame — they're the intensity
            // field of the active mode, resolved by LightController using state.
            throw ProtocolEncodingError.unsupported(command.kind, .suteFotoFA)

        case .raw(let data):
            return data
        }
    }
}

// MARK: Neewer-style

private extension ProtocolFamily {
    /// `78 tag len payload… checksum` — checksum is byte-sum & 0xFF.
    static func neewerPacket(tag: UInt8, payload: [UInt8]) -> Data {
        var bytes: [UInt8] = [0x78, tag, UInt8(payload.count)] + payload
        bytes.append(UInt8(bytes.reduce(0) { ($0 + Int($1)) } & 0xFF))
        return Data(bytes)
    }

    func encodeNeewer(_ command: LightCommand) throws -> Data {
        switch command {
        case .power(let on):
            return Self.neewerPacket(tag: 0x81, payload: [on ? 0x01 : 0x02])
        case .brightness(let pct):
            return Self.neewerPacket(tag: 0x82, payload: [UInt8(clamping: pct)])
        case .cct(let temp, let brightness):
            // payload: brightness%, CCT in hundreds of K (e.g. 56 = 5600K)
            let cct = UInt8(clamping: temp.kelvin / 100)
            return Self.neewerPacket(tag: 0x87, payload: [UInt8(clamping: brightness), cct])
        case .hsi(let color):
            let hue = Int(color.hue.rounded())
            return Self.neewerPacket(tag: 0x86, payload: [
                UInt8(hue & 0xFF), UInt8((hue >> 8) & 0xFF),
                UInt8(clamping: Int(color.saturation * 100)),
                UInt8(clamping: Int(color.intensity * 100)),
            ])
        case .rgb(let r, let g, let b):
            // No native RGB tag in this family — map through HSI.
            return try encodeNeewer(.hsi(color: LightColor(
                red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)))
        case .effect(let id, _, let brightness):
            return Self.neewerPacket(tag: 0x88, payload: [UInt8(clamping: brightness), UInt8(clamping: id)])
        case .channel(_, let channel):
            return Self.neewerPacket(tag: 0x90, payload: [UInt8(clamping: channel)])
        case .rgbcw:
            throw ProtocolEncodingError.unsupported(.rgbcw, .neewerStyle)
        case .raw(let data):
            return data
        }
    }
}

// MARK: ELK-BLEDOM style

private extension ProtocolFamily {
    func encodeElk(_ command: LightCommand) throws -> Data {
        switch command {
        case .power(let on):
            return Data([0x7E, 0x00, 0x04, on ? 0x01 : 0x00, 0x00, 0x00, 0x00, 0x00, 0xEF])
        case .brightness(let pct):
            return Data([0x7E, 0x00, 0x01, UInt8(clamping: pct), 0x00, 0x00, 0x00, 0x00, 0xEF])
        case .rgb(let r, let g, let b):
            return Data([0x7E, 0x00, 0x05, 0x03, r, g, b, 0x00, 0xEF])
        case .hsi(let color):
            let b = color.rgbBytes
            return try encodeElk(.rgb(red: b.red, green: b.green, blue: b.blue))
        case .cct(let temp, _):
            // warm/cool mix byte: 0x80 = warm…cool position
            let mix = UInt8(clamping: Int(temp.normalized() * 100))
            return Data([0x7E, 0x00, 0x05, 0x02, mix, UInt8(100 &- mix), 0x00, 0x08, 0xEF])
        case .effect(let id, let speed, _):
            return Data([0x7E, 0x00, 0x03, UInt8(clamping: id), UInt8(clamping: speed), 0x00, 0x00, 0x00, 0xEF])
        case .rgbcw, .channel:
            throw ProtocolEncodingError.unsupported(command.kind, .elkBledom)
        case .raw(let data):
            return data
        }
    }
}

// MARK: Triones style

private extension ProtocolFamily {
    func encodeTriones(_ command: LightCommand) throws -> Data {
        switch command {
        case .power(let on):
            return Data([0xCC, on ? 0x23 : 0x24, 0x33])
        case .rgb(let r, let g, let b):
            return Data([0x56, r, g, b, 0x00, 0xF0, 0xAA])
        case .hsi(let color):
            let b = color.rgbBytes
            return try encodeTriones(.rgb(red: b.red, green: b.green, blue: b.blue))
        case .brightness(let pct):
            // Triones has no separate brightness — scale current colour via white channel.
            let v = UInt8(clamping: pct * 255 / 100)
            return Data([0x56, 0x00, 0x00, 0x00, v, 0x0F, 0xAA])
        case .effect(let id, let speed, _):
            return Data([0xBB, UInt8(clamping: 0x25 + id), UInt8(clamping: speed), 0x44])
        case .cct, .rgbcw, .channel:
            throw ProtocolEncodingError.unsupported(command.kind, .triones)
        case .raw(let data):
            return data
        }
    }
}
