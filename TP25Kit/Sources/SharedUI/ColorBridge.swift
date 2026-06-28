import SwiftUI
import ProtocolEngine

public extension Color {
    init(_ lightColor: LightColor) {
        self.init(hue: lightColor.hue / 360,
                  saturation: lightColor.saturation,
                  brightness: max(lightColor.intensity, 0.02))
    }

    /// Approximate display colour for a CCT value (for slider thumbs/previews).
    init(kelvin: Int) {
        // Simple blackbody approximation, clamped to a pleasant range.
        let temp = Double(kelvin) / 100
        var red: Double = 1, green: Double = 1, blue: Double = 1
        if temp <= 66 {
            green = min(max(0.39 * log(temp) - 0.63, 0), 1)
            blue = temp <= 19 ? 0 : min(max(0.543 * log(temp - 10) - 1.196, 0), 1)
        } else {
            red = min(max(1.292 * pow(temp - 60, -0.1332), 0), 1)
            green = min(max(1.13 * pow(temp - 60, -0.0755), 0), 1)
        }
        self.init(red: red, green: green, blue: blue)
    }
}

public extension LightColor {
    /// Build from a SwiftUI colour picker value.
    init(_ color: Color) {
        #if canImport(UIKit)
        let native = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        native.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b))
        #elseif canImport(AppKit)
        let native = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        self.init(red: Double(native.redComponent),
                  green: Double(native.greenComponent),
                  blue: Double(native.blueComponent))
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
