import SwiftUI
import DeviceManager
import ProtocolEngine

/// Shows every connected light at once, each with its own inline colour +
/// brightness + power controls that target *only that light*. This is what lets
/// you set one light red and another green simultaneously, and see both states
/// side by side. Tapping the row also toggles it in the dashboard selection so
/// the same lights can be driven together by themes/presets.
public struct LightStripView: View {
    @Bindable var fleet: FleetController

    public init(fleet: FleetController) {
        self.fleet = fleet
    }

    private var connected: [Light] { fleet.lights.filter(\.isConnected) }

    public var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader("Lights (\(connected.count))", systemImage: "lightbulb.2.fill")
                if connected.isEmpty {
                    Text("No lights connected. Connect them in BLE Explorer.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(connected) { light in
                        LightRowControl(fleet: fleet, light: light)
                        if light.id != connected.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

/// One light's independent quick-control row.
struct LightRowControl: View {
    @Bindable var fleet: FleetController
    @Bindable var light: Light

    @State private var isRenaming = false
    @State private var draftName = ""

    private var swatch: LightColor {
        light.state.mode == .cct
            ? LightColor(hue: 40, saturation: 0.3, intensity: Double(light.state.brightness) / 100)
            : light.state.color
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(light.state.isOn ? Color(swatch) : .black)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                    .frame(width: 26, height: 26)
                    .shadow(color: light.state.isOn ? Color(swatch).opacity(0.6) : .clear, radius: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(light.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text("G\(light.group) · \(light.state.mode.rawValue) · \(light.state.brightness)%")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Spacer()

                // Per-light colour — sets just this light.
                ColorPicker("", selection: Binding(
                    get: { Color(light.state.color) },
                    set: { setColor(LightColor($0)) }
                ), supportsOpacity: false)
                .labelsHidden()

                Button {
                    setPower(!light.state.isOn)
                } label: {
                    Image(systemName: light.state.isOn ? "power.circle.fill" : "power.circle")
                        .font(.title3)
                        .foregroundStyle(light.state.isOn ? ConsolePalette.accent : .secondary)
                }
                .buttonStyle(.plain)

                // Per-light actions: rename, regroup, remove.
                Menu {
                    Button {
                        draftName = light.name
                        isRenaming = true
                    } label: { Label("Rename", systemImage: "pencil") }

                    Picker("Group", selection: Binding(
                        get: { light.group },
                        set: { fleet.assign(light, group: $0) }
                    )) {
                        ForEach(1...6, id: \.self) { Text("Group \($0)").tag($0) }
                    }

                    Divider()
                    Button(role: .destructive) {
                        fleet.remove(light)
                    } label: { Label("Remove from Console", systemImage: "minus.circle") }
                    Button(role: .destructive) {
                        let id = light.id
                        fleet.remove(light)
                        fleet.registry.forget(id)
                    } label: { Label("Forget Light", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            ConsoleSlider("Brightness", value: Binding(
                get: { Double(light.state.brightness) },
                set: { setBrightness(Int($0)) }
            ), in: 0...100, format: { "\(Int($0))%" })
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(fleet.selection.contains(light.id)
                    ? ConsolePalette.accent.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture { toggleSelection() }
        .alert("Rename Light", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
            Button("Save") { fleet.rename(light, to: draftName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func setColor(_ color: LightColor) {
        light.state.color = color
        light.state.mode = .hsi
        light.state.isOn = true
        Task { await fleet.send(.hsi(color: color), to: light) }
    }

    private func setBrightness(_ percent: Int) {
        light.state.brightness = percent
        Task { await fleet.send(.brightness(percent: percent), to: light) }
    }

    private func setPower(_ on: Bool) {
        light.state.isOn = on
        Task { await fleet.send(.power(on: on), to: light) }
    }

    private func toggleSelection() {
        if fleet.selection.contains(light.id) {
            fleet.selection.remove(light.id)
        } else {
            fleet.selection.insert(light.id)
        }
    }
}
