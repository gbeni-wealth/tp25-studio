import SwiftUI
import SwiftData
import DeviceManager
import ThemeEngine
import PresetEngine
import ProtocolEngine
import SharedUI

/// Theme Studio: design colour sequences, preview them live in the app,
/// then play them on real lights. Custom themes persist + sync via SwiftData.
struct MacThemeStudioView: View {
    @Bindable var fleet: FleetController
    let player: ThemePlayer

    @Environment(\.modelContext) private var context
    @Query private var customThemes: [CustomTheme]

    @State private var draft = Theme(name: "New Theme", palette: [
        LightColor(hue: 20, saturation: 0.9, intensity: 0.7),
        LightColor(hue: 200, saturation: 0.8, intensity: 0.6),
    ])
    @State private var previewPlayer = ThemePlayer()
    @State private var pickerColor = Color.orange

    var body: some View {
        HSplitView {
            editor
                .frame(minWidth: 380)
            ScrollView {
                VStack(spacing: 14) {
                    preview
                    ThemesGalleryView(fleet: fleet, player: player,
                                      customThemes: customThemes.compactMap(\.theme),
                                      onEdit: { draft = $0 })
                        .frame(minHeight: 400)
                }
                .padding()
            }
            .frame(minWidth: 360)
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        PanelHeader("Theme Designer", systemImage: "paintbrush.pointed.fill")

                        HStack {
                            TextField("Theme name", text: $draft.name)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                draft = Theme(name: "New Theme", palette: [
                                    LightColor(hue: 20, saturation: 0.9, intensity: 0.7),
                                    LightColor(hue: 200, saturation: 0.8, intensity: 0.6),
                                ])
                            } label: { Label("New", systemImage: "plus") }
                                .buttonStyle(.bordered)
                        }

                        Picker("Motion", selection: $draft.motion) {
                            ForEach(Theme.Motion.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }

                        ConsoleSlider("Transition", value: $draft.transitionDuration, in: 0.1...15,
                                      format: { String(format: "%.1fs", $0) })
                        ConsoleSlider("Hold", value: $draft.holdDuration, in: 0.1...60,
                                      format: { String(format: "%.1fs", $0) })

                        PanelHeader("Palette", systemImage: "swatchpalette")
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Array(draft.palette.enumerated()), id: \.offset) { index, color in
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(color))
                                        .frame(width: 44, height: 44)
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(.white.opacity(0.2)))
                                        .contextMenu {
                                            Button("Remove", role: .destructive) {
                                                draft.palette.remove(at: index)
                                            }
                                        }
                                }
                                ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                                    .labelsHidden()
                                Button {
                                    draft.palette.append(LightColor(pickerColor))
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }

                        HStack {
                            Button {
                                previewPlayer.onColor = nil
                                previewPlayer.play(theme: draft)
                            } label: {
                                Label("Preview", systemImage: "eye.fill")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                player.onColor = { color in
                                    Task { _ = await fleet.sendToTargets(.hsi(color: color),
                                                                         interruptScene: false) }
                                }
                                fleet.beginActivity("Theme · \(draft.name)") { player.stop() }
                                player.play(theme: draft)
                            } label: {
                                Label("Play on Lights", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Spacer()

                            if ThemeLibrary.isBuiltIn(draft.id) {
                                Button("Reset", role: .destructive) { resetBuiltIn(draft.id) }
                                    .buttonStyle(.bordered)
                                    .help("Discard edits and restore the original built-in")
                            }

                            Button {
                                upsert(draft)
                            } label: {
                                Label(ThemeLibrary.isBuiltIn(draft.id) ? "Save Edit" : "Save Theme",
                                      systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .disabled(draft.palette.isEmpty)
                        }
                    }
                }

                if !customThemes.isEmpty {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 6) {
                            PanelHeader("My Themes", systemImage: "person.crop.square")
                            ForEach(customThemes) { custom in
                                HStack {
                                    Text(custom.name)
                                    Spacer()
                                    Button("Load") {
                                        if let theme = custom.theme { draft = theme }
                                    }
                                    .controlSize(.small)
                                    Button(role: .destructive) {
                                        context.delete(custom)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var preview: some View {
        GlassPanel {
            VStack(spacing: 10) {
                PanelHeader("Live Preview", systemImage: "eye")
                // While something is playing on the real lights, mirror that
                // colour; otherwise mirror the in-app preview / first swatch.
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(liveColor))
                    .frame(height: 120)
                    .shadow(color: Color(liveColor).opacity(0.5), radius: 24)
                    .animation(.linear(duration: 0.1), value: liveColor)
                if let activity = fleet.activeActivity {
                    Text("On lights: \(activity)")
                        .font(.caption).foregroundStyle(ConsolePalette.accent)
                }
                if previewPlayer.isPlaying {
                    Button("Stop Preview") { previewPlayer.stop() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    /// Colour to show in the preview swatch: live lights win, then in-app
    /// preview, then the draft's first colour.
    private var liveColor: LightColor {
        if fleet.activeActivity != nil, player.isPlaying { return player.currentColor }
        if previewPlayer.isPlaying { return previewPlayer.currentColor }
        return draft.palette.first ?? .white
    }

    // MARK: Persistence helpers

    /// Insert-or-update a theme keyed by its id, so editing a built-in saves an
    /// override and editing a custom updates it in place (no duplicates).
    private func upsert(_ theme: Theme) {
        if let existing = customThemes.first(where: { $0.theme?.id == theme.id }) {
            existing.theme = theme
            existing.name = theme.name
        } else {
            context.insert(CustomTheme(theme: theme))
        }
    }

    /// Drop a built-in's override and restore the editor to the original.
    private func resetBuiltIn(_ id: UUID) {
        if let override = customThemes.first(where: { $0.theme?.id == id }) {
            context.delete(override)
        }
        if let original = ThemeLibrary.builtIn(id) { draft = original }
    }
}

/// Simple macOS preset browser (apply/favourite/delete).
struct MacPresetsView: View {
    @Bindable var fleet: FleetController
    let player: ThemePlayer
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Preset.modifiedAt, order: .reverse)])
    private var presets: [Preset]

    @State private var selected: Preset?
    @State private var editing: Preset?

    /// What the live-preview swatch shows: a running scene wins, else the
    /// selected preset's colour.
    private var previewColor: LightColor {
        if fleet.activeActivity != nil, player.isPlaying { return player.currentColor }
        return selected?.payload.color ?? .white
    }

    var body: some View {
        VStack(spacing: 0) {
            if selected != nil || fleet.activeActivity != nil {
                LivePreviewSwatch(color: previewColor,
                                  label: fleet.activeActivity ?? (selected?.name ?? "Preview"))
                    .padding(10)
            }
            List {
            ForEach(presets) { preset in
                HStack {
                    if let color = preset.payload.color {
                        Circle().fill(Color(color)).frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading) {
                        Text(preset.name).font(.headline)
                        Text(preset.payload.mode.uppercased())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if preset.isFavourite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    Button("Apply") { apply(preset) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .contentShape(Rectangle())
                .listRowBackground(selected?.id == preset.id
                                   ? ConsolePalette.accent.opacity(0.15) : Color.clear)
                .onTapGesture { apply(preset) }
                .contextMenu {
                    Button("Apply") { apply(preset) }
                    Button("Edit…") { editing = preset }
                    Button("Favourite") { PresetStore.toggleFavourite(preset) }
                    Button("Duplicate") { _ = PresetStore.duplicate(preset, in: context) }
                    Button("Delete", role: .destructive) { context.delete(preset) }
                }
            }
            }
        }
        .sheet(item: $editing) { preset in
            PresetEditorView(preset: preset, fleet: fleet)
        }
        .overlay {
            if presets.isEmpty {
                ContentUnavailableView("No presets yet",
                                       systemImage: "square.stack.3d.up.slash",
                                       description: Text("Presets saved on iPhone sync here via iCloud."))
            }
        }
    }

    private func apply(_ preset: Preset) {
        selected = preset
        let commands = PresetStore.commands(for: preset.payload)
        Task {
            for command in commands {
                _ = await fleet.sendToTargets(command)
            }
        }
    }
}
