import Foundation
import BluetoothCore
import ProtocolEngine
import Observation

/// The app's central object: owns the scanner, all connected lights,
/// group/channel organisation, and synchronised multi-light operations.
@Observable
public final class FleetController {
    public let scanner = BLEScanner()
    public private(set) var lights: [Light] = []
    public private(set) var controllers: [UUID: LightController] = [:]
    /// Lights currently targeted by dashboard controls (empty = all).
    public var selection: Set<UUID> = []
    /// Persistent registry of lights we've named/connected to before.
    public let registry = KnownLightsStore.shared
    /// Name of the continuous effect currently running (theme/random/music),
    /// or nil. Surfaced so the UI can show what's playing and offer a stop.
    public private(set) var activeActivity: String?
    /// How to stop whatever continuous effect is running.
    private var activityStop: (() -> Void)?
    public var map: ProtocolMap {
        didSet {
            try? ProtocolMapStore.save(map)
            for controller in controllers.values { controller.map = map }
        }
    }

    public init(map: ProtocolMap? = nil) {
        // Saved map wins; otherwise ship the confirmed TP25 protocol so controls
        // work out of the box. (Re-run discovery to override for other models.)
        self.map = map ?? ProtocolMapStore.load() ?? .suteFotoTP25
    }

    // MARK: Connection lifecycle

    @discardableResult
    public func connect(to device: DiscoveredDevice) -> Light? {
        if let existing = lights.first(where: { $0.id == device.id }) {
            if !existing.isConnected { existing.session.connect() }
            return existing
        }
        guard let peripheral = scanner.peripheral(for: device) else { return nil }
        let session = BLEDeviceSession(device: device, peripheral: peripheral,
                                       central: scanner.centralManager)
        // Reuse the saved name/group/channel so a known light keeps its identity
        // instead of reappearing as a fresh, unnamed entry.
        let known = registry.known(device.id)
        let light = Light(session: session,
                          alias: known?.name,
                          group: known?.group ?? 1,
                          channel: known?.channel ?? 1)
        registry.record(id: device.id, defaultName: light.alias,
                        modelName: light.profile.modelName,
                        group: light.group, channel: light.channel)
        lights.append(light)
        // Use the model's own command map (TP25, P100, …); fall back to the
        // fleet discovery map for unrecognised devices.
        let profileMap = light.profile.makeProtocolMap()
        let controller = LightController(light: light,
                                         map: profileMap.isUsable ? profileMap : map)
        controllers[light.id] = controller
        session.connect()
        // Refine capabilities once GATT is known (adds battery, identifies
        // unknown SuteFoto models from their characteristics).
        Task { @MainActor in
            for _ in 0..<100 where session.connectionState != .ready {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard session.connectionState == .ready else { return }
            light.refineProfile()
            let refined = light.profile.makeProtocolMap()
            if refined.isUsable { controller.map = refined }
        }
        return light
    }

    public func remove(_ light: Light) {
        light.session.disconnect()
        lights.removeAll { $0.id == light.id }
        controllers.removeValue(forKey: light.id)
        selection.remove(light.id)
    }

    public func controller(for light: Light) -> LightController? {
        controllers[light.id]
    }

    // MARK: Saved-light registry

    /// One-tap reconnect to a previously-known light, no scan required.
    @discardableResult
    public func reconnect(known: KnownLight) -> Light? {
        guard let id = UUID(uuidString: known.id) else { return nil }
        if let existing = lights.first(where: { $0.id == id }) {
            if !existing.isConnected { existing.session.connect() }
            return existing
        }
        guard let peripheral = scanner.retrievePeripheral(id: id) else { return nil }
        let device = DiscoveredDevice(id: id, name: known.name, rssi: 0,
                                      advertisementData: [:], manufacturerData: nil,
                                      serviceUUIDs: [], isConnectable: true, lastSeen: .now)
        let session = BLEDeviceSession(device: device, peripheral: peripheral,
                                       central: scanner.centralManager)
        let light = Light(session: session, alias: known.name,
                          group: known.group, channel: known.channel)
        registry.record(id: id, defaultName: known.name, modelName: light.profile.modelName,
                        group: light.group, channel: light.channel)
        lights.append(light)
        let profileMap = light.profile.makeProtocolMap()
        controllers[light.id] = LightController(light: light,
                                                map: profileMap.isUsable ? profileMap : map)
        session.connect()
        return light
    }

    /// Rename a light and persist it so the name survives reconnects.
    public func rename(_ light: Light, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        light.alias = trimmed
        registry.rename(light.id, to: trimmed)
    }

    /// Assign a light to a group and persist it.
    public func assign(_ light: Light, group: Int) {
        light.group = min(max(group, 1), 6)
        registry.setGroup(light.id, group: light.group)
    }

    public func forget(_ known: KnownLight) {
        if let id = UUID(uuidString: known.id) {
            registry.forget(id)
        }
    }

    // MARK: Scene activity (one continuous effect at a time)

    /// Register a continuous effect (theme / random / music). Any effect already
    /// running is stopped first, so starting a new scene cleanly preempts it.
    public func beginActivity(_ name: String, stop: @escaping () -> Void) {
        activityStop?()
        activityStop = stop
        activeActivity = name
    }

    /// Stop whatever continuous effect is running (called by manual control,
    /// preset apply, or an explicit Stop button).
    public func interruptActivity() {
        activityStop?()
        activityStop = nil
        activeActivity = nil
    }

    public func endActivity() { interruptActivity() }

    // MARK: Targeting

    /// Lights that dashboard commands go to: the selection, or everything connected.
    public var targets: [Light] {
        let connected = lights.filter(\.isConnected)
        guard !selection.isEmpty else { return connected }
        return connected.filter { selection.contains($0.id) }
    }

    public func lights(inGroup group: Int) -> [Light] {
        lights.filter { $0.group == group }
    }

    // MARK: Synchronised control

    /// Send a command to all target lights concurrently. Per-light errors are
    /// collected, not fatal — one flaky light shouldn't break a scene.
    ///
    /// `interruptScene` (default true) stops any running theme/random/music
    /// first, so a manual control or preset immediately takes over. Scene loops
    /// themselves pass `false` so they don't cancel their own output.
    @discardableResult
    public func sendToTargets(_ command: LightCommand,
                              interruptScene: Bool = true) async -> [UUID: Error] {
        if interruptScene { interruptActivity() }
        return await send(command, to: targets)
    }

    /// Send to a single light (regardless of the dashboard selection) so each
    /// light can hold its own colour at the same time — "red here, green there".
    @discardableResult
    public func send(_ command: LightCommand, to light: Light,
                     interruptScene: Bool = true) async -> Error? {
        if interruptScene { interruptActivity() }
        return await send(command, to: [light])[light.id]
    }

    public func send(_ command: LightCommand, to lights: [Light]) async -> [UUID: Error] {
        await withTaskGroup(of: (UUID, Error?).self) { taskGroup in
            for light in lights {
                guard let controller = controllers[light.id] else { continue }
                taskGroup.addTask {
                    do {
                        try await controller.send(command)
                        return (light.id, nil)
                    } catch {
                        return (light.id, error)
                    }
                }
            }
            var errors: [UUID: Error] = [:]
            for await (id, error) in taskGroup {
                if let error { errors[id] = error }
            }
            return errors
        }
    }

    /// Smoothly fade all target lights to a colour over `duration` seconds.
    public func fadeTargets(to color: LightColor, duration: TimeInterval, steps: Int = 20) async {
        interruptActivity()
        guard duration > 0, steps > 1 else {
            _ = await sendToTargets(.hsi(color: color))
            return
        }
        let starts = targets.reduce(into: [UUID: LightColor]()) { $0[$1.id] = $1.state.color }
        let stepDelay = duration / Double(steps)
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            await withTaskGroup(of: Void.self) { taskGroup in
                for light in targets {
                    guard let controller = controllers[light.id],
                          let start = starts[light.id] else { continue }
                    taskGroup.addTask {
                        try? await controller.send(.hsi(color: LightColor.lerp(start, color, t: t)))
                    }
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }
    }
}
