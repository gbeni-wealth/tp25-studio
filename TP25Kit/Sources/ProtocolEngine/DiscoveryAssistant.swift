import Foundation
import Observation

/// Abstracts the BLE write path so ProtocolEngine stays transport-free.
/// DeviceManager adapts a live BluetoothCore session to this.
public protocol CommandTransport: AnyObject {
    /// Writable characteristics available on the connected device:
    /// (serviceUUID, characteristicUUID, supportsWriteWithoutResponse)
    var writableCharacteristics: [(service: String, characteristic: String, writeWithoutResponse: Bool)] { get }
    func write(_ data: Data, toCharacteristic uuid: String) async throws
}

/// Interactive, human-in-the-loop protocol discovery.
///
/// Builds an ordered probe plan (candidate family × writable characteristic),
/// sends one probe at a time, and asks the operator to confirm whether the
/// light visibly reacted. Confirmed probes are written into the ProtocolMap.
@Observable
public final class DiscoveryAssistant {
    public struct Probe: Identifiable, Sendable {
        public let id = UUID()
        public let family: ProtocolFamily
        public let characteristicUUID: String
        public let serviceUUID: String
        public let label: String
        public let expectedEffect: String
        public let data: Data
        public let kind: CommandKind
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case awaitingConfirmation(probeID: UUID)
        case finished
        case failed(String)
    }

    public private(set) var plan: [Probe] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var phase: Phase = .idle
    public private(set) var log: [String] = []
    public var map: ProtocolMap

    private weak var transport: CommandTransport?

    public init(map: ProtocolMap = ProtocolMapStore.load() ?? ProtocolMap()) {
        self.map = map
    }

    public var currentProbe: Probe? {
        plan.indices.contains(currentIndex) ? plan[currentIndex] : nil
    }

    public var progress: Double {
        plan.isEmpty ? 0 : Double(currentIndex) / Double(plan.count)
    }

    /// Build the probe plan. Characteristics whose UUID matches a family's
    /// hint UUIDs are probed first with that family.
    public func buildPlan(transport: CommandTransport) {
        self.transport = transport
        var probes: [Probe] = []
        let writables = transport.writableCharacteristics

        // Pass 1: hint-matched pairs (most likely to succeed).
        // Pass 2: every family against every writable characteristic.
        for hintedOnly in [true, false] {
            for family in ProtocolFamily.allCases where family != .custom {
                for char in writables {
                    let hinted = family.hintUUIDs.contains { hint in
                        char.characteristic.uppercased().contains(hint.uppercased())
                            || char.service.uppercased().contains(hint.uppercased())
                    }
                    guard hinted == hintedOnly else { continue }
                    for probe in family.probes where !probe.data.isEmpty {
                        let kind: CommandKind = probe.label.lowercased().contains("power") ? .power
                            : probe.label.lowercased().contains("bright") ? .brightness
                            : probe.label.lowercased().contains("cct") ? .cct
                            : probe.label.lowercased().contains("hsi") ? .hsi : .rgb
                        probes.append(Probe(family: family,
                                            characteristicUUID: char.characteristic,
                                            serviceUUID: char.service,
                                            label: probe.label,
                                            expectedEffect: probe.expectedEffect,
                                            data: probe.data,
                                            kind: kind))
                    }
                }
            }
        }
        // De-duplicate identical (characteristic, payload) pairs from the two passes.
        var seen = Set<String>()
        plan = probes.filter { seen.insert($0.characteristicUUID + $0.data.hexString).inserted }
        currentIndex = 0
        phase = plan.isEmpty ? .failed("No writable characteristics found") : .idle
        log.append("Plan built: \(plan.count) probes across \(writables.count) writable characteristics")
    }

    /// Send the current probe, then wait for the operator's visual confirmation.
    public func sendCurrentProbe() async {
        guard let probe = currentProbe, let transport else { return }
        do {
            try await transport.write(probe.data, toCharacteristic: probe.characteristicUUID)
            log.append("→ \(probe.characteristicUUID) [\(probe.family.rawValue)] \(probe.data.hexString)")
            phase = .awaitingConfirmation(probeID: probe.id)
        } catch {
            log.append("✗ write failed on \(probe.characteristicUUID): \(error.localizedDescription)")
            advance()
        }
    }

    /// Operator says whether the light visibly reacted to the current probe.
    public func confirmCurrentProbe(lightReacted: Bool, notes: String = "") {
        guard let probe = currentProbe else { return }
        if lightReacted {
            let entry = ProtocolMapEntry(kind: probe.kind,
                                         serviceUUID: probe.serviceUUID,
                                         characteristicUUID: probe.characteristicUUID,
                                         family: probe.family,
                                         exampleHex: probe.data.hexString,
                                         notes: notes.isEmpty ? probe.label : notes)
            map.record(entry)
            try? ProtocolMapStore.save(map)
            log.append("✓ CONFIRMED \(probe.kind.rawValue) via \(probe.family.rawValue) on \(probe.characteristicUUID)")
            // A hit strongly implies the whole family works on that characteristic —
            // register the remaining kinds the family can encode, marked unverified.
            registerFamilyWide(probe: probe)
            phase = .finished
        } else {
            log.append("· no reaction: \(probe.label) on \(probe.characteristicUUID)")
            advance()
        }
    }

    /// Skip ahead (e.g. characteristic obviously wrong).
    public func skipCurrentProbe() { advance() }

    public func reset() {
        plan = []
        currentIndex = 0
        phase = .idle
        log.removeAll()
    }

    /// Record a template learned manually via the diff viewer.
    public func recordLearnedTemplate(_ template: CommandTemplate,
                                      serviceUUID: String,
                                      characteristicUUID: String,
                                      notes: String = "learned via diff viewer") {
        let entry = ProtocolMapEntry(kind: template.kind,
                                     serviceUUID: serviceUUID,
                                     characteristicUUID: characteristicUUID,
                                     family: .custom,
                                     template: template,
                                     exampleHex: Data(template.base).hexString,
                                     notes: notes)
        map.record(entry)
        try? ProtocolMapStore.save(map)
        log.append("✓ template recorded for \(template.kind.rawValue)")
    }

    private func advance() {
        currentIndex += 1
        phase = currentIndex >= plan.count ? .finished : .idle
    }

    private func registerFamilyWide(probe: Probe) {
        let kinds: [CommandKind] = [.power, .brightness, .cct, .hsi, .rgb, .effect, .channel]
        for kind in kinds where map.entry(for: kind) == nil {
            // Only register kinds this family can actually encode.
            let sample: LightCommand? = switch kind {
            case .power: .power(on: true)
            case .brightness: .brightness(percent: 50)
            case .cct: .cct(temperature: .init(kelvin: 5600), brightness: 50)
            case .hsi: .hsi(color: .white)
            case .rgb: .rgb(red: 255, green: 255, blue: 255)
            case .effect: .effect(id: 1, speed: 5, brightness: 50)
            case .channel: .channel(group: 1, channel: 1)
            default: nil
            }
            guard let sample, (try? probe.family.encode(sample)) != nil else { continue }
            map.record(ProtocolMapEntry(kind: kind,
                                        serviceUUID: probe.serviceUUID,
                                        characteristicUUID: probe.characteristicUUID,
                                        family: probe.family,
                                        notes: "inferred from confirmed \(probe.kind.rawValue) — verify"))
        }
        try? ProtocolMapStore.save(map)
    }
}
