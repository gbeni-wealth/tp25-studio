import SwiftUI
import BluetoothCore
import DeviceManager
import ProtocolEngine
import SharedUI

/// The Phase-0 workspace on iPhone: assistant, GATT explorer, live monitor,
/// console, diff viewer, and session recording.
struct ReverseEngineeringView: View {
    @Bindable var fleet: FleetController
    @State private var recorder = SessionRecorder()
    @State private var selectedPackets: Set<UUID> = []
    @State private var exportMessage: String?

    private var light: Light? { fleet.lights.first(where: \.isConnected) ?? fleet.lights.first }

    var body: some View {
        NavigationStack {
            Group {
                if let light, let controller = fleet.controller(for: light) {
                    workspace(light: light, controller: controller)
                } else {
                    ContentUnavailableView("Connect a light first",
                                           systemImage: "wrench.and.screwdriver",
                                           description: Text("Use the Lights tab to scan and connect."))
                }
            }
            .background(ConsolePalette.backdrop)
            .navigationTitle("Discover")
        }
    }

    private func workspace(light: Light, controller: LightController) -> some View {
        List {
            Section("Protocol Discovery") {
                NavigationLink {
                    DiscoveryAssistantView(controller: controller) { map in
                        fleet.map = map
                    }
                    .navigationTitle("Assistant")
                } label: {
                    Label("Discovery Assistant", systemImage: "wand.and.stars")
                }

                NavigationLink {
                    GATTExplorerView(session: light.session)
                        .navigationTitle("GATT Explorer")
                } label: {
                    Label("Services & Characteristics", systemImage: "list.bullet.indent")
                }

                NavigationLink {
                    ScrollView {
                        DeveloperConsoleView(session: light.session)
                            .padding()
                    }
                    .background(ConsolePalette.backdrop)
                    .navigationTitle("Console")
                } label: {
                    Label("Developer Console", systemImage: "terminal")
                }
            }

            Section("Traffic") {
                NavigationLink {
                    VStack(spacing: 0) {
                        PacketMonitorView(packets: light.session.packets,
                                          selection: $selectedPackets,
                                          allowSelection: true)
                        if selectedPackets.count >= 2 {
                            GlassPanel {
                                PacketDiffView(
                                    packets: light.session.packets.filter { selectedPackets.contains($0.id) },
                                    onSaveTemplate: { template in
                                        var map = fleet.map
                                        if let first = light.session.packets.first(where: { selectedPackets.contains($0.id) }) {
                                            map.record(ProtocolMapEntry(
                                                kind: template.kind,
                                                serviceUUID: first.serviceUUID,
                                                characteristicUUID: first.characteristicUUID,
                                                family: .custom,
                                                template: template,
                                                exampleHex: first.hex))
                                            fleet.map = map
                                        }
                                    })
                            }
                            .padding(.horizontal)
                        }
                    }
                    .background(ConsolePalette.backdrop)
                    .navigationTitle("Packet Monitor")
                    .toolbar {
                        Button("Clear") { light.session.clearLog() }
                    }
                } label: {
                    Label("Live Packet Monitor", systemImage: "waveform.path.ecg")
                        .badge(light.session.packets.count)
                }
            }

            Section("Session Recorder") {
                if recorder.isRecording {
                    Button {
                        recorder.capture(light.session.packets)
                        if let url = try? recorder.stopAndSave() {
                            exportMessage = "Saved \(url.lastPathComponent)"
                        }
                    } label: {
                        Label("Stop & Save Session", systemImage: "stop.circle.fill")
                            .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        recorder.start(device: light.session.device, services: light.session.services)
                    } label: {
                        Label("Start Recording Session", systemImage: "record.circle")
                    }
                }

                Button {
                    do {
                        let url = try SessionRecorder.exportCSV(packets: light.session.packets)
                        exportMessage = "CSV → \(url.lastPathComponent)"
                    } catch {
                        exportMessage = "Export failed: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Export Packets as CSV", systemImage: "square.and.arrow.up")
                }

                Button {
                    let md = ProtocolDocGenerator.markdown(
                        map: fleet.map,
                        gatt: light.session.services.map { service in
                            .init(serviceUUID: service.id,
                                  characteristics: service.characteristics.map {
                                      ($0.id, $0.propertyDescription,
                                       $0.lastValue?.map { String(format: "%02X", $0) }.joined(separator: " "))
                                  })
                        })
                    let url = SessionRecorder.sessionsDirectory
                        .appendingPathComponent("protocol-\(Int(Date().timeIntervalSince1970)).md")
                    try? md.data(using: .utf8)?.write(to: url)
                    exportMessage = "Docs → \(url.lastPathComponent)"
                } label: {
                    Label("Generate Protocol Documentation", systemImage: "doc.text")
                }

                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Connection") {
                LabeledContent("Device", value: light.session.device.name)
                LabeledContent("State", value: stateText(light.session.connectionState))
                LabeledContent("Services", value: "\(light.session.services.count)")
                LabeledContent("Packets", value: "\(light.session.packets.count)")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func stateText(_ state: BLEDeviceSession.ConnectionState) -> String {
        switch state {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .discovering: "Discovering services…"
        case .ready: "Ready"
        case .failed(let reason): "Failed: \(reason)"
        }
    }
}
