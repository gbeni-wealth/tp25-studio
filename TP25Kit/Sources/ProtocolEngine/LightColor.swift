import Foundation

/// Platform-independent colour model used across the whole app.
/// Stored as HSI (hue 0–360, saturation 0–1, intensity 0–1) with RGB conversion helpers.
public struct LightColor: Codable, Hashable, Sendable {
    public var hue: Double        // 0...360
    public var saturation: Double // 0...1
    public var intensity: Double  // 0...1 (brightness)

    public init(hue: Double, saturation: Double, intensity: Double) {
        self.hue = hue.truncatingRemainder(dividingBy: 360) < 0
            ? hue.truncatingRemainder(dividingBy: 360) + 360
            : hue.truncatingRemainder(dividingBy: 360)
        self.saturation = min(max(saturation, 0), 1)
        self.intensity = min(max(intensity, 0), 1)
    }

    public init(red: Double, green: Double, blue: Double) {
        let r = min(max(red, 0), 1), g = min(max(green, 0), 1), b = min(max(blue, 0), 1)
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        var h: Double = 0
        if delta > 0 {
            if maxC == r { h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6)) }
            else if maxC == g { h = 60 * (((b - r) / delta) + 2) }
            else { h = 60 * (((r - g) / delta) + 4) }
        }
        if h < 0 { h += 360 }
        self.init(hue: h, saturation: maxC == 0 ? 0 : delta / maxC, intensity: maxC)
    }

    /// RGB components 0...1 (HSV-style conversion; intensity drives V).
    public var rgb: (red: Double, green: Double, blue: Double) {
        let c = intensity * saturation
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = intensity - c
        let (r1, g1, b1): (Double, Double, Double)
        switch hue {
        case ..<60:    (r1, g1, b1) = (c, x, 0)
        case ..<120:   (r1, g1, b1) = (x, c, 0)
        case ..<180:   (r1, g1, b1) = (0, c, x)
        case ..<240:   (r1, g1, b1) = (0, x, c)
        case ..<300:   (r1, g1, b1) = (x, 0, c)
        default:       (r1, g1, b1) = (c, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }

    /// RGB as 0...255 bytes.
    public var rgbBytes: (red: UInt8, green: UInt8, blue: UInt8) {
        let c = rgb
        return (UInt8(c.red * 255), UInt8(c.green * 255), UInt8(c.blue * 255))
    }

    /// Hex string like "FF8800".
    public var hexString: String {
        let b = rgbBytes
        return String(format: "%02X%02X%02X", b.red, b.green, b.blue)
    }

    public init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Shortest-path hue interpolation between two colours.
    public static func lerp(_ a: LightColor, _ b: LightColor, t: Double) -> LightColor {
        let t = min(max(t, 0), 1)
        var dh = b.hue - a.hue
        if dh > 180 { dh -= 360 }
        if dh < -180 { dh += 360 }
        return LightColor(
            hue: a.hue + dh * t,
            saturation: a.saturation + (b.saturation - a.saturation) * t,
            intensity: a.intensity + (b.intensity - a.intensity) * t
        )
    }

    /// Perceptual-ish distance used by the random engine to avoid similar colours.
    public func distance(to other: LightColor) -> Double {
        var dh = abs(hue - other.hue)
        if dh > 180 { dh = 360 - dh }
        return (dh / 180) * 0.6
            + abs(saturation - other.saturation) * 0.25
            + abs(intensity - other.intensity) * 0.15
    }

    public static let white = LightColor(hue: 0, saturation: 0, intensity: 1)
    public static let off = LightColor(hue: 0, saturation: 0, intensity: 0)
}

/// Correlated colour temperature value for CCT mode.
public struct ColorTemperature: Codable, Hashable, Sendable {
    public var kelvin: Int
    /// TP25-class lights commonly range 2500K–8500K; refine after discovery.
    public static let assumedRange = 2500...8500

    public init(kelvin: Int) {
        self.kelvin = min(max(kelvin, 1000), 20000)
    }

    /// Normalised 0...1 position within a range (for byte encoding).
    public func normalized(in range: ClosedRange<Int> = ColorTemperature.assumedRange) -> Double {
        Double(kelvin - range.lowerBound) / Double(range.upperBound - range.lowerBound)
    }
}
