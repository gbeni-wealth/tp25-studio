import Foundation
import ProtocolEngine

/// A theme is a palette plus motion: how the light moves between colours.
public struct Theme: Codable, Identifiable, Hashable, Sendable {
    public enum Motion: String, Codable, CaseIterable, Sendable {
        case smoothFade      // crossfade palette in order
        case suddenJump      // hard cuts
        case shuffle         // random palette order, crossfaded
        case breathe         // fade intensity down/up between colours
    }

    public var id: UUID
    public var name: String
    public var symbolName: String           // SF Symbol for UI
    public var palette: [LightColor]
    public var motion: Motion
    /// Seconds spent transitioning between colours.
    public var transitionDuration: Double
    /// Seconds a colour is held before moving on.
    public var holdDuration: Double
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, symbolName: String = "paintpalette",
                palette: [LightColor], motion: Motion = .smoothFade,
                transitionDuration: Double = 2, holdDuration: Double = 3,
                isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.palette = palette
        self.motion = motion
        self.transitionDuration = transitionDuration
        self.holdDuration = holdDuration
        self.isBuiltIn = isBuiltIn
    }
}

public enum BuiltInThemes {
    /// Stable IDs so a user can edit a built-in and the override sticks across
    /// launches (the override is keyed by this id), and so "is this one playing"
    /// comparisons survive relaunch.
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000%02d", n))!
    }

    public static let all: [Theme] = [
        Theme(id: id(1), name: "Sunset", symbolName: "sunset.fill", palette: [
            LightColor(hue: 25, saturation: 1.0, intensity: 0.8),   // orange
            LightColor(hue: 40, saturation: 0.9, intensity: 0.7),   // amber
            LightColor(hue: 5, saturation: 1.0, intensity: 0.7),    // red
            LightColor(hue: 330, saturation: 0.7, intensity: 0.7),  // pink
        ], motion: .smoothFade, transitionDuration: 4, holdDuration: 5, isBuiltIn: true),

        Theme(id: id(2), name: "Ocean", symbolName: "water.waves", palette: [
            LightColor(hue: 220, saturation: 0.9, intensity: 0.7),  // blue
            LightColor(hue: 180, saturation: 0.8, intensity: 0.6),  // teal
            LightColor(hue: 190, saturation: 1.0, intensity: 0.8),  // cyan
        ], motion: .smoothFade, transitionDuration: 5, holdDuration: 4, isBuiltIn: true),

        Theme(id: id(3), name: "Cyberpunk", symbolName: "bolt.fill", palette: [
            LightColor(hue: 275, saturation: 1.0, intensity: 0.8),  // purple
            LightColor(hue: 310, saturation: 1.0, intensity: 0.9),  // magenta
            LightColor(hue: 210, saturation: 1.0, intensity: 1.0),  // electric blue
        ], motion: .suddenJump, transitionDuration: 0.3, holdDuration: 2, isBuiltIn: true),

        Theme(id: id(4), name: "Fire", symbolName: "flame.fill", palette: [
            LightColor(hue: 0, saturation: 1.0, intensity: 0.7),    // red
            LightColor(hue: 25, saturation: 1.0, intensity: 0.9),   // orange
            LightColor(hue: 50, saturation: 0.9, intensity: 0.8),   // yellow
        ], motion: .breathe, transitionDuration: 0.8, holdDuration: 0.4, isBuiltIn: true),

        Theme(id: id(5), name: "Forest", symbolName: "leaf.fill", palette: [
            LightColor(hue: 130, saturation: 0.9, intensity: 0.6),  // green
            LightColor(hue: 150, saturation: 1.0, intensity: 0.5),  // emerald
            LightColor(hue: 90, saturation: 0.8, intensity: 0.7),   // lime
        ], motion: .smoothFade, transitionDuration: 6, holdDuration: 6, isBuiltIn: true),

        Theme(id: id(6), name: "Studio Warm", symbolName: "lightbulb.fill", palette: [
            LightColor(hue: 35, saturation: 0.45, intensity: 0.9),  // ~3200K tungsten feel
        ], motion: .smoothFade, transitionDuration: 1, holdDuration: 60, isBuiltIn: true),

        Theme(id: id(7), name: "Studio Cool", symbolName: "sun.max.fill", palette: [
            LightColor(hue: 210, saturation: 0.08, intensity: 1.0), // ~5600K daylight feel
        ], motion: .smoothFade, transitionDuration: 1, holdDuration: 60, isBuiltIn: true),

        Theme(id: id(8), name: "Party", symbolName: "party.popper.fill", palette: [
            LightColor(hue: 0, saturation: 1, intensity: 1),
            LightColor(hue: 60, saturation: 1, intensity: 1),
            LightColor(hue: 120, saturation: 1, intensity: 1),
            LightColor(hue: 200, saturation: 1, intensity: 1),
            LightColor(hue: 280, saturation: 1, intensity: 1),
            LightColor(hue: 320, saturation: 1, intensity: 1),
        ], motion: .shuffle, transitionDuration: 0.2, holdDuration: 0.5, isBuiltIn: true),

        Theme(id: id(9), name: "Relax", symbolName: "moon.stars.fill", palette: [
            LightColor(hue: 250, saturation: 0.5, intensity: 0.35),
            LightColor(hue: 200, saturation: 0.4, intensity: 0.3),
            LightColor(hue: 290, saturation: 0.4, intensity: 0.3),
        ], motion: .breathe, transitionDuration: 8, holdDuration: 6, isBuiltIn: true),
    ]
}

/// Merges the built-in themes with the user's saved customs. A custom whose id
/// matches a built-in is treated as an *override* (the user edited that built-in)
/// and replaces it in place; everything else is appended as a new theme.
public enum ThemeLibrary {
    public static func resolved(customs: [Theme]) -> [Theme] {
        let overrides = Dictionary(customs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let builtInIDs = Set(BuiltInThemes.all.map(\.id))
        let merged = BuiltInThemes.all.map { overrides[$0.id] ?? $0 }
        let extras = customs.filter { !builtInIDs.contains($0.id) }
        return merged + extras
    }

    public static func isBuiltIn(_ id: UUID) -> Bool {
        BuiltInThemes.all.contains { $0.id == id }
    }

    /// The original (un-edited) built-in for a given id, if any.
    public static func builtIn(_ id: UUID) -> Theme? {
        BuiltInThemes.all.first { $0.id == id }
    }
}
