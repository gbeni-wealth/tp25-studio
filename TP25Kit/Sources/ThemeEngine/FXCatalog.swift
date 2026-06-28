import Foundation

/// TP25 FX-mode scene catalog. IDs are placeholders until discovery confirms
/// the real effect indices — `verified` flips per-effect as they're confirmed.
/// New effects are added by appending to `all` (or recording custom ones).
public struct FXEffect: Codable, Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var symbolName: String
    public var defaultSpeed: Int     // 1...10
    public var verified: Bool

    public init(id: Int, name: String, symbolName: String, defaultSpeed: Int = 5, verified: Bool = false) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.defaultSpeed = defaultSpeed
        self.verified = verified
    }
}

public enum FXCatalog {
    /// The TP25's actual FX scenes, in the order shown by the official
    /// "SS LED Video Light" app (IDs are the app's grid order — confirm the
    /// real on-wire indices via capture/sweep). Each effect has Frequency
    /// (1–N) and Intensity (0–100%) parameters in the app.
    public static let all: [FXEffect] = [
        FXEffect(id: 1, name: "Lightning", symbolName: "cloud.bolt.fill", defaultSpeed: 4),
        FXEffect(id: 2, name: "Police", symbolName: "light.beacon.max.fill", defaultSpeed: 4),
        FXEffect(id: 3, name: "Fire truck", symbolName: "truck.box.fill", defaultSpeed: 4),
        FXEffect(id: 4, name: "Ambulance", symbolName: "cross.case.fill", defaultSpeed: 4),
        FXEffect(id: 5, name: "Fire", symbolName: "flame.fill", defaultSpeed: 4),
        FXEffect(id: 6, name: "Fireworks", symbolName: "sparkles", defaultSpeed: 4),
        FXEffect(id: 7, name: "Fault bulb", symbolName: "lightbulb.slash.fill", defaultSpeed: 4),
        FXEffect(id: 8, name: "TV", symbolName: "tv.fill", defaultSpeed: 4),
        FXEffect(id: 9, name: "RGB Circle", symbolName: "arrow.triangle.2.circlepath", defaultSpeed: 4),
        FXEffect(id: 10, name: "Paparazzi", symbolName: "camera.fill", defaultSpeed: 4),
    ]

    public static var verifiedCatalogURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TP25Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("fx-catalog.json")
    }

    /// Load the user-verified catalog if it exists, else the defaults.
    public static func load() -> [FXEffect] {
        guard let data = try? Data(contentsOf: verifiedCatalogURL),
              let effects = try? JSONDecoder().decode([FXEffect].self, from: data) else {
            return all
        }
        return effects
    }

    public static func save(_ effects: [FXEffect]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try? (try? encoder.encode(effects))?.write(to: verifiedCatalogURL, options: .atomic)
    }
}
