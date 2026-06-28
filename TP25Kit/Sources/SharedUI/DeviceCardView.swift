import SwiftUI
import DeviceManager
import ProtocolEngine

/// Home-screen card for one connected light: colour, mode, level, signal.
public struct DeviceCardView: View {
    let light: Light
    var isSelected: Bool

    public init(light: Light, isSelected: Bool = false) {
        self.light = light
        self.isSelected = isSelected
    }

    public var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle()
                        .fill(light.state.isOn
                              ? Color(light.state.mode == .cct
                                      ? LightColor(hue: 40, saturation: 0.3, intensity: Double(light.state.brightness) / 100)
                                      : light.state.color)
                              : Color.black)
                        .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                        .frame(width: 34, height: 34)
                        .shadow(color: light.state.isOn ? Color(light.state.color).opacity(0.6) : .clear,
                                radius: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(light.name)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(light.isConnected ? "Connected" : "Offline")
                                .foregroundStyle(light.isConnected ? .green : .secondary)
                            Text("·").foregroundStyle(.secondary)
                            Text(light.profile.modelName)
                                .foregroundStyle(.secondary)
                            if !light.profile.verified {
                                Text("(assumed)").foregroundStyle(.orange)
                            }
                        }
                        .font(.caption2)
                    }
                    Spacer()
                    SignalStrengthView(rssi: light.rssi)
                }

                HStack(spacing: 12) {
                    badge(light.state.mode.rawValue, symbol: "dial.medium")
                    badge("\(light.state.brightness)%", symbol: "sun.max")
                    if light.state.mode == .cct {
                        badge("\(light.state.temperature.kelvin)K", symbol: "thermometer.medium")
                    }
                    badge("G\(light.group)·C\(light.channel)", symbol: "person.3")
                    if let battery = light.batteryPercent {
                        badge("\(battery)%", symbol: "battery.75")
                    }
                    Spacer()
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? ConsolePalette.accent : .clear, lineWidth: 2)
        )
    }

    private func badge(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}
