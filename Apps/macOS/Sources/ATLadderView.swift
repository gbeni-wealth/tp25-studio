import SwiftUI
import BluetoothCore
import ProtocolEngine
import SharedUI

/// AT-command brute-force helper for TP25-class text-protocol lights.
/// Fires a configurable ladder of candidate AT commands (each terminated with
/// CRLF) with a pause between them so the operator can watch the light react.
/// Whatever turns the light on/changes it is the real command — note it and
/// we encode it into the protocol map.
struct ATLadderView: View {
    let session: BLEDeviceSession

    @State private var characteristic = "FFE1"
    @State private var isRunning = false
    @State private var currentLabel = ""
    @State private var delayMs: Double = 1500
    @State private var task: Task<Void, Never>?

    // Candidate command words. The status stream uses tokens like pwm (output),
    // so these mirror the most common AT LED vocab. Wide net on purpose.
    private let ladder: [(label: String, cmd: String)] = [
        ("Status (confirm channel)", "AT+STAT"),
        ("Power ON (AT+ON)", "AT+ON"),
        ("Power ON (AT+POW=1)", "AT+POW=1"),
        ("Power ON (AT+SW=1)", "AT+SW=1"),
        ("Brightness 80 (AT+PWM=80)", "AT+PWM=80"),
        ("Brightness 80 (AT+BR=80)", "AT+BR=80"),
        ("Brightness 80 (AT+LUM=80)", "AT+LUM=80"),
        ("Brightness 80 (AT+L=80)", "AT+L=80"),
        ("CCT 5600 (AT+CCT=5600)", "AT+CCT=5600"),
        ("CCT (AT+CT=56)", "AT+CT=56"),
        ("Red (AT+RGB=255,0,0)", "AT+RGB=255,0,0"),
        ("Red (AT+RGB=FF0000)", "AT+RGB=FF0000"),
        ("Red (AT+COL=255,0,0)", "AT+COL=255,0,0"),
        ("HSI (AT+HSI=0,100,80)", "AT+HSI=0,100,80"),
        ("Mode RGB (AT+MODE=2)", "AT+MODE=2"),
    ]

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader("AT Command Ladder", systemImage: "ladder")
                Text("Watch the light. Each step sends one candidate AT command (with CRLF). When the light reacts, note the step — that's the real command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Write char").font(.caption)
                    TextField("FFE1", text: $characteristic)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("Step delay").font(.caption)
                    Slider(value: $delayMs, in: 500...4000) { Text("delay") }
                        .frame(width: 120)
                    Text("\(Int(delayMs)) ms").font(.caption.monospacedDigit())
                }

                if isRunning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(currentLabel).font(.callout.weight(.medium))
                            .foregroundStyle(ConsolePalette.accent)
                    }
                }

                HStack {
                    Button {
                        isRunning ? stop() : start()
                    } label: {
                        Label(isRunning ? "Stop Ladder" : "Run AT Ladder",
                              systemImage: isRunning ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRunning ? .red : ConsolePalette.accent)

                    Button("Send AT+STAT once") {
                        Task { await send("AT+STAT", label: "manual AT+STAT") }
                    }
                    .buttonStyle(.bordered)
                }

                Text("All commands sent to \(characteristic). Open the Packet Sniffer in another step to record responses.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func start() {
        isRunning = true
        task = Task {
            for step in ladder {
                if Task.isCancelled { break }
                currentLabel = step.label
                await send(step.cmd, label: step.label)
                try? await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
            }
            currentLabel = "Done — note which step changed the light"
            isRunning = false
        }
    }

    private func stop() {
        task?.cancel()
        isRunning = false
        currentLabel = "Stopped"
    }

    private func send(_ command: String, label: String) async {
        let data = Data((command + "\r\n").utf8)
        try? await session.write(data, characteristicUUID: characteristic, annotation: "AT: \(command)")
    }
}
