import SwiftUI
import BluetoothCore
import ProtocolEngine

/// Byte-level diff of selected packets: changing bytes highlighted —
/// the fastest way to spot which byte carries brightness or hue.
public struct PacketDiffView: View {
    let packets: [BLEPacket]
    var onSaveTemplate: ((CommandTemplate) -> Void)?

    @State private var templateKind: CommandKind = .brightness

    public init(packets: [BLEPacket], onSaveTemplate: ((CommandTemplate) -> Void)? = nil) {
        self.packets = packets
        self.onSaveTemplate = onSaveTemplate
    }

    private var diff: PacketDiff { PacketDiff(packets: packets.map(\.data)) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader("Byte Diff — \(packets.count) packets", systemImage: "rectangle.on.rectangle.angled")

            if packets.count < 2 {
                Text("Select two or more packets in the monitor to compare.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                        // Offset header row
                        GridRow {
                            Text("byte").font(.caption2).foregroundStyle(.secondary)
                            ForEach(diff.columns) { col in
                                Text(String(format: "%02d", col.id))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(Array(packets.enumerated()), id: \.element.id) { index, packet in
                            GridRow {
                                Text("#\(index + 1)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                ForEach(diff.columns) { col in
                                    let byte = col.values.indices.contains(index) ? col.values[index] : nil
                                    Text(byte.map { String(format: "%02X", $0) } ?? "··")
                                        .font(.callout.monospaced())
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(
                                            col.isChanging ? Color.orange.opacity(0.3) : .clear,
                                            in: RoundedRectangle(cornerRadius: 4)
                                        )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    let checksum = diff.detectChecksum()
                    Label(
                        "Changing offsets: \(diff.changingOffsets.map(String.init).joined(separator: ", "))"
                            + (checksum != .none ? " · checksum: \(checksum.rawValue)" : ""),
                        systemImage: "sparkle.magnifyingglass"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                }

                if let onSaveTemplate {
                    HStack {
                        Picker("Save as", selection: $templateKind) {
                            ForEach(CommandKind.allCases.filter { $0 != .raw }, id: \.self) {
                                Text($0.rawValue.uppercased()).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        Button("Save Command Template") {
                            if let template = diff.makeTemplate(kind: templateKind,
                                                                notes: "from diff of \(packets.count) packets") {
                                onSaveTemplate(template)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(diff.changingOffsets.isEmpty)
                    }
                }
            }
        }
    }
}
