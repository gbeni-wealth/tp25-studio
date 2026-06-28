import SwiftUI
import BluetoothCore

/// Service/characteristic tree for a connected session — Phase 0 exploration.
public struct GATTExplorerView: View {
    let session: BLEDeviceSession
    var onSelectCharacteristic: ((GATTCharacteristicInfo) -> Void)?

    public init(session: BLEDeviceSession,
                onSelectCharacteristic: ((GATTCharacteristicInfo) -> Void)? = nil) {
        self.session = session
        self.onSelectCharacteristic = onSelectCharacteristic
    }

    public var body: some View {
        List {
            ForEach(session.services) { service in
                Section {
                    ForEach(service.characteristics) { ch in
                        Button {
                            onSelectCharacteristic?(ch)
                        } label: {
                            characteristicRow(ch)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Read Value") {
                                session.readValue(characteristicUUID: ch.id)
                            }
                            Button(ch.isNotifying ? "Stop Notifications" : "Subscribe") {
                                session.setNotify(!ch.isNotifying, characteristicUUID: ch.id)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "shippingbox")
                        Text("Service \(service.id)")
                            .font(.caption.monospaced())
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
    }

    private func characteristicRow(_ ch: GATTCharacteristicInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(ch.id)
                    .font(.callout.monospaced())
                if ch.isWritable {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                if ch.isNotifying {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Spacer()
            }
            Text(ch.propertyDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let value = ch.lastValue, !value.isEmpty {
                Text(value.hexAsciiDump)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
