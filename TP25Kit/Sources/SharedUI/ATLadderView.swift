import SwiftUI
import BluetoothCore

/// Comprehensive on-device text/AT command tester for UART-style lights
/// (like the SuteFoto TP25, which streams ASCII telemetry on FFE1).
///
/// Strategy: rather than guess one command at a time, fire a structured ladder
/// — firmware *self-documentation* commands first (these can dump the entire
/// command set in one reply), then power/brightness/colour candidates across
/// several syntaxes and line terminators. An "interesting response" detector
/// flags any reply that deviates from the repeating telemetry, so a valid
/// command stands out even if the light itself doesn't visibly change.
public struct ATLadderView: View {
    let session: BLEDeviceSession

    @State private var targetCharacteristic = ""
    @State private var terminator: Terminator = .crlf
    @State private var interStepDelay: Double = 0.7
    @State private var running = false
    @State private var progressText = ""
    @State private var interestingLines: [String] = []
    @State private var baselineShapes: Set<String> = []

    public init(session: BLEDeviceSession) {
        self.session = session
    }

    enum Terminator: String, CaseIterable, Identifiable {
        case crlf = "\\r\\n", lf = "\\n", cr = "\\r", none = "none"
        var id: String { rawValue }
        var bytes: String {
            switch self {
            case .crlf: "\r\n"
            case .lf: "\n"
            case .cr: "\r"
            case .none: ""
            }
        }
    }

    /// Command ladder. Discovery first (highest yield), then control candidates.
    static let discovery = [
        "AT", "AT?", "AT+HELP", "AT+HELP?", "AT+LIST", "AT+CMD?", "AT+VER",
        "AT+INFO", "AT+STAT?", "?", "help", "AT+GMR",
    ]
    static let control = [
        // Power
        "AT+ON", "AT+OFF", "AT+POW=1", "AT+SW=1", "AT+EN=1", "AT+LED=1",
        // Brightness / PWM (status reports "pwm", so try those names)
        "AT+PWM=80", "AT+PW=80", "AT+BR=80", "AT+BRIGHT=80", "AT+LUM=80",
        "AT+L=80", "AT+DIM=80", "AT+SI=80",
        // CCT
        "AT+CCT=5600", "AT+CT=56", "AT+TEMP=5600", "AT+K=5600",
        // Colour
        "AT+RGB=255,0,0", "AT+RGB=FF0000", "AT+COL=255,0,0", "AT+C=255,0,0",
        "AT+HSI=0,100,80", "AT+H=0", "AT+MODE=2", "AT+M=2",
        // Bare-token forms (telemetry uses bare tokens like pwm0)
        "pwm80", "pw80", "br80", "on", "off",
    ]

    public var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader("AT / Text Command Sweep", systemImage: "text.magnifyingglass")

                Text("Fires a structured ladder of text commands and flags any reply that differs from the repeating telemetry. Run the discovery set first — firmware help commands can dump the whole command list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Characteristic", selection: $targetCharacteristic) {
                    Text("Select…").tag("")
                    ForEach(writableIDs, id: \.self) { Text($0).tag($0) }
                }

                HStack {
                    Picker("Line ending", selection: $terminator) {
                        ForEach(Terminator.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(maxWidth: 160)
                    Spacer()
                    Text("Delay \(String(format: "%.1f", interStepDelay))s")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $interStepDelay, in: 0.3...2).frame(width: 120)
                }

                HStack {
                    Button {
                        Task { await run(Self.discovery, label: "discovery") }
                    } label: {
                        Label("Run Discovery (\(Self.discovery.count))", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(running || targetCharacteristic.isEmpty)

                    Button {
                        Task { await run(Self.control, label: "control") }
                    } label: {
                        Label("Run Control (\(Self.control.count))", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(running || targetCharacteristic.isEmpty)
                }

                if running {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(progressText).font(.caption.monospaced())
                    }
                }

                if !interestingLines.isEmpty {
                    Divider()
                    Label("Interesting responses (differ from telemetry)", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ConsolePalette.accent)
                    ForEach(Array(interestingLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if !running && !progressText.isEmpty {
                    Text("No replies differed from the normal telemetry — this firmware likely ignores these command names. Capturing the official app is the reliable next step (see the Reverse-Engineering guide).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear {
            if targetCharacteristic.isEmpty {
                // Prefer FFE1 (TP25 control char) if present.
                targetCharacteristic = writableIDs.first { $0.uppercased().contains("FFE1") }
                    ?? writableIDs.first ?? ""
            }
        }
    }

    private var writableIDs: [String] {
        session.writableCharacteristics.map(\.characteristic)
    }

    /// Normalise a telemetry line to a "shape" (digits → #) so we can tell a
    /// genuinely new reply from the same status line with different numbers.
    private func shape(_ line: String) -> String {
        var out = ""
        for ch in line { out.append(ch.isNumber ? "#" : ch) }
        return out
    }

    @MainActor
    private func run(_ commands: [String], label: String) async {
        running = true
        interestingLines = []
        progressText = "Learning telemetry baseline…"

        // 1. Sample the baseline telemetry shapes for ~2s.
        let startCount = session.packets.count
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        baselineShapes = Set(recentNotificationLines(after: startCount).map(shape))

        // 2. Fire each command, then look for a reply whose shape isn't in baseline.
        for (i, cmd) in commands.enumerated() {
            progressText = "[\(i+1)/\(commands.count)] \(cmd)"
            let before = session.packets.count
            let payload = Data((cmd + terminator.bytes).utf8)
            try? await session.write(payload, characteristicUUID: targetCharacteristic,
                                     annotation: "sweep: \(cmd)")
            try? await Task.sleep(nanoseconds: UInt64(interStepDelay * 1_000_000_000))

            for line in recentNotificationLines(after: before) {
                let s = shape(line)
                if !baselineShapes.contains(s), line.trimmingCharacters(in: .whitespaces).count > 1 {
                    interestingLines.append("\(cmd)  →  \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
                    baselineShapes.insert(s) // don't repeat the same novelty
                }
            }
        }
        progressText = "Done — \(commands.count) \(label) commands sent."
        running = false
    }

    /// ASCII notification lines logged after `index`.
    private func recentNotificationLines(after index: Int) -> [String] {
        guard session.packets.count > index else { return [] }
        let slice = session.packets[index...]
        let text = slice
            .filter { $0.direction == .notification }
            .map { String(decoding: $0.data, as: UTF8.self) }
            .joined()
        return text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).map(String.init)
    }
}
