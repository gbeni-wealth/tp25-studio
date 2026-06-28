import SwiftUI
import BluetoothCore
import DeviceManager
import ProtocolEngine
import SharedUI
import AppKit

/// macOS Packet Sniffer: live traffic + selection diff + export.
struct MacSnifferView: View {
    @Bindable var fleet: FleetController
    @State private var selectedPackets: Set<UUID> = []
    @State private var recorder = SessionRecorder()
    @State private var statusText = ""

    private var light: Light? { fleet.lights.first(where: \.isConnected) }

    var body: some View {
        if let light {
            VSplitView {
                PacketMonitorView(packets: light.session.packets,
                                  selection: $selectedPackets,
                                  allowSelection: true)
                    .frame(minHeight: 220)

                ScrollView {
                    GlassPanel {
                        PacketDiffView(
                            packets: light.session.packets.filter { selectedPackets.contains($0.id) },
                            onSaveTemplate: { template in
                                guard let first = light.session.packets.first(where: { selectedPackets.contains($0.id) })
                                else { return }
                                var map = fleet.map
                                map.record(ProtocolMapEntry(
                                    kind: template.kind,
                                    serviceUUID: first.serviceUUID,
                                    characteristicUUID: first.characteristicUUID,
                                    family: .custom,
                                    template: template,
                                    exampleHex: first.hex))
                                fleet.map = map
                                statusText = "Template saved to protocol map"
                            })
                    }
                    .padding()
                }
                .frame(minHeight: 180)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        if recorder.isRecording {
                            recorder.capture(light.session.packets)
                            if let url = try? recorder.stopAndSave() {
                                statusText = "Session saved: \(url.lastPathComponent)"
                            }
                        } else {
                            recorder.start(device: light.session.device, services: light.session.services)
                            statusText = "Recording session…"
                        }
                    } label: {
                        Label(recorder.isRecording ? "Stop Recording" : "Record Session",
                              systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                    }

                    Button {
                        exportCSV(light: light)
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        exportDocs(light: light)
                    } label: {
                        Label("Protocol Docs", systemImage: "doc.text")
                    }

                    Button {
                        light.session.clearLog()
                        selectedPackets.removeAll()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.caption)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
        } else {
            ContentUnavailableView("Connect a light in BLE Explorer first",
                                   systemImage: "waveform.path.ecg")
        }
    }

    private func exportCSV(light: Light) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tp25-packets.csv"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try SessionRecorder.exportCSV(packets: light.session.packets, to: url)
                statusText = "Exported \(url.lastPathComponent)"
            } catch {
                statusText = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportDocs(light: Light) {
        let md = ProtocolDocGenerator.markdown(
            map: fleet.map,
            gatt: light.session.services.map { service in
                .init(serviceUUID: service.id,
                      characteristics: service.characteristics.map {
                          ($0.id, $0.propertyDescription,
                           $0.lastValue?.map { String(format: "%02X", $0) }.joined(separator: " "))
                      })
            },
            observedNotifications: light.session.packets
                .filter { $0.direction == .notification }
                .map { ($0.timestamp, $0.hex) })
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TP25-protocol.md"
        if panel.runModal() == .OK, let url = panel.url {
            try? md.data(using: .utf8)?.write(to: url)
            statusText = "Documentation exported"
        }
    }
}
