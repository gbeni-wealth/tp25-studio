import SwiftUI
import DeviceManager
import ProtocolEngine
import ThemeEngine

/// The production light-control surface: power, brightness, CCT, HSI, RGB,
/// RGBCW and FX. Sends to the fleet's current targets (selected or all).
public struct DashboardControlsView: View {
    @Bindable var fleet: FleetController

    @State private var mode: LightMode = .cct
    @State private var brightness: Double = 50
    @State private var kelvin: Double = 5600
    @State private var color = LightColor(hue: 20, saturation: 0.85, intensity: 0.6)
    @State private var hexInput = ""
    @State private var coolWhite: Double = 0
    @State private var warmWhite: Double = 0
    @State private var effects = FXCatalog.load()
    @State private var selectedEffect: FXEffect?
    @State private var effectSpeed: Double = 5
    @State private var errorText: String?

    public init(fleet: FleetController) {
        self.fleet = fleet
    }

    /// Union of capabilities across the targeted lights → which mode tabs show.
    private var capabilities: DeviceCapabilities {
        let targets = fleet.targets
        guard !targets.isEmpty else { return .suteFotoBaseline }
        return targets.reduce(into: DeviceCapabilities()) { $0.formUnion($1.capabilities) }
    }

    private var availableModes: [LightMode] {
        let caps = capabilities
        return LightMode.allCases.filter { mode in
            switch mode {
            case .cct: caps.contains(.cct)
            case .hsi: caps.contains(.hsi)
            case .rgbcw: caps.contains(.rgbcw)
            case .fx: caps.contains(.fx)
            }
        }
    }

    public var body: some View {
        VStack(spacing: 14) {
            // Which lights am I controlling? (all / selected / by group)
            TargetingBar(fleet: fleet)

            // Power + mode
            GlassPanel {
                VStack(spacing: 12) {
                    HStack {
                        PanelHeader("Power", systemImage: "power")
                        Spacer()
                        Button { send(.power(on: true)) } label: {
                            Label("On", systemImage: "lightbulb.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ConsolePalette.accent)
                        Button { send(.power(on: false)) } label: {
                            Label("Off", systemImage: "lightbulb.slash")
                        }
                        .buttonStyle(.bordered)
                    }
                    Picker("Mode", selection: $mode) {
                        ForEach(availableModes) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Brightness (all modes)
            GlassPanel {
                ConsoleSlider("Brightness", value: $brightness, in: 0...100,
                              format: { "\(Int($0))%" }) {
                    send(.brightness(percent: Int(brightness)))
                }
            }

            switch mode {
            case .cct: cctPanel
            case .hsi: hsiPanel
            case .rgbcw: rgbcwPanel
            case .fx: fxPanel
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            snapModeToAvailable()
            // Entering the manual console takes over: stop any running
            // theme/random/music so the controls aren't fighting it.
            fleet.interruptActivity()
            if mode == .cct { resetCCT(send: false) }
        }
        .onChange(of: availableModes) { _, _ in snapModeToAvailable() }
        .onChange(of: mode) { _, newMode in
            // Switching mode is a manual action — stop any running scene.
            fleet.interruptActivity()
            // CCT always starts clean: neutral daylight white, no leftover hue.
            if newMode == .cct { resetCCT(send: true) }
        }
    }

    private func snapModeToAvailable() {
        if !availableModes.contains(mode) { mode = availableModes.first ?? .cct }
    }

    /// Reset CCT to the original neutral white (5600K, no tint). Optionally push
    /// it to the lights so the colour actually changes back immediately.
    private func resetCCT(send doSend: Bool) {
        let range = fleet.map.cctRange
        kelvin = min(max(5600, Double(range.lowerBound)), Double(range.upperBound))
        guard doSend else { return }
        send(.cct(temperature: .init(kelvin: Int(kelvin)), brightness: Int(brightness)))
    }

    // MARK: Panels

    private var cctPanel: some View {
        GlassPanel {
            VStack(spacing: 10) {
                PanelHeader("Colour Temperature", systemImage: "thermometer.medium")
                ConsoleSlider("Temperature", value: $kelvin,
                              in: Double(fleet.map.cctRange.lowerBound)...Double(fleet.map.cctRange.upperBound),
                              format: { "\(Int($0))K" }) {
                    send(.cct(temperature: .init(kelvin: Int(kelvin)), brightness: Int(brightness)))
                }
                LinearGradient(colors: [Color(kelvin: 2500), Color(kelvin: 5000), Color(kelvin: 8500)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 8)
                    .clipShape(Capsule())
            }
        }
    }

    private var hsiPanel: some View {
        GlassPanel {
            VStack(spacing: 12) {
                PanelHeader("HSI / RGB", systemImage: "paintpalette.fill")
                ColorWheelView(color: $color) { sendColor() }
                    .frame(maxWidth: 280)

                ConsoleSlider("Hue", value: Binding(
                    get: { color.hue },
                    set: { color = LightColor(hue: $0, saturation: color.saturation, intensity: color.intensity) }
                ), in: 0...360, format: { "\(Int($0))°" }) { sendColor() }

                ConsoleSlider("Saturation", value: Binding(
                    get: { color.saturation * 100 },
                    set: { color = LightColor(hue: color.hue, saturation: $0 / 100, intensity: color.intensity) }
                ), in: 0...100, format: { "\(Int($0))%" }) { sendColor() }

                ConsoleSlider("Intensity", value: Binding(
                    get: { color.intensity * 100 },
                    set: { color = LightColor(hue: color.hue, saturation: color.saturation, intensity: $0 / 100) }
                ), in: 0...100, format: { "\(Int($0))%" }) { sendColor() }

                rgbSliders

                HStack {
                    TextField("Hex e.g. FF8800", text: $hexInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout.monospaced())
                        .onSubmit(applyHex)
                    Button("Apply", action: applyHex)
                        .buttonStyle(.bordered)
                    Spacer()
                    Text("#\(color.hexString)")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rgbSliders: some View {
        let rgb = color.rgb
        return VStack(spacing: 8) {
            ConsoleSlider("R", value: Binding(
                get: { rgb.red * 255 },
                set: { color = LightColor(red: $0 / 255, green: rgb.green, blue: rgb.blue) }
            ), in: 0...255) { sendColor() }
            ConsoleSlider("G", value: Binding(
                get: { rgb.green * 255 },
                set: { color = LightColor(red: rgb.red, green: $0 / 255, blue: rgb.blue) }
            ), in: 0...255) { sendColor() }
            ConsoleSlider("B", value: Binding(
                get: { rgb.blue * 255 },
                set: { color = LightColor(red: rgb.red, green: rgb.green, blue: $0 / 255) }
            ), in: 0...255) { sendColor() }
        }
    }

    private var rgbcwPanel: some View {
        GlassPanel {
            VStack(spacing: 10) {
                PanelHeader("RGB + Cool/Warm White", systemImage: "circle.lefthalf.filled")
                ColorWheelView(color: $color) { sendRGBCW() }
                    .frame(maxWidth: 240)
                ConsoleSlider("Cool White", value: $coolWhite, in: 0...255) { sendRGBCW() }
                ConsoleSlider("Warm White", value: $warmWhite, in: 0...255) { sendRGBCW() }
            }
        }
    }

    private var fxPanel: some View {
        GlassPanel {
            VStack(spacing: 10) {
                PanelHeader("Effects", systemImage: "sparkles")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(effects) { effect in
                        Button {
                            selectedEffect = effect
                            effectSpeed = Double(effect.defaultSpeed)
                            send(.effect(id: effect.id, speed: effect.defaultSpeed,
                                         brightness: Int(brightness)))
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: effect.symbolName)
                                    .font(.title3)
                                Text(effect.name)
                                    .font(.caption2)
                                if !effect.verified {
                                    Text("unverified")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedEffect?.id == effect.id
                                    ? ConsolePalette.accent.opacity(0.25)
                                    : Color.white.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            // After tapping an effect and seeing it on the light,
                            // confirm the on-wire ID actually matches this name.
                            Button(effect.verified ? "Mark unverified" : "Mark verified ✓") {
                                toggleVerified(effect)
                            }
                        }
                    }
                }
                if let effect = selectedEffect {
                    ConsoleSlider("Speed", value: $effectSpeed, in: 1...10) {
                        send(.effect(id: effect.id, speed: Int(effectSpeed),
                                     brightness: Int(brightness)))
                    }
                    Text("Tap an effect, watch the light, then right-click → Mark verified to confirm its ID.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Sending

    private func toggleVerified(_ effect: FXEffect) {
        guard let index = effects.firstIndex(where: { $0.id == effect.id }) else { return }
        effects[index].verified.toggle()
        FXCatalog.save(effects)
    }

    private func sendColor() {
        send(.hsi(color: color))
    }

    private func sendRGBCW() {
        let bytes = color.rgbBytes
        send(.rgbcw(red: bytes.red, green: bytes.green, blue: bytes.blue,
                    cool: UInt8(coolWhite), warm: UInt8(warmWhite)))
    }

    private func applyHex() {
        guard let parsed = LightColor(hexString: hexInput) else {
            errorText = "Invalid hex colour"
            return
        }
        color = LightColor(hue: parsed.hue, saturation: parsed.saturation, intensity: color.intensity)
        sendColor()
    }

    private func send(_ command: LightCommand) {
        errorText = nil
        Task {
            let errors = await fleet.sendToTargets(command)
            if let first = errors.values.first {
                errorText = errors.count == fleet.targets.count && fleet.targets.isEmpty == false
                    ? "Send failed: \(first.localizedDescription)"
                    : (errors.isEmpty ? nil : "Some lights failed: \(first.localizedDescription)")
            }
            if fleet.targets.isEmpty {
                errorText = "No connected lights"
            }
            if !fleet.map.isUsable {
                errorText = "Protocol not discovered yet — run the Discovery Assistant first"
            }
        }
    }
}
