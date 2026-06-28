import Foundation
import SwiftData
import ProtocolEngine

/// Convenience operations over the SwiftData context for presets.
@MainActor
public enum PresetStore {
    public static func allPresets(in context: ModelContext) -> [Preset] {
        // Bool isn't Comparable, so favourites are sorted in memory.
        let descriptor = FetchDescriptor<Preset>(
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        let presets = (try? context.fetch(descriptor)) ?? []
        return presets.sorted { a, b in
            if a.isFavourite != b.isFavourite { return a.isFavourite }
            return a.modifiedAt > b.modifiedAt
        }
    }

    @discardableResult
    public static func duplicate(_ preset: Preset, in context: ModelContext) -> Preset {
        let copy = Preset(name: preset.name + " Copy", payload: preset.payload)
        context.insert(copy)
        return copy
    }

    public static func rename(_ preset: Preset, to name: String) {
        preset.name = name
        preset.modifiedAt = .now
    }

    public static func toggleFavourite(_ preset: Preset) {
        preset.isFavourite.toggle()
        preset.modifiedAt = .now
    }

    /// Convert a preset payload back into the command(s) that recreate the scene.
    public static func commands(for payload: PresetPayload) -> [LightCommand] {
        var commands: [LightCommand] = []
        switch payload.mode {
        case "CCT", "cct":
            if let kelvin = payload.temperatureKelvin {
                commands.append(.cct(temperature: .init(kelvin: kelvin),
                                     brightness: payload.brightness ?? 50))
            }
        case "RGBCW", "rgbcw":
            if let color = payload.color {
                let bytes = color.rgbBytes
                commands.append(.rgbcw(red: bytes.red, green: bytes.green, blue: bytes.blue,
                                       cool: payload.coolWhite ?? 0, warm: payload.warmWhite ?? 0))
            }
        case "FX", "fx":
            if let id = payload.effectID {
                commands.append(.effect(id: id, speed: payload.effectSpeed ?? 5,
                                        brightness: payload.brightness ?? 50))
            }
        default: // HSI
            if let color = payload.color {
                commands.append(.hsi(color: color))
            }
        }
        if commands.isEmpty, let brightness = payload.brightness {
            commands.append(.brightness(percent: brightness))
        }
        return commands
    }
}
