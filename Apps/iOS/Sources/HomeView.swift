import SwiftUI
import BluetoothCore
import DeviceManager
import SharedUI

/// Connected lights + scan sheet + the production dashboard.
struct HomeView: View {
    @Bindable var fleet: FleetController
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if fleet.lights.isEmpty {
                        emptyState
                    } else {
                        lightsGrid

                        if !fleet.map.isUsable {
                            protocolWarning
                        }

                        DashboardControlsView(fleet: fleet)
                    }
                }
                .padding()
            }
            .background(ConsolePalette.backdrop)
            .navigationTitle("TP25 Studio")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Add Light", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                ScannerSheet(fleet: fleet)
            }
        }
    }

    private var emptyState: some View {
        GlassPanel {
            VStack(spacing: 12) {
                Image(systemName: "lightbulb.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("No lights connected")
                    .font(.headline)
                Text("Turn on your TP25, then scan for nearby lights.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showScanner = true
                } label: {
                    Label("Scan for Lights", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
    }

    private var lightsGrid: some View {
        VStack(spacing: 10) {
            // Each light with its own colour/brightness/power — set one red and
            // another green at the same time, both visible here.
            LightStripView(fleet: fleet)
            if fleet.lights.count > 1 {
                Text(fleet.selection.isEmpty
                     ? "Themes & presets drive all lights — tap a row to target one"
                     : "Targeting \(fleet.selection.count) selected light(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var protocolWarning: some View {
        GlassPanel {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Protocol not discovered yet").font(.subheadline.weight(.semibold))
                    Text("Run the Discovery Assistant in the Discover tab before controls will work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Modal scanner listing nearby BLE devices with full advertisement data.
struct ScannerSheet: View {
    @Bindable var fleet: FleetController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(fleet.scanner.visibleDevices) { device in
                Button {
                    fleet.connect(to: device)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(device.name).font(.headline)
                            if device.looksLikeLight {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(ConsolePalette.accent)
                                    .font(.caption)
                            }
                            Spacer()
                            SignalStrengthView(rssi: device.rssi)
                            Text("\(device.rssi) dBm")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(device.id.uuidString)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                        if !device.serviceUUIDs.isEmpty {
                            Text("Services: \(device.serviceUUIDs.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let mfr = device.manufacturerHex {
                            Text("Mfr: \(mfr)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("Nearby Devices")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Toggle("All", isOn: Binding(
                        get: { fleet.scanner.showAllDevices },
                        set: { fleet.scanner.showAllDevices = $0 }
                    ))
                    .toggleStyle(.button)
                }
            }
            .onAppear { fleet.scanner.startScan() }
            .onDisappear { fleet.scanner.stopScan() }
            .overlay {
                if fleet.scanner.visibleDevices.isEmpty {
                    ContentUnavailableView(
                        fleet.scanner.isScanning ? "Scanning…" : "Bluetooth Off?",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text(fleet.scanner.isScanning
                            ? "Make sure the light is powered on."
                            : "Enable Bluetooth to scan.")
                    )
                }
            }
        }
    }
}
