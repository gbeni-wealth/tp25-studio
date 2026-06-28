import SwiftUI
import DeviceManager

/// The persistent registry of lights you've connected to before. Reconnect with
/// one tap (no rescan), rename, or forget. Keyed by peripheral UUID so the same
/// physical light is never listed twice.
public struct SavedLightsView: View {
    @Bindable var fleet: FleetController

    @State private var renaming: KnownLight?
    @State private var draftName = ""

    public init(fleet: FleetController) {
        self.fleet = fleet
    }

    private func isConnected(_ known: KnownLight) -> Bool {
        guard let id = UUID(uuidString: known.id) else { return false }
        return fleet.lights.first(where: { $0.id == id })?.isConnected ?? false
    }

    public var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader("Saved Lights", systemImage: "checklist")

                if fleet.registry.all.isEmpty {
                    Text("Lights you connect to are saved here for one-tap reconnect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fleet.registry.all) { known in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isConnected(known) ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(known.name).font(.callout.weight(.medium))
                                Text(known.modelName.isEmpty ? "G\(known.group)"
                                     : "\(known.modelName) · G\(known.group)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isConnected(known) {
                                Text("Connected")
                                    .font(.caption2)
                                    .foregroundStyle(ConsolePalette.accent)
                            } else {
                                Button("Reconnect") { fleet.reconnect(known: known) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button {
                                renaming = known
                                draftName = known.name
                            } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) {
                                fleet.forget(known)
                            } label: { Label("Forget", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .alert("Rename Light", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $draftName)
            Button("Save") {
                if let known = renaming, let id = UUID(uuidString: known.id) {
                    fleet.registry.rename(id, to: draftName)
                    // Update a live light too, if it's connected.
                    if let light = fleet.lights.first(where: { $0.id == id }) {
                        fleet.rename(light, to: draftName)
                    }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}
