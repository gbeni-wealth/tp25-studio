import SwiftUI
import ProtocolEngine
import DeviceManager

/// Guided protocol discovery: sends one safe probe at a time and asks
/// "did the light react?". Confirmed probes populate the protocol map.
public struct DiscoveryAssistantView: View {
    @State private var assistant: DiscoveryAssistant
    let controller: LightController
    var onMapUpdated: (ProtocolMap) -> Void

    public init(controller: LightController,
                onMapUpdated: @escaping (ProtocolMap) -> Void = { _ in }) {
        self.controller = controller
        self.onMapUpdated = onMapUpdated
        self._assistant = State(initialValue: DiscoveryAssistant())
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        PanelHeader("Discovery Assistant", systemImage: "wand.and.stars")
                        Text("Point the light where you can see it. The assistant sends one harmless test packet at a time — confirm whether the light visibly reacts.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if assistant.plan.isEmpty {
                            Button {
                                assistant.buildPlan(transport: controller)
                            } label: {
                                Label("Build Probe Plan", systemImage: "list.number")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            ProgressView(value: assistant.progress) {
                                Text("Probe \(min(assistant.currentIndex + 1, assistant.plan.count)) of \(assistant.plan.count)")
                                    .font(.caption)
                            }
                            .tint(ConsolePalette.accent)
                        }
                    }
                }

                if let probe = assistant.currentProbe {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            PanelHeader("Current Probe", systemImage: "target")
                            LabeledContent("Test", value: probe.label)
                            LabeledContent("Family", value: probe.family.displayName)
                            LabeledContent("Characteristic", value: probe.characteristicUUID)
                                .font(.callout.monospaced())
                            LabeledContent("Packet", value: probe.data.hexString)
                                .font(.callout.monospaced())
                            Text("Expected: \(probe.expectedEffect)")
                                .font(.callout)
                                .foregroundStyle(ConsolePalette.accent)

                            switch assistant.phase {
                            case .awaitingConfirmation:
                                HStack {
                                    Button {
                                        assistant.confirmCurrentProbe(lightReacted: true)
                                        onMapUpdated(assistant.map)
                                    } label: {
                                        Label("Light Reacted", systemImage: "checkmark.circle.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)

                                    Button {
                                        assistant.confirmCurrentProbe(lightReacted: false)
                                    } label: {
                                        Label("No Change", systemImage: "xmark.circle")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            default:
                                HStack {
                                    Button {
                                        Task { await assistant.sendCurrentProbe() }
                                    } label: {
                                        Label("Send Probe", systemImage: "paperplane.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Skip") { assistant.skipCurrentProbe() }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                if assistant.phase == .finished {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            PanelHeader("Result", systemImage: "flag.checkered")
                            if assistant.map.isUsable {
                                Label("Protocol mapped — production controls are live.", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("No family matched. Use the packet monitor + diff viewer to learn templates manually.", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                            Button("Start Over") { assistant.reset() }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        PanelHeader("Log", systemImage: "text.alignleft")
                        ForEach(Array(assistant.log.suffix(12).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                MappedCommandsView(map: assistant.map)
            }
            .padding()
        }
        .background(ConsolePalette.backdrop)
    }
}

/// Summary of the current protocol map.
public struct MappedCommandsView: View {
    let map: ProtocolMap

    public init(map: ProtocolMap) { self.map = map }

    public var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 6) {
                PanelHeader("Protocol Map — \(map.deviceModel)", systemImage: "map")
                if map.entries.isEmpty {
                    Text("Nothing confirmed yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(map.entries) { entry in
                        HStack {
                            Text(entry.kind.rawValue.uppercased())
                                .font(.caption.weight(.bold))
                                .frame(width: 90, alignment: .leading)
                            Text(entry.characteristicUUID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.family == .custom ? "template" : entry.family.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
    }
}
