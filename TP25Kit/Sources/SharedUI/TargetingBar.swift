import SwiftUI
import DeviceManager

/// Shows every connected light and lets you choose which ones the dashboard
/// controls — individually, all at once, or by group. This is what makes
/// "control both lights together" obvious and one-tap.
public struct TargetingBar: View {
    @Bindable var fleet: FleetController

    @State private var renaming: Light?
    @State private var draftName = ""

    public init(fleet: FleetController) {
        self.fleet = fleet
    }

    private var connected: [Light] { fleet.lights.filter(\.isConnected) }

    /// Groups that actually have a connected member.
    private var activeGroups: [Int] {
        Array(Set(connected.map(\.group))).sorted()
    }

    public var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    PanelHeader("Controlling", systemImage: "target")
                    Spacer()
                    Text(targetSummary)
                        .font(.caption)
                        .foregroundStyle(ConsolePalette.accent)
                }

                if connected.isEmpty {
                    Text("No lights connected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Light chips (multi-select). Empty selection = all.
                    FlowChips {
                        chip(title: "All Lights",
                             icon: "lightbulb.2.fill",
                             active: fleet.selection.isEmpty) {
                            fleet.selection.removeAll()
                        }
                        ForEach(connected) { light in
                            chip(title: "\(light.name)  ·  G\(light.group)",
                                 icon: "lightbulb.fill",
                                 active: fleet.selection.contains(light.id)) {
                                toggle(light)
                            }
                            .contextMenu {
                                Button {
                                    renaming = light
                                    draftName = light.name
                                } label: { Label("Rename", systemImage: "pencil") }
                                Picker("Assign to group", selection: Binding(
                                    get: { light.group },
                                    set: { fleet.assign(light, group: $0) }
                                )) {
                                    ForEach(1...6, id: \.self) { Text("Group \($0)").tag($0) }
                                }
                            }
                        }
                    }

                    if activeGroups.count > 1 {
                        Divider()
                        HStack(spacing: 6) {
                            Text("Groups")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(activeGroups, id: \.self) { group in
                                Button("G\(group)") { selectGroup(group) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
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
                if let light = renaming { fleet.rename(light, to: draftName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var targetSummary: String {
        let targets = fleet.targets
        if fleet.selection.isEmpty { return "All \(connected.count) light(s)" }
        if targets.count == 1 { return targets[0].name }
        return "\(targets.count) selected"
    }

    private func toggle(_ light: Light) {
        if fleet.selection.contains(light.id) {
            fleet.selection.remove(light.id)
        } else {
            fleet.selection.insert(light.id)
        }
    }

    private func selectGroup(_ group: Int) {
        fleet.selection = Set(connected.filter { $0.group == group }.map(\.id))
    }

    private func chip(title: String, icon: String, active: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? ConsolePalette.accent.opacity(0.28) : Color.white.opacity(0.06),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(
                    active ? ConsolePalette.accent : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Simple wrapping HStack for chips (works on iOS + macOS without Layout APIs).
struct FlowChips<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        // A lazy vgrid of adaptive chips wraps naturally and stays light.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 240), spacing: 6,
                                     alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            content
        }
    }
}
