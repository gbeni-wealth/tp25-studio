import SwiftUI
import BluetoothCore
import DeviceManager
import ProtocolEngine
import SharedUI

/// Protocol Lab: raw commands, saved command library, replay, and packet
/// template building against the live connection.
struct MacProtocolLabView: View {
    @Bindable var fleet: FleetController
    @State private var savedCommands: [SavedCommand] = SavedCommandStore.load()
    @State private var newLabel = ""
    @State private var statusText = ""

    struct SavedCommand: Codable, Identifiable, Hashable {
        var id = UUID()
        var label: String
        var characteristicUUID: String
        var hex: String
    }

    private var light: Light? { fleet.lights.first(where: \.isConnected) }

    var body: some View {
        if let light {
            HSplitView {
                ScrollView {
                    VStack(spacing: 14) {
                        ATLadderView(session: light.session)
                        DeveloperConsoleView(session: light.session)
                        MappedCommandsView(map: fleet.map)
                    }
                    .padding()
                }
                .frame(minWidth: 380)

                commandLibrary(light: light)
                    .frame(minWidth: 300)
            }
        } else {
            ContentUnavailableView("Connect a light in BLE Explorer first",
                                   systemImage: "testtube.2")
        }
    }

    private func commandLibrary(light: Light) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader("Command Library", systemImage: "books.vertical")
                .padding(.top, 12)

            List {
                ForEach(savedCommands) { command in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(command.label).font(.callout.weight(.medium))
                            Spacer()
                            Button {
                                replay(command, light: light)
                            } label: {
                                Image(systemName: "play.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(ConsolePalette.accent)
                        }
                        Text("\(command.characteristicUUID) ← \(command.hex)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Replay") { replay(command, light: light) }
                        Button("Delete", role: .destructive) {
                            savedCommands.removeAll { $0.id == command.id }
                            SavedCommandStore.save(savedCommands)
                        }
                    }
                }
            }

            // Save the most recent write as a named command
            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save last sent write")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Label e.g. Brightness 50", text: $newLabel)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        guard let lastWrite = light.session.packets.last(where: {
                            $0.direction == .write || $0.direction == .writeNoResponse
                        }) else {
                            statusText = "No writes in this session yet"
                            return
                        }
                        savedCommands.append(SavedCommand(
                            label: newLabel.isEmpty ? "Command \(savedCommands.count + 1)" : newLabel,
                            characteristicUUID: lastWrite.characteristicUUID,
                            hex: lastWrite.hex))
                        SavedCommandStore.save(savedCommands)
                        newLabel = ""
                    }
                    .buttonStyle(.bordered)
                    if !statusText.isEmpty {
                        Text(statusText).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding([.horizontal, .bottom], 10)
        }
        .padding(.horizontal, 4)
    }

    private func replay(_ command: SavedCommand, light: Light) {
        guard let data = Data(hexInput: command.hex) else { return }
        Task {
            do {
                try await light.session.write(data, characteristicUUID: command.characteristicUUID,
                                              annotation: "replay: \(command.label)")
                statusText = "Replayed \(command.label)"
            } catch {
                statusText = "Replay failed: \(error.localizedDescription)"
            }
        }
    }

    enum SavedCommandStore {
        static var url: URL {
            SessionRecorder.sessionsDirectory.deletingLastPathComponent()
                .appendingPathComponent("saved-commands.json")
        }
        static func load() -> [SavedCommand] {
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([SavedCommand].self, from: data)) ?? []
        }
        static func save(_ commands: [SavedCommand]) {
            try? (try? JSONEncoder().encode(commands))?.write(to: url, options: .atomic)
        }
    }
}
