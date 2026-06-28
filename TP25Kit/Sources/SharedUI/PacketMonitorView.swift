import SwiftUI
import BluetoothCore

/// Live BLE traffic monitor — shared by the iOS RE workspace and the macOS
/// packet sniffer. Supports selection for the diff viewer.
public struct PacketMonitorView: View {
    let packets: [BLEPacket]
    @Binding var selection: Set<UUID>
    var allowSelection: Bool

    public init(packets: [BLEPacket], selection: Binding<Set<UUID>> = .constant([]),
                allowSelection: Bool = false) {
        self.packets = packets
        self._selection = selection
        self.allowSelection = allowSelection
    }

    public var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(packets) { packet in
                    PacketRow(packet: packet,
                              isSelected: selection.contains(packet.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard allowSelection else { return }
                            if selection.contains(packet.id) {
                                selection.remove(packet.id)
                            } else {
                                selection.insert(packet.id)
                            }
                        }
                        .id(packet.id)
                }
            }
            .listStyle(.plain)
            .onChange(of: packets.count) {
                if let last = packets.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

struct PacketRow: View {
    let packet: BLEPacket
    var isSelected = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var directionColor: Color {
        switch packet.direction {
        case .write, .writeNoResponse: .orange
        case .read: .blue
        case .notification: .green
        }
    }

    private var directionSymbol: String {
        switch packet.direction {
        case .write: "arrow.up.circle.fill"
        case .writeNoResponse: "arrow.up.circle"
        case .read: "arrow.down.circle.fill"
        case .notification: "bell.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: directionSymbol)
                    .foregroundStyle(directionColor)
                    .font(.caption)
                Text(Self.timeFormatter.string(from: packet.timestamp))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(packet.characteristicUUID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let annotation = packet.annotation {
                    Text(annotation)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(packet.hex)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}
