import SwiftUI
import ProtocolEngine

/// Hue/saturation wheel with a draggable thumb. Intensity is controlled by a
/// separate slider, matching how lighting consoles separate colour and level.
public struct ColorWheelView: View {
    @Binding var color: LightColor
    /// Called when the user lifts their finger (avoids flooding BLE writes).
    var onCommit: () -> Void

    public init(color: Binding<LightColor>, onCommit: @escaping () -> Void = {}) {
        self._color = color
        self.onCommit = onCommit
    }

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                wheel(radius: radius)
                    .frame(width: size, height: size)
                    .position(center)

                // Thumb
                let angle = Angle(degrees: color.hue)
                let distance = color.saturation * (radius - 14)
                Circle()
                    .fill(Color(LightColor(hue: color.hue, saturation: color.saturation, intensity: 1)))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .frame(width: 28, height: 28)
                    .shadow(radius: 4)
                    .position(x: center.x + cos(angle.radians) * distance,
                              y: center.y + sin(angle.radians) * distance)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        var hue = atan2(dy, dx) * 180 / .pi
                        if hue < 0 { hue += 360 }
                        let sat = min(sqrt(dx * dx + dy * dy) / (radius - 14), 1)
                        color = LightColor(hue: hue, saturation: sat, intensity: color.intensity)
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func wheel(radius: CGFloat) -> some View {
        Circle()
            .fill(
                AngularGradient(colors: (0...12).map {
                    Color(hue: Double($0) / 12, saturation: 1, brightness: 1)
                }, center: .center)
            )
            .overlay(
                Circle().fill(
                    RadialGradient(colors: [.white, .white.opacity(0)],
                                   center: .center, startRadius: 0, endRadius: radius)
                )
            )
            .overlay(Circle().strokeBorder(ConsolePalette.panelStroke, lineWidth: 1))
    }
}
