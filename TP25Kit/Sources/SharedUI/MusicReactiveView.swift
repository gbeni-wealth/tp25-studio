import SwiftUI
import AVFoundation
import DeviceManager
import ProtocolEngine
import ThemeEngine

/// Microphone-driven light reactions: amplitude → brightness pulses,
/// simple energy-flux beat detection → colour changes. Works on iOS and macOS
/// (macOS needs the audio-input entitlement + NSMicrophoneUsageDescription).
@Observable
public final class MusicReactiveEngine {
    public var isRunning = false
    public private(set) var level: Double = 0          // smoothed 0...1
    public private(set) var beatCount = 0
    /// How strongly the mic input drives the lights. 1.0 = default; higher means
    /// quieter sound fills the meter and beats trigger more easily.
    public var sensitivity: Double = 1.0

    /// Called on every audio buffer with the current level (0...1).
    public var onLevel: ((Double) -> Void)?
    /// Called when a beat is detected.
    public var onBeat: (() -> Void)?

    private let engine = AVAudioEngine()
    private var recentEnergy: [Double] = []
    private var lastBeat = Date.distantPast

    public init() {}

    public func start() throws {
        #if os(iOS)
        // macOS has no AVAudioSession; the input node is used directly there.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true)
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        try engine.start()
        isRunning = true
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        var sum: Double = 0
        for i in 0..<frames { sum += Double(channel[i] * channel[i]) }
        let rms = sqrt(sum / Double(max(frames, 1)))

        Task { @MainActor in
            // Sensitivity scales the normalisation: higher = quieter sound reads
            // louder, and the beat threshold below is easier to cross.
            let instant = min(rms * 12 * self.sensitivity, 1)
            // Smooth level
            self.level = self.level * 0.7 + instant * 0.3
            self.onLevel?(self.level)

            // Beat: instantaneous energy well above the recent average. More
            // sensitivity lowers both the relative and absolute beat gates.
            self.recentEnergy.append(instant)
            if self.recentEnergy.count > 32 { self.recentEnergy.removeFirst() }
            let average = self.recentEnergy.reduce(0, +) / Double(max(self.recentEnergy.count, 1))
            let relativeGate = 1.6 - min(self.sensitivity - 1, 0.5) * 0.6   // 1.6 → ~1.3
            if instant > average * relativeGate, instant > 0.12 / self.sensitivity,
               Date().timeIntervalSince(self.lastBeat) > 0.22 {
                self.lastBeat = Date()
                self.beatCount += 1
                self.onBeat?()
            }
        }
    }
}

public struct MusicReactiveView: View {
    @Bindable var fleet: FleetController
    @State private var engine = MusicReactiveEngine()
    @State private var random = RandomColourEngine(config: {
        var cfg = RandomColourEngine.Config()
        cfg.palette = .neon
        cfg.avoidSimilar = true
        return cfg
    }())
    @State private var colourOnBeats = true
    @State private var brightnessPulses = true
    @State private var lastColor: LightColor = .white
    @State private var errorText: String?

    public init(fleet: FleetController) {
        self.fleet = fleet
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassPanel {
                    VStack(spacing: 12) {
                        PanelHeader("Music Reactive", systemImage: "music.note")

                        // Level meter
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule()
                                    .fill(ConsolePalette.accent)
                                    .frame(width: geo.size.width * engine.level)
                            }
                        }
                        .frame(height: 10)

                        ConsoleSlider("Sensitivity", value: Binding(
                            get: { engine.sensitivity },
                            set: { engine.sensitivity = $0 }
                        ), in: 0.2...4.0, format: { String(format: "%.1f×", $0) })

                        Toggle("Colour change on beats", isOn: $colourOnBeats)
                        Toggle("Brightness follows level", isOn: $brightnessPulses)
                        LabeledContent("Beats", value: "\(engine.beatCount)")

                        Button {
                            toggle()
                        } label: {
                            Label(engine.isRunning ? "Stop" : "Start Listening",
                                  systemImage: engine.isRunning ? "stop.fill" : "mic.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(engine.isRunning ? .red : ConsolePalette.accent)

                        if let errorText {
                            Text(errorText).font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                if engine.isRunning {
                    LivePreviewSwatch(color: lastColor, label: "Music Reactive")
                }
            }
            .padding()
        }
        .background(ConsolePalette.backdrop)
    }

    private func toggle() {
        if engine.isRunning {
            fleet.endActivity()
            return
        }
        engine.onBeat = {
            guard colourOnBeats else { return }
            let color = random.next()
            lastColor = color
            Task { _ = await fleet.sendToTargets(.hsi(color: color), interruptScene: false) }
        }
        var lastSent = Date.distantPast
        engine.onLevel = { level in
            guard brightnessPulses else { return }
            // Throttle brightness writes to ~5/sec to stay within BLE budget.
            guard Date().timeIntervalSince(lastSent) > 0.2 else { return }
            lastSent = Date()
            Task { _ = await fleet.sendToTargets(.brightness(percent: Int(20 + level * 80)),
                                                 interruptScene: false) }
        }
        // Register as the active scene so starting a theme/manual control stops
        // music automatically — and stop the mic when something preempts us.
        fleet.beginActivity("Music Reactive") { engine.stop() }
        do {
            try engine.start()
            errorText = nil
        } catch {
            errorText = "Microphone unavailable: \(error.localizedDescription)"
            fleet.endActivity()
        }
    }
}
