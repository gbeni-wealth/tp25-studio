import Foundation
import CoreBluetooth
import Observation

/// Scans for peripherals and exposes them as observable `DiscoveredDevice`s.
/// All CoreBluetooth callbacks arrive on the main queue.
@Observable
public final class BLEScanner: NSObject {
    public private(set) var devices: [DiscoveredDevice] = []
    public private(set) var isScanning = false
    public private(set) var state: CBManagerState = .unknown
    /// Show every BLE device, or only ones that look like lights.
    public var showAllDevices = true

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    /// startScan() before Bluetooth is powered on defers until it is.
    private var wantsScan = false

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public var visibleDevices: [DiscoveredDevice] {
        let list = showAllDevices ? devices : devices.filter(\.looksLikeLight)
        // Stable order: likely-lights pinned to the top, otherwise discovery
        // order. We deliberately do NOT sort by live RSSI — that made rows
        // jump around on every advertisement and was impossible to tap.
        return list.enumerated()
            .sorted { a, b in
                if a.element.looksLikeLight != b.element.looksLikeLight {
                    return a.element.looksLikeLight
                }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    public func startScan() {
        wantsScan = true
        guard central.state == .poweredOn else { return } // resumes in didUpdateState
        devices.removeAll()
        // No service filter: TP25 services are unknown until discovered.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
    }

    public func stopScan() {
        wantsScan = false
        central.stopScan()
        isScanning = false
    }

    /// Hand back the CBPeripheral for a discovered device so a session can connect.
    public func peripheral(for device: DiscoveredDevice) -> CBPeripheral? {
        peripherals[device.id]
    }

    /// Re-acquire a peripheral we've connected to before by its UUID, without
    /// waiting for a fresh advertisement. Powers one-tap reconnect from the
    /// saved-lights registry. Returns nil if Bluetooth can't resolve it.
    public func retrievePeripheral(id: UUID) -> CBPeripheral? {
        if let cached = peripherals[id] { return cached }
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first
        else { return nil }
        peripherals[id] = peripheral
        return peripheral
    }

    public var centralManager: CBCentralManager { central }
}

extension BLEScanner: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if state == .poweredOn {
            if wantsScan && !isScanning { startScan() }
        } else {
            isScanning = false
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        ConnectionRelay.shared.didConnect(peripheral.identifier)
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral, error: Error?) {
        ConnectionRelay.shared.didFailToConnect(peripheral.identifier, error: error)
    }

    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        ConnectionRelay.shared.didDisconnect(peripheral.identifier, error: error)
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any],
                               rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral

        var adv: [String: String] = [:]
        for (key, value) in advertisementData {
            switch value {
            case let data as Data: adv[key] = data.hexAsciiDump
            case let uuids as [CBUUID]: adv[key] = uuids.map(\.uuidString).joined(separator: ", ")
            case let dict as [CBUUID: Data]:
                adv[key] = dict.map { "\($0.key.uuidString)=\($0.value.hexAsciiDump)" }.joined(separator: "; ")
            default: adv[key] = String(describing: value)
            }
        }

        let device = DiscoveredDevice(
            id: peripheral.identifier,
            name: (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                ?? peripheral.name ?? "Unknown",
            rssi: RSSI.intValue,
            advertisementData: adv,
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            serviceUUIDs: (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
                .map(\.uuidString) ?? [],
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? true,
            lastSeen: Date()
        )

        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            // Keep the richest name/services seen so far.
            var merged = device
            if merged.name == "Unknown" { merged.name = devices[index].name }
            if merged.serviceUUIDs.isEmpty { merged.serviceUUIDs = devices[index].serviceUUIDs }
            if merged.manufacturerData == nil { merged.manufacturerData = devices[index].manufacturerData }
            devices[index] = merged
        } else {
            devices.append(device)
        }
    }
}
