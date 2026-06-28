import SwiftUI
import SwiftData
import DeviceManager
import ThemeEngine
import CloudSync
import SharedUI

@main
struct TP25StudioMacApp: App {
    @State private var fleet = FleetController()
    @State private var player = ThemePlayer()

    let container = CloudSync.makeContainerWithFallback()

    var body: some Scene {
        WindowGroup {
            MacRootView(fleet: fleet, player: player)
                .preferredColorScheme(.dark)
                .tint(ConsolePalette.accent)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .modelContainer(container)
        .windowStyle(.automatic)
    }
}

enum MacSection: String, CaseIterable, Identifiable {
    case explorer = "BLE Explorer"
    case sniffer = "Packet Sniffer"
    case protocolLab = "Protocol Lab"
    case assistant = "Discovery Assistant"
    case dashboard = "Light Console"
    case themeStudio = "Theme Studio"
    case presets = "Presets"
    case music = "Music Reactive"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .explorer: "antenna.radiowaves.left.and.right"
        case .sniffer: "waveform.path.ecg"
        case .protocolLab: "testtube.2"
        case .assistant: "wand.and.stars"
        case .dashboard: "slider.horizontal.3"
        case .themeStudio: "paintbrush.pointed.fill"
        case .presets: "square.stack.3d.up.fill"
        case .music: "music.note"
        }
    }
}

struct MacRootView: View {
    @Bindable var fleet: FleetController
    let player: ThemePlayer
    @State private var section: MacSection = .explorer

    var body: some View {
        // Custom-drawn sidebar: macOS 26's vibrancy-based sidebar rendered our
        // labels invisible, so we own every pixel instead.
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
                .background(Color(red: 0.09, green: 0.09, blue: 0.11))

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ConsolePalette.backdrop)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TP25 STUDIO")
                .font(.caption.weight(.bold))
                .foregroundStyle(ConsolePalette.accent)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ForEach(MacSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                            .frame(width: 18)
                            .foregroundStyle(section == item ? ConsolePalette.accent : .secondary)
                        Text(item.rawValue)
                            .foregroundStyle(section == item ? .primary : .secondary)
                        Spacer()
                    }
                    .font(.callout)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(
                        section == item ? Color.white.opacity(0.1) : .clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            if !fleet.lights.isEmpty {
                Text("LIGHTS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                ForEach(fleet.lights) { light in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(light.isConnected ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)
                        Text(light.name)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        SignalStrengthView(rssi: light.rssi)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 3)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch section {
        case .explorer:
            MacExplorerView(fleet: fleet)
        case .sniffer:
            MacSnifferView(fleet: fleet)
        case .protocolLab:
            MacProtocolLabView(fleet: fleet)
        case .assistant:
            if let light = fleet.lights.first(where: \.isConnected),
               let controller = fleet.controller(for: light) {
                DiscoveryAssistantView(controller: controller) { fleet.map = $0 }
            } else {
                ContentUnavailableView("Connect a light in BLE Explorer",
                                       systemImage: "wand.and.stars")
            }
        case .dashboard:
            ScrollView {
                VStack(spacing: 14) {
                    // Each connected light, controllable on its own (red here,
                    // green there) and side by side.
                    LightStripView(fleet: fleet)
                    DashboardControlsView(fleet: fleet)
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        case .themeStudio:
            MacThemeStudioView(fleet: fleet, player: player)
        case .presets:
            MacPresetsView(fleet: fleet, player: player)
        case .music:
            MusicReactiveView(fleet: fleet)
        }
    }
}
