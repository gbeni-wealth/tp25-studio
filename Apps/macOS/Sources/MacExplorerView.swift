import SwiftUI
import BluetoothCore
import DeviceManager
import SharedUI

/// macOS BLE Explorer: scan table on the left, GATT tree for the selected
/// connected device on the right.
struct MacExplorerView: View {
    @Bindable var fleet: FleetController
    @State private var selectedDeviceID: UUID?

    var body: some View {
        // A plain HStack (not HSplitView): on recent macOS, HSplitView fails to
        // propose a concrete height to its panes, so the scan table sized to its
        // own content and the whole stack drifted to the bottom of the pane. An
        // HStack proposes full height, so `maxHeight: .infinity` is honoured.
        HStack(spacing: 0) {
            // Pass the scanner in directly (see BLEScanPane) so the device list
            // repaints as advertisements stream in.
            BLEScanPane(scanner: fleet.scanner, fleet: fleet,
                        selectedDeviceID: $selectedDeviceID)
                .frame(minWidth: 420, maxWidth: 620, maxHeight: .infinity)

            Divider()

            gattPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Scanning should never need hunting for a button.
            if !fleet.scanner.isScanning { fleet.scanner.startScan() }
        }
    }

    @ViewBuilder
    private var gattPane: some View {
        if let light = selectedLight {
            VStack(spacing: 0) {
                HStack {
                    Text(light.name).font(.headline)
                    Spacer()
                    Text(stateText(light.session.connectionState))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Disconnect") { fleet.remove(light) }
                        .controlSize(.small)
                }
                .padding(10)
                Divider()
                GATTExplorerView(session: light.session)
            }
        } else {
            ContentUnavailableView("Select & double-click a device to connect",
                                   systemImage: "list.bullet.indent")
        }
    }

    private var selectedLight: Light? {
        if let id = selectedDeviceID, let light = fleet.lights.first(where: { $0.id == id }) {
            return light
        }
        return fleet.lights.first(where: \.isConnected)
    }

    private func stateText(_ state: BLEDeviceSession.ConnectionState) -> String {
        switch state {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .discovering: "Discovering…"
        case .ready: "Ready"
        case .failed(let reason): "Failed: \(reason)"
        }
    }
}

/// The scan controls + results table. Takes the `BLEScanner` as a direct input
/// so this view's body observes `scanner.devices`/`isScanning` itself. Reaching
/// through `fleet.scanner.…` in the parent left the table stale until some other
/// `fleet` change forced a redraw — which is why devices only appeared after
/// connecting a light. Observing the scanner directly fixes that.
private struct BLEScanPane: View {
    let scanner: BLEScanner
    @Bindable var fleet: FleetController
    @Binding var selectedDeviceID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible control bar (toolbar items can get buried on macOS 26).
            HStack(spacing: 12) {
                Button {
                    scanner.isScanning ? scanner.stopScan() : scanner.startScan()
                } label: {
                    Label(scanner.isScanning ? "Stop Scan" : "Start Scan",
                          systemImage: scanner.isScanning ? "stop.circle.fill" : "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(scanner.isScanning ? .red : ConsolePalette.accent)

                if scanner.isScanning {
                    ProgressView().controlSize(.small)
                }

                Toggle("Show all devices", isOn: Binding(
                    get: { scanner.showAllDevices },
                    set: { scanner.showAllDevices = $0 }
                ))
                .toggleStyle(.checkbox)

                Spacer()

                Text("\(scanner.visibleDevices.count) device(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)

            if !fleet.registry.all.isEmpty {
                SavedLightsView(fleet: fleet)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }

            Divider()

            Table(scanner.visibleDevices, selection: $selectedDeviceID) {
                TableColumn("Name") { device in
                    HStack(spacing: 4) {
                        if device.looksLikeLight {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(ConsolePalette.accent)
                                .font(.caption)
                        }
                        Text(device.name)
                    }
                }
                .width(min: 130)
                TableColumn("RSSI") { device in
                    Text("\(device.rssi) dBm").monospacedDigit()
                }
                .width(70)
                TableColumn("Services") { device in
                    Text(device.serviceUUIDs.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }
                TableColumn("") { device in
                    Button(isConnected(device) ? "Connected" : "Connect") {
                        fleet.connect(to: device)
                        selectedDeviceID = device.id
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isConnected(device))
                }
                .width(100)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button("Connect") { connect(ids) }
            } primaryAction: { ids in
                connect(ids)
            }
            // Fill the remaining height so the table sits right under the
            // controls instead of collapsing to its header and sinking to the
            // bottom of the pane.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func isConnected(_ device: DiscoveredDevice) -> Bool {
        fleet.lights.first(where: { $0.id == device.id })?.isConnected ?? false
    }

    private func connect(_ ids: Set<UUID>) {
        for id in ids {
            if let device = scanner.devices.first(where: { $0.id == id }) {
                fleet.connect(to: device)
            }
        }
        if let first = ids.first { selectedDeviceID = first }
    }
}
