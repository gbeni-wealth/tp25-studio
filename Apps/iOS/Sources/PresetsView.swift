import SwiftUI
import SwiftData
import DeviceManager
import PresetEngine
import ProtocolEngine
import SharedUI

/// Saved scenes: apply, favourite, rename, duplicate. Synced via CloudKit.
struct PresetsView: View {
    @Bindable var fleet: FleetController
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Preset.modifiedAt, order: .reverse)])
    private var allPresets: [Preset]

    /// Favourites first (Bool isn't Comparable, so sort in memory).
    private var presets: [Preset] {
        allPresets.sorted { a, b in
            if a.isFavourite != b.isFavourite { return a.isFavourite }
            return a.modifiedAt > b.modifiedAt
        }
    }

    @State private var renaming: Preset?
    @State private var newName = ""
    @State private var editing: Preset?
    @State private var selected: Preset?

    var body: some View {
        NavigationStack {
            List {
                if let selected, let color = selected.payload.color {
                    LivePreviewSwatch(color: color, label: selected.name)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if presets.isEmpty {
                    ContentUnavailableView("No presets yet",
                                           systemImage: "square.stack.3d.up.slash",
                                           description: Text("Save the current look with the + button."))
                }
                ForEach(presets) { preset in
                    Button {
                        apply(preset)
                    } label: {
                        HStack {
                            if let color = preset.payload.color {
                                Circle()
                                    .fill(Color(color))
                                    .frame(width: 26, height: 26)
                            } else {
                                Image(systemName: "thermometer.medium")
                                    .frame(width: 26)
                            }
                            VStack(alignment: .leading) {
                                Text(preset.name).font(.headline)
                                Text(preset.payload.mode.uppercased())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if preset.isFavourite {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            context.delete(preset)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            PresetStore.toggleFavourite(preset)
                        } label: { Label("Favourite", systemImage: "star") }
                        .tint(.yellow)
                    }
                    .contextMenu {
                        Button("Apply") { apply(preset) }
                        Button("Edit…") { editing = preset }
                        Button("Rename") {
                            renaming = preset
                            newName = preset.name
                        }
                        Button("Duplicate") { _ = PresetStore.duplicate(preset, in: context) }
                        Button("Delete", role: .destructive) { context.delete(preset) }
                    }
                }
            }
            .navigationTitle("Presets")
            .toolbar {
                Button {
                    saveCurrentLook()
                } label: {
                    Label("Save Current Look", systemImage: "plus.circle.fill")
                }
            }
            .alert("Rename Preset", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $newName)
                Button("Save") {
                    if let preset = renaming { PresetStore.rename(preset, to: newName) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .sheet(item: $editing) { preset in
                PresetEditorView(preset: preset, fleet: fleet)
            }
        }
    }

    private func saveCurrentLook() {
        // Capture the first target light's state as the scene.
        guard let light = fleet.targets.first ?? fleet.lights.first else { return }
        var payload = PresetPayload()
        payload.mode = light.state.mode.rawValue
        payload.color = light.state.color
        payload.temperatureKelvin = light.state.temperature.kelvin
        payload.brightness = light.state.brightness
        payload.coolWhite = light.state.coolWhite
        payload.warmWhite = light.state.warmWhite
        payload.effectID = light.state.effectID
        payload.effectSpeed = light.state.effectSpeed
        let preset = Preset(name: "Scene \(presets.count + 1)", payload: payload)
        context.insert(preset)
    }

    private func apply(_ preset: Preset) {
        selected = preset
        let commands = PresetStore.commands(for: preset.payload)
        Task {
            for command in commands {
                _ = await fleet.sendToTargets(command)
            }
        }
    }
}
