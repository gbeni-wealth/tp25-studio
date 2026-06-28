# SuteFoto TP25 — BLE Protocol (decoded)

Reverse-engineered 2026-06-11 from a capture of the official **"SS LED Video
Light"** app (iPhone sysdiagnose → `bluetoothd-hci-latest.pklg` →
`tools/decode_pklg.py`). Every frame below was verified byte-for-byte against
the app's on-screen values.

## Transport

| | |
|---|---|
| Advertised name | `STX25RGB-…` (prefix `STX25`) |
| Control service | `FFE0` |
| Control characteristic | `FFE1` (Write / Write Without Response / Notify) |
| Battery | standard `180F` / `2A19` |
| Power | **physical switch only** — no BLE power command |

`FFE1` also continuously **notifies** an ASCII debug-telemetry stream
(`bhg:…_bv…_vn…-AI…-CI…-SI…-pw…-qi…-T:…c--bcnt:…-lvin:…`, `VIN…_BAT…-QI…-pwm…`).
This is status output, not the command channel.

## Frame format

```
FA <cmd> 00 00 00 <data…> <checksum> 8A
```

- `FA` start byte, `8A` end byte.
- `<cmd> 00 00 00` — command byte followed by 3 reserved zero bytes.
- `checksum` = (sum of every byte from `<cmd>` through the last data byte) & 0xFF.

## Commands

### 0x06 — CCT
```
FA 06 00 00 00  II  KH KL  GM  CK 8A
```
- `II` intensity 0–100 (0x00–0x64)
- `KH KL` colour temperature in Kelvin, big-endian (range **2800–10000 K**)
- `GM` green/magenta compensation, signed byte (`00` = neutral, `FF` = −1)

Example — 50 %, 2800 K, neutral: `FA 06 00 00 00 32 0A F0 00 32 8A`

### 0x07 — HSI
```
FA 07 00 00 00  II  HH HL  SS  CK 8A
```
- `II` intensity 0–100
- `HH HL` hue 0–360°, big-endian
- `SS` saturation 0–100

Verified — 17 %, 170°, 34: `FA 07 00 00 00 11 00 AA 22 E4 8A`

### 0x08 — RGBCW
```
FA 08 00 00 00  R  G  B  CW  WW  CK 8A
```
- `R G B` red/green/blue, each 0–100
- `CW` "Less Warm" (cool white) 0–100, `WW` "More Warm" (warm white) 0–100

Verified — R8 G0 B6 LW0 MW1: `FA 08 00 00 00 08 00 06 00 01 17 8A`

### 0x09 — FX
```
FA 09 00 00 00  ID  FR  II  CK 8A
```
- `ID` effect 1–10, in the app's grid order:
  1 Lightning · 2 Police · 3 Fire truck · 4 Ambulance · 5 Fire ·
  6 Fireworks · 7 Fault bulb · 8 TV · 9 RGB Circle · 10 Paparazzi
- `FR` frequency/speed, `II` intensity 0–100

Verified — Fire, freq 4, 11 %: `FA 09 00 00 00 05 04 0B 1D 8A`

### 0x01–0x05 — status queries
Single-byte query frames (`FA 0X 0X 8A`) the app sends at connect to read
device state. Not required for control.

## Per-zone control — NOT externally addressable (tested 2026-06-11)

The Police/Fire-truck effects split the panel into two colours, proving the
hardware has ≥2 independently-driven zones. But that split is **firmware-internal
to the FX routines** — there is no BLE command to set a zone directly. Verified
with a guided probe ("Zone Probe", since removed) over **two rounds, 12 frame
formats**, all on a real TP25:

- reserved bytes #1/#2/#3 as a zone selector (`FA 08 RR RR RR …`) — no effect
- new command ids `0x0A`, `0x0B`, `0x0C` with `[zone,R,G,B]` — rejected/ignored
- HSI (`0x07`) with a zone byte — no effect
- **both colours in one frame** (`0x08` with `R1 G1 B1 R2 G2 B2`, and two full
  RGBCW blocks) — rendered whole-panel one colour
- custom-effect form of `0x09` with two embedded colours — no effect

Only the whole-light sanity frame worked. Conclusion: **multi-colour-at-once on a
single TP25 is not achievable over the known protocol.** For a real two-colour
look, use two physical lights (each is a "zone") or a temporal blend strobe.

## Notes

- **Brightness** is not a standalone command — it's the intensity field of the
  active mode. Re-send the current mode's frame with a new intensity.
- **Power off** = intensity 0 in the active mode (matches `pwm0` in telemetry).
- Implemented in code as `ProtocolFamily.suteFotoFA`; the ready-to-use map is
  `ProtocolMap.suteFotoTP25`.
