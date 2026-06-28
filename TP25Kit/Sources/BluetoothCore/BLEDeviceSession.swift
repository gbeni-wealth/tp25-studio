import Foundation
import CoreBluetooth
import Observation

/// A live connection to one peripheral: GATT discovery, read/write/notify,
/// and a full packet log of every operation. The foundation for both the
/// reverse-engineering workspace and production light control.
@Observable
public final class BLEDeviceSession: NSObject {
    public enum ConnectionState: Equatable {
        case disconnected, connecting, discovering, ready, failed(String)
    }

    public let device: DiscoveredDevice
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var services: [GATTServiceInfo] = []
    public private(set) var packets: [BLEPacket] = []
    /// Caps memory during long sniffing sessions.
    public var maxLogEntries = 5_000

    private let central: CBCentralManager
    private let peripheral: CBPeripheral
    private var characteristicsByUUID: [String: CBCharacteristic] = [:]
    private var writeContinuations: [CheckedContinuation<Void, Error>] = []

    public init(device: DiscoveredDevice, peripheral: CBPeripheral, central: CBCentralManager) {
        self.device = device
        self.peripheral = peripheral
        self.central = central
        super.init()
        peripheral.delegate = self
    }

    // MARK: Connection

    public func connect() {
        connectionState = .connecting
        ConnectionRelay.shared.register(self, for: peripheral.identifier)
        central.connect(peripheral, options: nil)
    }

    public func disconnect() {
        central.cancelPeripheralConnection(peripheral)
    }

    fileprivate func handleConnected() {
        connectionState = .discovering
        peripheral.discoverServices(nil)
    }

    fileprivate func handleDisconnected(error: Error?) {
        connectionState = error.map { .failed($0.localizedDescription) } ?? .disconnected
        for continuation in writeContinuations {
            continuation.resume(throwing: error ?? CocoaError(.userCancelled))
        }
        writeContinuations.removeAll()
    }

    fileprivate func handleFailedToConnect(error: Error?) {
        connectionState = .failed(error?.localizedDescription ?? "Failed to connect")
    }

    // MARK: GATT operations

    public func characteristic(uuid: String) -> CBCharacteristic? {
        characteristicsByUUID[uuid.uppercased()]
            ?? characteristicsByUUID.first { $0.key.contains(uuid.uppercased()) }?.value
    }

    public func readValue(characteristicUUID: String) {
        guard let ch = characteristic(uuid: characteristicUUID) else { return }
        peripheral.readValue(for: ch)
    }

    public func setNotify(_ enabled: Bool, characteristicUUID: String) {
        guard let ch = characteristic(uuid: characteristicUUID) else { return }
        peripheral.setNotifyValue(enabled, for: ch)
    }

    /// Write data; awaits the response for `.withResponse` characteristics.
    ///
    /// All session state (the packet log, the continuation list, GATT lookups)
    /// is touched on the main thread to stay serialized with CoreBluetooth's
    /// delegate callbacks, which also arrive on `.main`. `write` is called from
    /// background tasks, so doing this work off-main would race the array
    /// mutations in those callbacks and corrupt the heap.
    public func write(_ data: Data, characteristicUUID: String, annotation: String? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                guard let ch = self.characteristic(uuid: characteristicUUID) else {
                    continuation.resume(throwing: CocoaError(.fileNoSuchFile, userInfo: [
                        NSLocalizedDescriptionKey: "Characteristic \(characteristicUUID) not found"]))
                    return
                }
                let withResponse = ch.properties.contains(.write)
                self.appendLog(BLEPacket(direction: withResponse ? .write : .writeNoResponse,
                                         serviceUUID: ch.service?.uuid.uuidString ?? "?",
                                         characteristicUUID: ch.uuid.uuidString,
                                         data: data,
                                         annotation: annotation))
                if withResponse {
                    // Resumed later in didWriteValueFor (also on main).
                    self.writeContinuations.append(continuation)
                    self.peripheral.writeValue(data, for: ch, type: .withResponse)
                } else {
                    self.peripheral.writeValue(data, for: ch, type: .withoutResponse)
                    continuation.resume()
                }
            }
        }
    }

    /// All writable characteristics — feeds the discovery assistant.
    public var writableCharacteristics: [(service: String, characteristic: String, writeWithoutResponse: Bool)] {
        services.flatMap { service in
            service.characteristics.filter(\.isWritable).map {
                (service.id, $0.id, $0.properties.contains(.writeWithoutResponse))
            }
        }
    }

    public func clearLog() { packets.removeAll() }

    private func log(_ packet: BLEPacket) {
        // Marshal to main so the @Observable `packets` array is only ever
        // mutated from one thread (CB callbacks already arrive on .main).
        if Thread.isMainThread {
            appendLog(packet)
        } else {
            DispatchQueue.main.async { [weak self] in self?.appendLog(packet) }
        }
    }

    private func appendLog(_ packet: BLEPacket) {
        packets.append(packet)
        if packets.count > maxLogEntries { packets.removeFirst(packets.count - maxLogEntries) }
    }

    private func updateCharacteristic(_ ch: CBCharacteristic) {
        let uuid = ch.uuid.uuidString
        guard let serviceUUID = ch.service?.uuid.uuidString else { return }
        guard let sIndex = services.firstIndex(where: { $0.id == serviceUUID }) else { return }
        if let cIndex = services[sIndex].characteristics.firstIndex(where: { $0.id == uuid }) {
            services[sIndex].characteristics[cIndex].lastValue = ch.value
            services[sIndex].characteristics[cIndex].isNotifying = ch.isNotifying
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEDeviceSession: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let discovered = peripheral.services else {
            connectionState = .failed(error?.localizedDescription ?? "Service discovery failed")
            return
        }
        services = discovered.map { GATTServiceInfo(id: $0.uuid.uuidString, isPrimary: $0.isPrimary, characteristics: []) }
        for service in discovered {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        let infos = chars.map {
            GATTCharacteristicInfo(id: $0.uuid.uuidString,
                                   serviceUUID: service.uuid.uuidString,
                                   properties: $0.properties,
                                   lastValue: $0.value,
                                   isNotifying: $0.isNotifying)
        }
        for ch in chars {
            characteristicsByUUID[ch.uuid.uuidString.uppercased()] = ch
            // Auto-subscribe to everything notifiable: passive sniffing from second one.
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: ch)
            }
            if ch.properties.contains(.read) {
                peripheral.readValue(for: ch)
            }
        }
        if let index = services.firstIndex(where: { $0.id == service.uuid.uuidString }) {
            services[index].characteristics = infos
        }
        connectionState = .ready
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let direction: BLEPacket.Direction = characteristic.isNotifying ? .notification : .read
        log(BLEPacket(direction: direction,
                      serviceUUID: characteristic.service?.uuid.uuidString ?? "?",
                      characteristicUUID: characteristic.uuid.uuidString,
                      data: value))
        updateCharacteristic(characteristic)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !writeContinuations.isEmpty else { return }
        let continuation = writeContinuations.removeFirst()
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}

// MARK: - Central delegate relay

/// Routes connect/disconnect events from the (single) central delegate —
/// the BLEScanner — to whichever session owns the peripheral.
public final class ConnectionRelay {
    public static let shared = ConnectionRelay()
    private var sessions: [UUID: WeakBox] = [:]

    private struct WeakBox { weak var session: BLEDeviceSession? }

    func register(_ session: BLEDeviceSession, for id: UUID) {
        sessions[id] = WeakBox(session: session)
    }

    public func didConnect(_ id: UUID) {
        sessions[id]?.session?.handleConnected()
    }

    public func didFailToConnect(_ id: UUID, error: Error?) {
        sessions[id]?.session?.handleFailedToConnect(error: error)
    }

    public func didDisconnect(_ id: UUID, error: Error?) {
        sessions[id]?.session?.handleDisconnected(error: error)
    }
}
