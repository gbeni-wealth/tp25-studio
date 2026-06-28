# Capturing the official "SS LED Video Light" app (iPhone — sysdiagnose method)

Goal: record exactly what the official app writes to the TP25 over Bluetooth,
so we can decode the real command protocol. The **Bluetooth logging profile +
sysdiagnose** captures it entirely on the iPhone — no PacketLogger, no extra Mac
downloads, no USB cable needed.

## One-time setup (iPhone)
1. In Safari on the iPhone, open
   <https://developer.apple.com/bug-reporting/profiles-and-logs/>.
2. Find **Bluetooth** → download the configuration profile.
3. Settings → General → **VPN & Device Management** → install the
   "Bluetooth" profile (enter your passcode).
4. **Restart the iPhone** (required — logging only starts after the reboot).

> The profile expires after ~3 days. Reinstall it if you capture again later.

## Capturing a session

> ⚠️ **Critical:** the TP25 accepts only ONE Bluetooth connection at a time.
> Before capturing, in TP25 Studio on the Mac click **Disconnect** on the light
> (or quit the Mac app) so the iPhone's SS LED app can connect to it.
>
> Note: the TP25 power switch is **physical-only** — capture brightness/colour/
> effects, not power.

1. Put the TP25 **on its charger** and switch it **ON** (physical switch). On
   the charger it's stable; off-charger flickering ruins the data.
2. On the iPhone, open **SS LED Video Light** and connect to the light.
3. Do these actions **one at a time, ~2 seconds apart** (the spacing is what
   lets the decoder line each command up with what you did):
   - Brightness **10%** → **50%** → **90%**
   - CCT mode: **3200K** → **5600K**
   - Colour: pure **Red** → **Green** → **Blue**
   - **One effect** (e.g. the first FX)
4. **Immediately** trigger a sysdiagnose: press and release **Volume Up +
   Volume Down + Side button** all together. You'll feel a short vibration.
   (Do this right after the actions — the log buffer holds recent traffic.)
5. **Wait ~10 minutes** for it to finish gathering.

## Get the file to the Mac
1. iPhone: Settings → **Privacy & Security** → **Analytics & Improvements** →
   **Analytics Data**.
2. Scroll to a file named like **`sysdiagnose_2026.06.11_…`** (tap it → Share →
   **AirDrop** to this Mac). It's large (50–200 MB) — that's normal.
3. It lands in `~/Downloads`. Tell Claude it's there.

Claude then extracts the Bluetooth packet log from inside the sysdiagnose,
pulls every write the SS LED app sent to characteristic `FFE1`, matches them to
the actions above, and builds the TP25 protocol map so the app's controls work.
