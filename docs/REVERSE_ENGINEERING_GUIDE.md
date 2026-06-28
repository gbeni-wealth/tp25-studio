# Reverse-Engineering Guide — SuteFoto TP25 (and related SS LED lights)

This guide is the field manual for discovering the TP25's BLE protocol with
the tools built into TP25 Studio. It applies to any light driven by the
official **"SS LED Video Light"** app.

## What we know from the manual

- Bluetooth control via the "SS LED Video Light" app
- Modes: **CCT**, **HSI**, **RGBCW**, **FX**
- **6 groups**, **12 channels**, multi-light control

What we *don't* know until measured: service/characteristic UUIDs, packet
framing, parameter encodings, checksums, and whether the light reports state
(battery, current mode) via notifications.

## Strategy overview

```
1. Passive recon   → scan, read advertisement + GATT
2. Guided probing  → Discovery Assistant (known LED families)
3. Active capture  → sniff the official app, replay + diff
4. Template build  → diff viewer → command templates → protocol map
5. Document        → generated markdown, session exports
```

## Step 1 — Passive recon

Scan in **BLE Explorer** (Mac) or **Discover** (iPhone). Record:

- Advertised name (note the exact prefix — add it to the protocol map's
  `deviceNamePrefixes` so future auto-detection works)
- Service UUIDs in the advertisement
- Manufacturer data (company ID = first 2 bytes, little-endian)

Connect. The app reads every readable characteristic and subscribes to every
notify characteristic automatically. Look for:

- **Standard services**: `180F` (Battery — gives you battery level for free),
  `180A` (Device Info — model/firmware strings)
- **Vendor services**: 16-bit UUIDs like `FFF0`/`FFE5`/`FFD5`, or 128-bit
  vendor UUIDs (e.g. `6940xxxx-…` on Neewer-family hardware)
- The **write characteristic** is usually the one with `write`/`writeNR` in a
  vendor service; the **status characteristic** has `notify`.

## Step 2 — Guided probing (Discovery Assistant)

The assistant crosses three known LED-light protocol families with every
writable characteristic, hint-matched pairs first:

| Family | Frame | Typical UUIDs |
|---|---|---|
| Neewer-style | `78 tag len payload… sum&0xFF` | `69400001/2/3` |
| ELK-BLEDOM | `7E … EF` | `FFF0` / `FFF3` |
| Triones | `56 RR GG BB 00 F0 AA`, power `CC 23/24 33` | `FFD5` / `FFD9` |

Probes are deliberately *visible but harmless* (low-brightness CCT/colour
changes, power on). When you confirm a reaction, the family is registered for
that characteristic, the remaining commands of the family are inferred
(marked **unverified** — verify each from the dashboard), and production
controls unlock.

**Verify inferred commands one by one.** A light can match a family's colour
command but use a different brightness tag. Anything wrong → fix it with
Step 4 templates, which override family entries per command kind.

## Step 3 — Active capture of the official app

If no family matches, capture what "SS LED Video Light" actually sends:

### Option A — Apple PacketLogger (recommended, no extra hardware)

1. Install the **Bluetooth** profile from
   [developer.apple.com/bug-reporting/profiles-and-logs](https://developer.apple.com/bug-reporting/profiles-and-logs/)
   on the iPhone that runs the official app.
2. Install Xcode's *Additional Tools* → **PacketLogger** on the Mac.
3. Start a capture, then use the official app: toggle power, sweep
   brightness 10→50→90, set pure red/green/blue, switch CCT 3200K→5600K, try
   one FX.
4. **Do one action at a time and write down the order** — this is what makes
   the diff step trivial.
5. Filter PacketLogger to ATT `Write Command` / `Write Request` packets for
   the light's handle. Note the characteristic handle and copy hex payloads.

### Option B — Android HCI snoop log

Developer options → *Enable Bluetooth HCI snoop log* → use the official app →
pull `btsnoop_hci.log` (via `adb bugreport`) → open in Wireshark, filter
`btatt.opcode == 0x52 || btatt.opcode == 0x12`.

### Option C — nRF Connect (manual)

Use nRF Connect (iOS/Android) to enumerate GATT and hand-test writes; mirror
anything that works in TP25 Studio's developer console so it gets logged.

## Step 4 — Replay, diff, template

1. In the **Developer Console**, replay a captured payload against the
   suspected write characteristic (paste hex). Light reacts → right
   characteristic.
2. Send several variants of the *same* command captured at different values
   (e.g. three brightness levels). They're now in the packet monitor.
3. Select them and open the **Diff Viewer**:
   - Constant bytes = framing/opcodes.
   - The byte that tracks your swept parameter = the parameter byte.
   - A trailing byte that changes whenever anything changes = checksum — the
     diff tool auto-detects `sum & 0xFF` and XOR checksums.
4. Pick the command kind and **Save Command Template**. The template (base
   bytes + parameter offsets + checksum rule) is stored in the protocol map
   and immediately drives the production UI.

Repeat per command kind: power, brightness, CCT, HSI/RGB, RGBCW, FX, channel.

### Groups & channels

The manual's 6 groups / 12 channels usually work in one of two ways:

- **Broadcast-style**: every packet carries a group/channel byte — you'll see
  it in diffs when changing groups in the official app.
- **Device-set**: a dedicated "set channel" command. Capture the official
  app's group screen to find it, save it as a `channel` template.

Multi-light sync in TP25 Studio doesn't depend on either: the fleet
controller writes to each connected light concurrently.

## Step 5 — Document and share

- **Sniffer → Protocol Docs** generates markdown with GATT structure,
  confirmed commands, templates and observed notifications.
- **Record Session** stores complete JSON sessions in
  `~/Library/Application Support/TP25Studio/Sessions/`; CSV export for
  spreadsheets.
- Commit the generated protocol doc to this repo under `docs/` so other
  SuteFoto owners benefit.

## Decoding notifications

If a notify characteristic emits data when you change settings *on the light
itself* (physical buttons), that's the state-report channel. Capture one
packet per known state, diff them the same way, and you can populate battery,
mode and brightness in the home-screen cards (`Light.batteryPercent` etc.).

## Safety rules

- Probe at **low brightness** — don't strobe a light at 100% on your desk.
- Never write to characteristics in `180A`/`1801` or anything that mentions
  OTA/DFU/firmware in its UUID or service neighbours.
- One unknown write at a time, watching the light; keep payloads ≤ 20 bytes
  unless captures show the official app sending longer ones.
- If the light wedges, power-cycle it — these lights keep no persistent state
  from control packets.
