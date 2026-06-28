# Setup Guide

## Prerequisites

- macOS 14+ with Xcode 16+ (Swift 6 toolchain)
- [Homebrew](https://brew.sh)
- An iPhone running iOS 17+ (BLE doesn't work in the iOS Simulator)
- An Apple Developer account (free is fine for device installs; paid is
  required for CloudKit)

## 1. Generate the Xcode project

The project is defined declaratively in `project.yml` (XcodeGen), so there is
no checked-in `.xcodeproj` to merge-conflict.

```bash
brew install xcodegen
cd ~/TP25Studio
xcodegen generate
open TP25Studio.xcodeproj
```

## 2. Signing

1. In Xcode, select the **TP25Studio-iOS** target → *Signing & Capabilities*.
2. Choose your team. Repeat for **TP25Studio-macOS**.
3. Or set `DEVELOPMENT_TEAM` in `project.yml` and re-run `xcodegen generate`.

## 3. Bundle IDs and iCloud container

Defaults use the `com.yourteam` prefix. Before App Store work, change in
`project.yml`:

- `options.bundleIdPrefix`
- `PRODUCT_BUNDLE_IDENTIFIER` on both targets
- the iCloud container `iCloud.com.yourteam.tp25studio` (both entitlement
  blocks) **and** `CloudSync.containerIdentifier` in
  `TP25Kit/Sources/CloudSync/CloudSync.swift` — these must match.

CloudKit setup:

1. developer.apple.com → *Certificates, Identifiers & Profiles* → register
   both app IDs with the iCloud capability and attach the container.
2. First run creates the schema automatically in the CloudKit **Development**
   environment. Deploy schema to Production from the CloudKit Console before
   release.

No iCloud yet? Everything still works — the apps call
`CloudSync.makeContainerWithFallback()` which defaults to a **local-only**
store. Important: do NOT pass `cloud: true` before the iCloud entitlements
exist on the target — CloudKit mirroring without the entitlement crashes
asynchronously at launch (it cannot be caught). Once entitlements are added,
change the call in `TP25StudioApp.swift` / `TP25StudioMacApp.swift` to
`makeContainerWithFallback(cloud: true)` and sync turns on.

## 4. Run

- **Mac app**: select `TP25Studio-macOS` → My Mac → Run. Grant the Bluetooth
  permission prompt.
- **iPhone app**: select `TP25Studio-iOS` → your physical iPhone → Run.

## 5. Package tests

```bash
cd ~/TP25Studio/TP25Kit
swift test
```

## 6. First session with your TP25

1. Power the light on and put it near the Mac or iPhone.
2. Open **Discover** (iOS) or **BLE Explorer** (macOS) and scan. The light
   typically advertises a name containing `TP25`, `SS`, or similar — the app
   flags likely lights with a 💡 icon, but check *All devices* if unsure.
3. Connect, then run the **Discovery Assistant** and follow the prompts.
4. When a probe visibly changes the light, tap **Light Reacted** — production
   controls unlock immediately.
5. If nothing matches, follow `docs/REVERSE_ENGINEERING_GUIDE.md`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| No devices in scan | Bluetooth off, or light is paired/connected to the official app — force-quit "SS LED Video Light" on your phone |
| `state != poweredOn` | Grant Bluetooth permission in Settings/System Settings |
| Writes succeed but light ignores them | Wrong characteristic or family — run the assistant again, or sniff the official app (RE guide) |
| CloudKit errors on launch | Container not provisioned — app falls back to local storage; finish step 3 |
| Mac sandbox denies export | Exports use save panels (user-selected file access); App Support files are always allowed |
