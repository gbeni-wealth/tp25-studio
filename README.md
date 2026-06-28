# TP25 Studio

Native iPhone + Mac apps for discovering, reverse-engineering, and controlling
**SuteFoto TP25 RGB lights** (and similar SuteFoto/SS LED video lights) over
Bluetooth LE.

> **The golden rule of this codebase:** the BLE protocol is *not assumed*.
> Phase 0 tooling (scanner, GATT explorer, packet monitor, discovery
> assistant, diff viewer) discovers the protocol on your actual hardware and
> records it into a **Protocol Map**. Production controls (dashboard, themes,
> presets, effects) only work through that map.

## Project layout

```
TP25Studio/
├── project.yml                  # XcodeGen project definition (both apps)
├── TP25Kit/                     # Shared Swift package (all the logic)
│   ├── Sources/
│   │   ├── BluetoothCore/       # CoreBluetooth: scanner, sessions, packet log, recorder
│   │   ├── ProtocolEngine/      # Commands, protocol families, map, diff, doc generator
│   │   ├── DeviceManager/       # Light model, per-light controller, multi-light fleet
│   │   ├── ThemeEngine/         # Themes, theme player, random colour engine, FX catalog
│   │   ├── PresetEngine/        # SwiftData models + preset operations
│   │   ├── CloudSync/           # CloudKit-backed SwiftData container
│   │   ├── DeveloperTools/      # Console command parsing (hex/UTF-8/presets)
│   │   └── SharedUI/            # Glass panels, colour wheel, dashboards, RE views
│   └── Tests/                   # Unit tests (protocol, themes, tools)
├── Apps/
│   ├── iOS/Sources/             # iPhone app (tabs: Lights, Themes, Random, Presets, Music, Discover)
│   └── macOS/Sources/           # Mac app (BLE Explorer, Sniffer, Protocol Lab, Theme Studio…)
└── docs/
    ├── SETUP.md                 # Build & signing instructions
    └── REVERSE_ENGINEERING_GUIDE.md
```

## Architecture

- **Swift 6 toolchain / SwiftUI / MVVM** with `@Observable` models.
  (The package currently builds in Swift 5 language mode; strict-concurrency
  migration is the tracked next step — see `swiftLanguageModes` in
  `TP25Kit/Package.swift`.)
- **Module boundaries**: `ProtocolEngine` is pure (no CoreBluetooth import) and
  talks to hardware via the `CommandTransport` protocol; `DeviceManager`
  adapts a live `BLEDeviceSession` to it. This keeps the discovery assistant,
  encoders, and diff tools fully unit-testable.
- **Protocol Map**: a persisted JSON document
  (`~/Library/Application Support/TP25Studio/protocol-map.json`) mapping
  command kinds (power, brightness, CCT, HSI, RGB, RGBCW, FX, channel) to a
  characteristic + encoder. Encoders are either a known **protocol family**
  (Neewer-style `0x78…checksum`, ELK-BLEDOM `7E…EF`, Triones `0x56…`) or a
  **learned template** captured with the diff viewer.
- **CloudKit sync** via SwiftData's CloudKit mirroring: presets, custom
  themes, device aliases and saved groups sync between iPhone and Mac
  automatically once the iCloud container is provisioned.

## The discovery workflow (Phase 0)

1. **Scan** — see name, UUID, RSSI, advertisement + manufacturer data,
   service UUIDs for every nearby device.
2. **Connect + explore** — full GATT tree; every readable characteristic is
   read, every notifiable characteristic auto-subscribed.
3. **Discovery Assistant** — sends one *safe, visible, harmless* probe at a
   time (e.g. "CCT 5600K @ 30%") and asks you whether the light reacted.
   A confirmed probe registers the protocol family on that characteristic and
   infers the rest of the family's commands (marked *unverified*).
4. **Packet monitor + diff viewer** — if no family matches, capture the
   official "SS LED Video Light" app's traffic patterns (see the RE guide),
   replay candidate writes from the console, then diff packets to find
   parameter bytes and checksums, and save them as command templates.
5. **Export** — JSON/CSV session exports and a generated markdown protocol
   document.

## Building

See [docs/SETUP.md](docs/SETUP.md). Short version:

```bash
brew install xcodegen
cd TP25Studio
xcodegen generate
open TP25Studio.xcodeproj
```

Run the shared-package tests without Xcode:

```bash
cd TP25Studio/TP25Kit
swift test
```

## Feature checklist

- [x] BLE scanner with full advertisement display
- [x] GATT service/characteristic explorer with live values
- [x] Notification monitor with timestamps + hex payloads
- [x] Developer console (hex / UTF-8 / preset test commands) with history & replay
- [x] Session recorder with JSON + CSV export
- [x] Guided protocol discovery assistant → protocol map
- [x] Packet diff viewer with checksum detection → command templates
- [x] Protocol documentation generator (markdown)
- [x] Dashboard: power, brightness, CCT, HSI, RGB (wheel/sliders/hex), RGBCW
- [x] FX engine with extensible catalog (IDs verified per-device)
- [x] 9 built-in themes + Theme Studio designer (macOS) with live preview
- [x] Random colour engine: 6 palettes, timing, limits, similarity/repeat avoidance
- [x] Multi-light fleet: select/all targeting, groups & channels, synced fades
- [x] Presets: save/rename/duplicate/favourite + CloudKit sync
- [x] Music reactive mode (iOS): amplitude → brightness, beat → colour
- [x] Unit tests for protocol engine, random engine, console tools

## Safety notes

- The discovery assistant only sends *low-brightness, visible-state* probes —
  never firmware/OTA-looking payloads. Don't write random bytes to unknown
  characteristics on devices you can't factory-reset.
- This project is for controlling lights **you own**.
