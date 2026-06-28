import SwiftUI
import ThemeEngine
import DeviceManager
import ProtocolEngine

/// Gallery of built-in + custom themes with live play controls.
public struct ThemesGalleryView: View {
    @Bindable var fleet: FleetController
    let player: ThemePlayer
    var customThemes: [Theme]
    /// Optional hook: tap "Edit" on a card to load it into a theme editor.
    var onEdit: ((Theme) -> Void)?

    public init(fleet: FleetController, player: ThemePlayer, customThemes: [Theme] = [],
                onEdit: ((Theme) -> Void)? = nil) {
        self.fleet = fleet
        self.player = player
        self.customThemes = customThemes
        self.onEdit = onEdit
    }

    /// Built-ins with the user's edits applied, plus any purely-custom themes.
    private var themes: [Theme] { ThemeLibrary.resolved(customs: customThemes) }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(themes) { theme in
                    ThemeCard(theme: theme,
                              isPlaying: player.activeThemeName == theme.name && player.isPlaying,
                              onEdit: onEdit.map { edit in { edit(theme) } }) {
                        if player.activeThemeName == theme.name && player.isPlaying {
                            fleet.endActivity()
                        } else {
                            wire()
                            // Registering as the fleet's active scene preempts any
                            // other running theme/random/music automatically.
                            fleet.beginActivity("Theme · \(theme.name)") { player.stop() }
                            player.play(theme: theme)
                        }
                    }
                }
            }
            .padding()

            if player.isPlaying {
                // Live preview of the colour currently being pushed to the lights.
                LivePreviewSwatch(color: player.currentColor,
                                  label: player.activeThemeName ?? "Playing")
                    .padding(.horizontal)

                Button {
                    fleet.endActivity()
                } label: {
                    Label("Stop \(player.activeThemeName ?? "")", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
            }
        }
        .background(ConsolePalette.backdrop)
    }

    private func wire() {
        player.onColor = { color in
            // interruptScene:false — the scene shouldn't cancel its own output.
            Task { _ = await fleet.sendToTargets(.hsi(color: color), interruptScene: false) }
        }
    }
}

/// A swatch that animates with the live colour stream — drop it on any page
/// that plays a scene so the user sees the colour change in real time.
public struct LivePreviewSwatch: View {
    let color: LightColor
    var label: String = "Now Playing"

    public init(color: LightColor, label: String = "Now Playing") {
        self.color = color
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(color))
                .frame(width: 56, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.2)))
                .shadow(color: Color(color).opacity(0.6), radius: 12)
                .animation(.linear(duration: 0.12), value: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.weight(.semibold))
                Text("#\(color.hexString)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ThemeCard: View {
    let theme: Theme
    let isPlaying: Bool
    var onEdit: (() -> Void)?
    let action: () -> Void

    private var isEdited: Bool {
        !theme.isBuiltIn && ThemeLibrary.isBuiltIn(theme.id)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: theme.symbolName)
                        .font(.title3)
                        .foregroundStyle(ConsolePalette.accent)
                    Spacer()
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(isPlaying ? .red : .secondary)
                }
                HStack(spacing: 5) {
                    Text(theme.name)
                        .font(.headline)
                    if isEdited {
                        Text("edited")
                            .font(.system(size: 8).weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(ConsolePalette.accent.opacity(0.2), in: Capsule())
                    }
                }
                HStack(spacing: 4) {
                    ForEach(Array(theme.palette.prefix(6).enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(Color(color))
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isPlaying ? ConsolePalette.accent : ConsolePalette.panelStroke,
                                  lineWidth: isPlaying ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onEdit {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            }
        }
    }
}

/// Random colour mode controls — palette, timing, constraints.
public struct RandomEngineView: View {
    @Bindable var fleet: FleetController
    let player: ThemePlayer

    @State private var config = RandomColourEngine.Config()
    @State private var minBrightness: Double = 30
    @State private var maxBrightness: Double = 100
    @State private var minSaturation: Double = 0
    @State private var maxSaturation: Double = 100

    public init(fleet: FleetController, player: ThemePlayer) {
        self.fleet = fleet
        self.player = player
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        PanelHeader("Random Colour Engine", systemImage: "dice.fill")
                        Picker("Palette", selection: $config.palette) {
                            ForEach(RandomColourEngine.Palette.allCases) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .pickerStyle(.menu)

                        ConsoleSlider("Transition", value: $config.transitionDuration, in: 0.1...15,
                                      format: { String(format: "%.1fs", $0) })
                        ConsoleSlider("Hold", value: $config.holdDuration, in: 0.2...30,
                                      format: { String(format: "%.1fs", $0) })
                        ConsoleSlider("Min Brightness", value: $minBrightness, in: 0...100,
                                      format: { "\(Int($0))%" })
                        ConsoleSlider("Max Brightness", value: $maxBrightness, in: 0...100,
                                      format: { "\(Int($0))%" })
                        ConsoleSlider("Min Saturation", value: $minSaturation, in: 0...100,
                                      format: { "\(Int($0))%" })
                        ConsoleSlider("Max Saturation", value: $maxSaturation, in: 0...100,
                                      format: { "\(Int($0))%" })

                        Toggle("Avoid similar colours", isOn: $config.avoidSimilar)
                        Toggle("Avoid repeats", isOn: $config.avoidRepeats)
                        Toggle("Smooth fades (off = sudden jumps)", isOn: $config.smoothFades)
                    }
                }

                // Live preview swatch
                GlassPanel {
                    HStack {
                        PanelHeader("Now Playing", systemImage: "waveform")
                        Spacer()
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(player.currentColor))
                            .frame(width: 64, height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.white.opacity(0.2)))
                    }
                }

                Button {
                    if player.isPlaying {
                        fleet.endActivity()
                    } else {
                        start()
                    }
                } label: {
                    Label(player.isPlaying ? "Stop" : "Start Random Mode",
                          systemImage: player.isPlaying ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(player.isPlaying ? .red : ConsolePalette.accent)
            }
            .padding()
        }
        .background(ConsolePalette.backdrop)
    }

    private func start() {
        var cfg = config
        let bLow = min(minBrightness, maxBrightness) / 100
        let bHigh = max(minBrightness, maxBrightness) / 100
        let sLow = min(minSaturation, maxSaturation) / 100
        let sHigh = max(minSaturation, maxSaturation) / 100
        cfg.brightnessRange = bLow...bHigh
        cfg.saturationRange = sLow...sHigh
        player.onColor = { color in
            Task { _ = await fleet.sendToTargets(.hsi(color: color), interruptScene: false) }
        }
        fleet.beginActivity("Random · \(cfg.palette.displayName)") { player.stop() }
        player.play(random: RandomColourEngine(config: cfg))
    }
}
