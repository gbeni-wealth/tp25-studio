import Foundation
import SwiftData
import CloudKit
import PresetEngine

/// CloudKit sync is delivered through SwiftData's native CloudKit mirroring:
/// one shared ModelContainer configured with the app's private database keeps
/// presets, themes, device aliases, and saved groups in sync between iPhone
/// and Mac automatically.
///
/// Requirements (see docs/SETUP.md):
///  - iCloud capability + CloudKit, container `iCloud.com.yourteam.tp25studio`
///  - Remote notifications background mode (iOS)
///  - All models optional/defaulted, no unique constraints (already true).
public enum CloudSync {
    public static let containerIdentifier = "iCloud.com.yourteam.tp25studio"

    public static let schema = Schema([
        Preset.self,
        CustomTheme.self,
        DeviceAlias.self,
        SavedGroup.self,
    ])

    /// The app-wide container. `cloud: false` falls back to local-only storage
    /// (useful before the CloudKit container is provisioned).
    public static func makeContainer(cloud: Bool = true) throws -> ModelContainer {
        let config: ModelConfiguration
        if cloud {
            config = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(containerIdentifier)
            )
        } else {
            config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// App-wide container. `cloud` defaults to **false** because CloudKit
    /// mirroring without the iCloud entitlement crashes asynchronously on
    /// CoreData's cloudkit queue — it cannot be caught with try/catch here.
    /// Pass `cloud: true` only after adding the iCloud capability + container
    /// to both app targets (docs/SETUP.md), then data syncs automatically.
    public static func makeContainerWithFallback(cloud: Bool = false) -> ModelContainer {
        if cloud, let container = try? makeContainer(cloud: true) { return container }
        do {
            return try makeContainer(cloud: false)
        } catch {
            fatalError("Unable to create local SwiftData container: \(error)")
        }
    }

    /// Current iCloud account status, for the settings screen.
    public static func accountStatus() async -> CKAccountStatus {
        (try? await CKContainer(identifier: containerIdentifier).accountStatus()) ?? .couldNotDetermine
    }
}
