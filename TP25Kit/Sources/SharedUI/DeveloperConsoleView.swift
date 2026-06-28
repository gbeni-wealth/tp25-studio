import SwiftUI
import BluetoothCore
import DeveloperTools

/// Raw command console: hex / UTF-8 / preset test commands against any
/// writable characteristic. Includes command history with replay.
public struct DeveloperConsoleView: View {
    let session: BLEDeviceSession

    @State private var input = ""
    @State private var targetCharacteristic = ""
    @State private var feedback = ""
    @State private var history: [String] = []

    public init(session: BLEDeviceSession) {
        self.session = session
    }

    /// Key paths can't reference tuple members — bridge to an Identifiable struct.
    private struct Writable: Identifiable {
        let id: String
        let noResponse: Bool
    }

    private var writables: [Writable] {
        session.writableCharacteristics.map {
            Writable(id: $0.characteristic, noResponse: $0.writeWithoutResponse)
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    PanelHeader("Developer Console", systemImage: "terminal")

                    Picker("Characteristic", selection: $targetCharacteristic) {
                        Text("Select…").tag("")
                        ForEach(writables) { item in
                            Text("\(item.id)\(item.noResponse ? " (no-rsp)" : "")")
                                .tag(item.id)
                        }
                    }

                    TextField("7E 00 04 01 EF  ·  \"text\"  ·  power-on@neewer", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit(send)

                    HStack {
                        Button(action: send) {
                            Label("Write", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(input.isEmpty || targetCharacteristic.isEmpty)

                        Button("Read") {
                            session.readValue(characteristicUUID: targetCharacteristic)
                            feedback = "Read requested — watch the monitor"
                        }
                        .buttonStyle(.bordered)
                        .disabled(targetCharacteristic.isEmpty)

                        Spacer()
                    }

                    if !feedback.isEmpty {
                        Text(feedback)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !history.isEmpty {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 4) {
                        PanelHeader("History", systemImage: "clock.arrow.circlepath")
                        ForEach(Array(history.suffix(8).reversed().enumerated()), id: \.offset) { _, cmd in
                            Button {
                                input = cmd
                            } label: {
                                Text(cmd)
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear {
            if targetCharacteristic.isEmpty,
               let first = session.writableCharacteristics.first {
                targetCharacteristic = first.characteristic
            }
        }
    }

    private func send() {
        switch ConsoleCommand.parse(input) {
        case .data(let data, let description):
            let command = input
            Task {
                do {
                    try await session.write(data, characteristicUUID: targetCharacteristic,
                                            annotation: "console")
                    feedback = "✓ sent \(description)"
                    if history.last != command { history.append(command) }
                } catch {
                    feedback = "✗ \(error.localizedDescription)"
                }
            }
        case .error(let message):
            feedback = "✗ \(message)"
        }
    }
}
