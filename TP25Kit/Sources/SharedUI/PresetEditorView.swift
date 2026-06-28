import SwiftUI
import DeviceManager
import PresetEngine
import ProtocolEngine

/// Edit a saved preset after the fact: rename it and adjust its captured look.
/// "Apply preview" pushes the in-progress edit to the lights so you can dial it
/// in live before saving.
public struct PresetEditorView: View {
    @Bindable var fleet: FleetController
    let preset: Preset

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var mode: LightMode
    @State private var color: LightColor
    @State private var brightness: Double
    @State private var kelvin: Double
    @State private var coolWhite: Double
    @State private var warmWhite: Double
    @State private var effectID: Int
    @State private var effectSpeed: Double

    public init(preset: Preset, fleet: FleetController) {
        self.preset = preset
        self.fleet = fleet
        let p = preset.payload
        _name = State(initialValue: preset.name)
        _mode = State(initialValue: LightMode(rawValue: p.mode.uppercased()) ?? .hsi)
        _color = State(initialValue: p.color ?? LightColor(hue: 30, saturation: 0.8, intensity: 0.6))
        _brightness = State(initialValue: Double(p.brightness ?? 50))
        _kelvin = State(initialValue: Double(p.temperatureKelvin ?? 5600))
        _coolWhite = State(initialValue: Double(p.coolWhite ?? 0))
        _warmWhite = State(initialValue: Double(p.warmWhite ?? 0))
        _effectID = State(initialValue: p.effectID ?? 1)
        _effectSpeed = State(initialValue: Double(p.effectSpeed ?? 5))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Preset").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            PanelHeader("Identity", systemImage: "tag")
                            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                            Picker("Mode", selection: $mode) {
                                ForEach(LightMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    GlassPanel {
                        ConsoleSlider("Brightness", value: $brightness, in: 0...100,
                                      format: { "\(Int($0))%" })
                    }

                    switch mode {
                    case .cct:
                        GlassPanel {
                            ConsoleSlider("Temperature", value: $kelvin, in: 2800...10000,
                                          format: { "\(Int($0))K" })
                        }
                    case .hsi:
                        GlassPanel {
                            VStack(spacing: 10) {
                                PanelHeader("Colour", systemImage: "paintpalette")
                                ColorWheelView(color: $color) {}
                                    .frame(maxWidth: 240)
                            }
                        }
                    case .rgbcw:
                        GlassPanel {
                            VStack(spacing: 10) {
                                ColorWheelView(color: $color) {}.frame(maxWidth: 220)
                                ConsoleSlider("Cool White", value: $coolWhite, in: 0...255)
                                ConsoleSlider("Warm White", value: $warmWhite, in: 0...255)
                            }
                        }
                    case .fx:
                        GlassPanel {
                            VStack(spacing: 10) {
                                Stepper("Effect ID: \(effectID)", value: $effectID, in: 1...10)
                                ConsoleSlider("Speed", value: $effectSpeed, in: 1...10)
                            }
                        }
                    }

                    Button {
                        Task { for c in commands { _ = await fleet.sendToTargets(c) } }
                    } label: {
                        Label("Apply preview to lights", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .frame(minWidth: 360, minHeight: 480)
    }

    private var payload: PresetPayload {
        var p = PresetPayload()
        p.mode = mode.rawValue
        p.color = color
        p.brightness = Int(brightness)
        p.temperatureKelvin = Int(kelvin)
        p.coolWhite = UInt8(coolWhite)
        p.warmWhite = UInt8(warmWhite)
        p.effectID = effectID
        p.effectSpeed = Int(effectSpeed)
        return p
    }

    private var commands: [LightCommand] { PresetStore.commands(for: payload) }

    private func save() {
        preset.name = name
        preset.payload = payload   // setter re-encodes + bumps modifiedAt
    }
}
