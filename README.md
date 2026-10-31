<div align="center">

# zenbook-duo-2026-linux

### Make the 2026 ASUS Zenbook Duo (UX8407AA) work properly on Linux.

Touchscreens, sound, rotation, both screens, brightness, keyboard, battery and performance:
one command fixes them, one command undoes it.

[![License: GPL-2.0](https://img.shields.io/badge/license-GPL--2.0-c4b5fd?style=flat-square)](LICENSE)
[![Linux 7.2+](https://img.shields.io/badge/linux-7.2%2B-86efac?style=flat-square)](#kernel-and-distribution-compatibility)
[![Hardware](https://img.shields.io/badge/hardware-UX8407AA-fbbf24?style=flat-square)](#is-this-for-my-laptop)
[![No kernel rebuild](https://img.shields.io/badge/kernel%20rebuild-not%20required-86efac?style=flat-square)](#faq)
[![Arch / CachyOS](https://img.shields.io/badge/distro-Arch%20%7C%20CachyOS-7dd3fc?style=flat-square)](#kernel-and-distribution-compatibility)

</div>

---

## What it fixes

| | Plain Linux | With zenbook-duo-2026-linux |
|---|:---:|:---:|
| 👆 **Top touchscreen and pen** | ❌ dead | ✅ works |
| 🔊 **Speakers, microphones, headphones** | ❌ no sound on kernel 7.2 | ✅ works, with ASUS speaker tuning |
| 🔄 **Auto-rotate and the two-screen layout** | ❌ upside down, touch breaks | ✅ follows how you hold it |
| ⌨️ **Keyboard lying on the bottom screen** | ⚠️ bottom screen stays on | ✅ turns off, back on when lifted |
| 😴 **Lid closed over the keyboard** | ❌ wakes up again and again, battery drains in a bag | ✅ stays asleep |
| 🧊 **Powered on with the keyboard on it** | ❌ bottom screen lost, lifting the keyboard can freeze the laptop | ✅ bottom screen works |
| 🔐 **Login screen** | ❌ upside down | ✅ right way up, follows rotation and the keyboard |
| 🔆 **Screen brightness** | ❌ slider does nothing | ✅ one slider, both screens |
| 🎨 **Colour** | ⚠️ 6-bit with dithering | ✅ 10-bit |
| 🖱️ **Mouse cursor on the top screen** | ❌ ghost copies stay behind | ✅ clean |
| 💡 **Keyboard backlight and Fn keys** | ❌ backlight stuck, most keys dead when attached | ✅ work, attached and on Bluetooth |
| 🖐️ **Palm on the touchpad while typing** | ❌ cursor jumps, stray clicks | ✅ ignored, attached and on Bluetooth |
| ↕️ **Keyboard touchpad motion** | ⚠️ cursor hitches on Bluetooth, up/down 3% slower than left/right | ✅ smooth, equal on both axes |
| 🎯 **Touchpad acceleration** (optional) | ⚠️ too fast when aiming, too slow for medium moves | ✅ Apple's trackpad curve |
| 🧭 **Rotation, light and hinge sensors** | ❌ missing | ✅ work |
| 🚀 **Performance** | ⚠️ capped at 20 W | ✅ Windows power limits (up to 64 W) |
| 🤫 **Quiet / battery-saver mode** | ⚠️ does nothing | ✅ quiet fans, lower power |
| 📶 **Wi-Fi responsiveness** | ⚠️ lag spikes up to 158 ms | ✅ 7 ms when plugged in |
| 🔋 **Idle power** | ⚠️ several devices never power down | ✅ idle devices power down |
| 🩺 **After kernel updates** | ⚠️ fixes can silently stop working | ✅ you get told |
| 📊 **Power draw in the panel** | ❌ only a battery percentage; "Charging" even while a weak charger lets the battery drain | ✅ live watts on battery and plugged in, real charging rate, where they go, temperatures, power mode |

Already fine on plain Linux: sleep (about 0.9% battery per hour with the lid closed), the bottom touchscreen and pen, Wi-Fi 7, Bluetooth, webcam, NPU and video acceleration.
Not yet: **HDR** (comes with a library update your distribution hasn't shipped yet), **VRR** (broken in the kernel for now).

## Install

```sh
git clone https://github.com/burakgon/zenbook-duo-2026-linux.git && cd zenbook-duo-2026-linux
sudo ./duo apply --recommended
sudo reboot
```

After the reboot, `./duo list` should say **All modules healthy**. Changed your mind? `sudo ./duo revert --all` puts everything back.

> [!IMPORTANT]
> **Without `display-edp2-tcss`, power the laptop on with the keyboard lifted off the bottom screen** (restarts too). After a power-on with the keyboard lying on it, a kernel bug breaks the bottom screen, and turning it on can freeze the whole system ([details](#if-the-bottom-screen-stays-black)). `display-edp2-tcss` fixes the bug in the driver; it is applied by default.

## If the bottom screen stays black

A kernel bug (xe #9196): the bottom panel's display PHY sits in the Type-C subsystem and needs that subsystem's power, which the driver never requests; only the firmware does, and only when it lights the panel at power-on, which it skips while the keyboard covers it. After such a power-on (or restart) the first attempt to turn the panel on fails; it can stall windows for 10 seconds or freeze the whole system, and a normal reboot does not fix it.

**`display-edp2-tcss` fixes it:** a DKMS build of the xe driver that requests that power itself (verified: docked power-on, then lifting, docking and lifting the keyboard again, all without an error). It is rebuilt on every kernel update.

Without it (for example on a kernel the patched driver did not build for), `desktop-kde-duo` remembers whether the keyboard was docked at power-on. If it was, lifting the keyboard leaves the bottom screen off for that boot and shows a notification instead of turning it on. Shut down and power on with the keyboard lifted to use it again.

If the bottom screen still fails (the kernel log check below, or the notification "Bottom screen stopped responding"), it stays off for the rest of that boot. To recover:

1. Shut down, unplug the charger.
2. Hold the power button for 15 seconds, wait a minute.
3. Power on **with the keyboard lifted off**.

`./duo doctor` reports it as a FAIL line. A kernel-side fix exists as a proposal ([TCSS power request before PHY B setup](https://github.com/therealarnold666/zenbook-duo26-Ubuntu26.04/tree/main/patches/kernel)); it is not upstream yet.

## Is this for my laptop?

This check is read-only and needs no root:

```sh
curl -fsSL https://raw.githubusercontent.com/burakgon/zenbook-duo-2026-linux/main/tools/check-hardware.sh | bash
```

Made for the **2026 ASUS Zenbook Duo, model UX8407AA** (Intel Core Ultra Series 3) on **Arch / CachyOS** with **KDE Plasma** (Wayland).
**Not for the older Zenbook Duo models** (UX8406 from 2024/2025, UX481/UX482): they use different hardware, and the fixes refuse to install there.
Most fixes also work on other distributions and desktops; see [compatibility](#kernel-and-distribution-compatibility).

**ASUS ROG Zephyrus Duo 2026 (GX651AX):** three modules of its own, `display-zephyrus-bottom-edp` (bottom screen), `wifi-zephyrus-dock-toggle` (Wi-Fi toggled by docking the keyboard) and `power-zephyrus-asusd` (asusd racing power-profiles-daemon on plug and unplug); it also takes `power-profile-sync` from the Zenbook, so power-saver reaches the firmware's low-power mode. Each module declares the board it is for (`DMI_BOARD` in `module.conf`); on a GX651AX the Zenbook modules show `n/a`, so `sudo ./duo apply --recommended` applies only these.

## Details

<details>
<summary><b>🔬 What exactly was wrong, and how each fix works</b></summary>

Measured on a UX8407AA with BIOS 310, `linux-cachyos` 7.2.9 and KDE Plasma 6.7.

| Hardware | Out of the box | With this repo | Module |
|---|---|---|---|
| **Top touchscreen + pen** (Raydium `RAYD0001`) | Dead. `raydium_i2c_ts` grabs a HID-over-I2C device it can't drive, and can Oops in `raydium_i2c_irq`. | Touch, multitouch and pen work through `i2c-hid`, under the finger (the digitizer sits 180° from its upside-down panel). | `touchscreen-hid` |
| **Speakers, headphones, mics** (CS42L43 + 2× CS35L56) | On 7.2.x: no sound card, only "Dummy Output". The BIOS declares an RT722 that isn't fitted, and `sof_sdw` fails with `-12`. 7.2.11 breaks it a second way: it backported only half of an upstream pair, and the card waits for a CS35L56 DAI (`cs35l56-ot25`) that the driver never registers. | Sound card registers; speakers use ASUS's calibrated amp tuning, HiFi profile, jack detection. (7.3+ has both fixes upstream; the second is queued for 7.2.12.) | `audio-ghost-rt722`, `audio-cs35l56-ot25` |
| **Accelerometer, ambient light, hinge sensor** (Intel ISH) | No sensors at all. The ISH rejects the generic firmware, so there is no auto-rotation and no auto-brightness. | All three sensors run on ASUS's signed ISH image, downloaded from ASUS and checksum-verified. | `sensors-ish-firmware` |
| **Rotation** | Screens upside down (the top panel is mounted 180° rotated). KWin turns both panels the same way, touch stops working after any rotation, and a brief tilt flips the screen. | Correct orientation; both panels rotate together, laid out around the hinge (laptop, tent, book). Touch and pen follow every change. Rotation waits for a 1 s stable reading. | `sensors-accel-mount`, `desktop-kde-duo` |
| **Keyboard on the bottom screen** | The bottom panel stays on under the keyboard and keeps drawing power. | The bottom panel turns off when the keyboard docks, and back on when you lift it. | `desktop-kde-duo` |
| **Lid closed over the docked keyboard** | The keyboard (USB `0b05:1cd7`) keeps USB remote wakeup on and wakes the laptop from s2idle every 10–60 s; KDE puts it back to sleep each time. 134 suspend cycles in one hour; in a bag the battery drains and the laptop warms up. | The keyboard's USB wakeup is off while the lid is closed and back on after resume; a key press still wakes the laptop with the lid open. Since the fix: five lid-closed sleeps of up to 5.5 h, no keyboard wake. | `power-kbd-lid-wake` |
| **Power-on with the keyboard docked** | The firmware leaves the bottom panel's PHY (Port B, a C20 PHY inside the Type-C subsystem) unpowered and xe never requests TCSS power for it: `PHY B failed to request refclk`, then pipe B timeouts or a hard hang when the keyboard is lifted. Survives warm reboots. | xe requests TCSS power before programming the PHY clocks and releases it when the panel turns off; the bottom panel works after any power-on. | `display-edp2-tcss` |
| **Login screen** | Top panel upside down, panels side by side, touch not mapped. | The same duo-rotate runs on the login screen: correct orientation, rotation, touch mapping, panel off under the keyboard. | `desktop-kde-duo` |
| **Brightness** | Slider and keys change a number in sysfs, but the OLEDs don't get dimmer: the panels only take brightness over DPCD/AUX. | One slider and the brightness keys change both panels' **hardware** backlight. There is no software dimming layer. | `display-dpcd-backlight`, `desktop-kde-duo` |
| **Colour depth** | 6-bit + dithering (`bpp=18`): 2880×1800@144 Hz doesn't fit the eDP link at 8 bpc, and the driver drops bits instead of using DSC. | 10-bit (`bpp=30`) through DSC; Panel Replay keeps working, same power. | `display-dsc-10bit` |
| **Cursor on the top screen** | 2–3 frozen copies of the cursor stay on screen (Panel Replay *Early Transport* bug). | One cursor. Only Early Transport is off; Panel Replay Selective Update keeps saving power. | `display-psr-et-off` |
| **Keyboard backlight, Fn keys** | The backlight never changes (stock `hid-asus` sends 64-byte reports, the keyboard times out with `-110`). Most Fn keys are dead over USB. The mic-mute LED never lights. | 3-level backlight; Fn keys (brightness, mic mute, backlight, …) work over USB and Bluetooth; the mic-mute LED follows the mute state. | `keyboard-hid-asus` |
| **Keyboard touchpad while typing** | The touchpad is on USB (docked) or Bluetooth, so libinput treats it as external: no disable-while-typing, no palm detection, and the touchpad's own palm reports are ignored. | Marked as the lower half of a touchpad+keyboard combo: disable-while-typing, edge palm zones and firmware palm reports, docked and on Bluetooth. | `touchpad-palm` |
| **Keyboard touchpad motion** | On Bluetooth two reports often arrive in one connection event, 0.5 ms apart; libinput measures speed from arrival time, calls that a jump and drops the motion (4% of all motion, a hitch every few hundred ms). The kernel rounds the axes to 31 and 32 units/mm, so up/down moves 3% less than left/right. | A libinput plugin runs the jump test on the touchpad's own scan time (`MSC_TIMESTAMP`) instead; an hwdb entry sets 31 units/mm on both axes. | `touchpad-motion` |
| **Touchpad acceleration** (optional, not in `--recommended`) | libinput's curve gives 2–3 screen mm per finger mm when aiming slowly and stays flat up to 130 mm/s: too fast for fine aiming, too slow for medium moves. KWin 6.8 offers no custom curve. | Apple's Magic Trackpad 2 curve inside KWin for the keyboard touchpad only (a small preloaded library); KDE's speed slider picks Apple's tracking speed. Until Plasma 6.9 ships custom curves. | `touchpad-accel` |
| **Sustained performance** | No one runs Intel DTT: power limits stay at the firmware default, PL1 20 W / PL2 30 W. | Windows' own DTT tables per profile: balanced PL1 28→42 W / PL2 55 W, performance PL1 55 W / PL2 64 W. | `power-dtt` |
| **Power saver** | KDE's "Power Save" leaves the firmware in balanced: neither ASUS quiet nor the Intel low-power slider survives the shared `platform_profile` list. Switching straight from Performance snaps back to Balanced within a second. | Power Save = ASUS quiet fans + SoC low-power + Xe GPU power saving (Windows "Whisper": PL1 20–30 W). Every switch sticks. | `power-profile-sync` |
| **Wi-Fi latency** (BE201) | Power save always on: 16 ms average to the router, spikes to 158 ms. | On AC: 7 ms, no spikes. On battery: power save stays on. | `wifi-powersave-ac` |
| **Wi-Fi roaming** (WPA3, Wi-Fi 7 mesh) | mac80211 leaves the old AP without a deauthentication; with PMF the AP blocks the new association for about a second, but Linux gives up after 300 ms. On a TP-Link Deco every 5 → 6 GHz move on the same unit timed out (10 of 10) and the laptop fell back to a distant node. | The old AP is told that the laptop leaves; the same roams finish on the first try in ~70 ms. | `wifi-roam-deauth` |
| **Idle power** | Several PCI devices ship with runtime PM disabled; the fTPM is polled as an entropy source. | Runtime PM on (sensor hub, Wi-Fi and NVMe excluded on purpose), fTPM left alone. Idle package power 0.66–0.79 W. | `power-runtime-pm`, `power-tpm-rng` |

Works without this repo: suspend (s2idle, ~0.9% battery per hour lid closed), the bottom touchscreen and pen, Wi-Fi 7 (6 GHz / 320 MHz, 2.9 Gbit/s link), Bluetooth, the webcam and IR camera, NPU, GPU compute and video decode/encode.

Not there yet:
- **HDR:** needs libdisplay-info ≥ 0.4, which Arch doesn't ship yet; the panel puts its HDR metadata inside DisplayID 2.0.
- **VRR:** broken upstream on Panther Lake eDP; keep it at *Never*.

Details, logs and upstream references for each line: [`docs/hardware-report.md`](docs/hardware-report.md), [`docs/research-notes.md`](docs/research-notes.md).

</details>

<details>
<summary><b>🧪 What the hardware check looks for</b></summary>

| Check | Expected | Why it matters |
|---|---|---|
| Model (DMI) | `ASUS Zenbook Duo UX8407AA` | Each module refuses boards other than its `DMI_BOARD` (`DUO_FORCE=1` overrides) |
| CPU | Intel Core Ultra Series 3 (Panther Lake, family 6 model 204) | `xe` display, ISH, power tables |
| Touchscreens | ACPI `RAYD0001` (top) and `RAYD0002` (bottom) | `touchscreen-hid`, touch mapping |
| Audio | SoundWire, PCI subsystem `1043:1444`: CS42L43 + 2× CS35L56 | `audio-ghost-rt722` matches this board |
| Sensor hub | Intel ISH `8086:e445` | Needs ASUS's signed firmware for rotation and ambient light |
| Keyboard | ASUS `0b05:1cd7` (USB, docked) / `0b05:1cd8` (Bluetooth) | `keyboard-hid-asus`, `touchpad-palm`, `touchpad-motion`, `touchpad-accel` |
| Distribution | Arch, CachyOS or another Arch derivative | `pacman`/DKMS helpers; config-only modules work anywhere |
| Desktop | KDE Plasma 6 on Wayland | `desktop-kde-duo` (all other modules are desktop-independent) |

</details>

<details>
<summary><b>🛠️ Using duo: pick, check and undo single fixes</b></summary>

```sh
./duo list                                   # every fix: needed here? applied? healthy?
./duo info power-dtt                         # what it does and why
sudo ./duo apply touchscreen-hid power-dtt   # apply only some
./duo status                                 # health check of every fix
sudo ./duo revert power-dtt                  # undo exactly what it changed
./duo doctor                                 # whole-machine PASS / WARN / FAIL summary
./duo scan --acpi                            # full hardware snapshot (serials, MACs, SSIDs redacted)
```

Run `sudo ./duo apply` from your desktop user's shell: `desktop-kde-duo` builds a small Qt program and enables per-user services.

</details>

<details>
<summary><b>📦 The 23 modules</b></summary>

| Module | What it changes | Kernels |
|---|---|---|
| `touchscreen-hid` | Keeps `raydium_i2c_ts` off `RAYD0001`, so `i2c-hid` binds it; udev: libinput calibration for its 180° offset | all |
| `audio-ghost-rt722` | DKMS `soundwire-intel` with the upstream ghost-RT722 quirk (ca02ffd4975c) | 7.2.x |
| `audio-cs35l56-ot25` | DKMS `snd-soc-cs35l56` + `snd-soc-cs35l56-sdw` with the OT25 DAI (86c8360c97f6) that 7.2.11 left out | 7.2.11 |
| `sensors-ish-firmware` | ASUS-signed ISH firmware in `/usr/lib/firmware/updates` | all |
| `sensors-accel-mount` | hwdb accelerometer mount matrix (panels mounted 180°) | all |
| `desktop-kde-duo` | `duo-rotate` user service, also on the login screen (rotation, hinge layout, touch mapping, keyboard dock) + one brightness slider for both panels | KDE Plasma |
| `display-dpcd-backlight` | `xe.enable_dpcd_backlight=1` | all |
| `display-psr-et-off` | Panel Replay Early Transport off (debugfs bit at boot) | all |
| `display-dsc-10bit` | Forces DSC on both panels for 10 bpc (debugfs at boot) | all |
| `display-edp2-tcss` | DKMS `xe` that requests Type-C subsystem power for the bottom panel (xe #9196), built from the running kernel's own sources (a pacman hook fetches them) | 7.x |
| `keyboard-hid-asus` | DKMS `hid-asus`: Duo IDs, 16-byte feature reports, hotkey descriptor fix, Fn-lock, mic-mute LED, battery report kept out of the hotkeys | 7.2.x, 7.3.x |
| `touchpad-palm` | libinput quirk: the keyboard's touchpad as a touchpad+keyboard combo (palm rejection, disable-while-typing) | all |
| `touchpad-motion` | libinput plugin: jump detection on the Bluetooth touchpad's scan time; hwdb: 31 units/mm on both axes | all |
| `touchpad-accel` | Optional. Library preloaded into KWin that gives the keyboard touchpad Apple's trackpad acceleration (`/etc/zenbook-duo/touchpad-accel.conf` switches back to libinput's) | KDE Plasma 6.8 |
| `power-dtt` | `thermald --adaptive` with the BIOS's DTT tables | all |
| `power-profile-sync` | Maps power-profiles-daemon profiles onto asus-wmi, the SoC slider and the Xe GPU | all |
| `power-runtime-pm` | udev: runtime PM for PCI devices that ship without it | all |
| `power-tpm-rng` | udev: fTPM not used as a hardware RNG | all |
| `power-kbd-lid-wake` | systemd-sleep hook: the docked keyboard's USB wakeup is off while the lid is closed | all |
| `wifi-powersave-ac` | udev + NetworkManager dispatcher: Wi-Fi power save follows AC | all |
| `wifi-roam-deauth` | DKMS `mac80211` that deauthenticates from the AP it leaves when roaming with PMF, built from the running kernel's own sources (a pacman hook fetches them) | 7.x |
| `desktop-power-widget` | KDE panel widget: live power draw (RAPL psys, also on AC), charging rate, USB-C charger contract (udev helper), breakdown, temperatures, fans, power mode | KDE Plasma |
| `system-health` | pacman hook after kernel updates + one check per login; notifies only when a fix is not active | all |

`./duo list` marks modules that your running kernel doesn't need as "n/a".

</details>

<details>
<summary><b>🧊 If the desktop freezes</b></summary>

If the picture stops but the mouse or keyboard still respond, or a TTY still works (<kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F3</kbd>), capture the state before you reboot:

```sh
ps -eo etimes,stat,pid,wchan:24,cmd | awk 'NR==1 || $2 ~ /^D/'      # stuck (D-state) tasks
journalctl -k -b --no-pager | grep -E 'PSR idle state|DSB|FIFO underrun|Pageflip|controller timed out|bus ready|incomplete report' | tail -n 30
```

If you had to force a reboot, the previous boot's log still has it: `journalctl -b -1 -k`. Please open an issue with the output.

Known patterns:
- `Timed out waiting for PSR Idle for re-enable` or `pipe A] flip_done timed out`: a Panel Replay hang on the top screen, reported on 7.1/7.2 by other UX8407AA users. Fallback: add `xe.enable_panel_replay=0 xe.enable_psr=1` to the kernel command line.
- `PHY B failed`, `AUX B/DDI B/PHY B: timeout` or `pipe B] flip_done timed out`: the bottom-screen bug, see [above](#if-the-bottom-screen-stays-black).
- `DMC wakelock ack timed out` and `Unexpected DBuf power power state (0x00000000, expected 0x0000000f)`, then `flip_done timed out` on pipes A and B: both screens froze on the login screen of the first 7.3.0 boot, with the keyboard detached and the stock xe. It has not come back since; if you see it, please open an issue with `journalctl -b -1 -k`.

One freeze while pressing the brightness keys was seen on 7.2.9 and not reproduced since. The kernel kept logging through it, so the display stack hung, not the kernel. No PSR, DSB or I²C errors were logged.

</details>

<details>
<summary><b>⚙️ How it works (safety, revert, snapshots)</b></summary>

```
duo                     CLI (bash)
lib/common.sh           logging, kernel version compare (rc < final), DMI checks, module metadata
lib/actions.sh          recorded system changes + automatic revert
modules/<id>/
  module.conf           ID, NAME, SUMMARY, CATEGORY, SEVERITY, RISK, REBOOT, KERNEL_MIN/MAX, DEFAULT, UPSTREAM
  apply.sh              idempotent; only uses the lib/actions.sh helpers
  status.sh             0 = healthy, 1 = needs fix, 2 = not applicable
  files/ dkms/ src/     files to install, DKMS sources, sources to build
kernel/patches/         kernel patches for upstream submission
tools/check-hardware.sh the "is this repo for me?" check
tools/hw-scan.sh        repeatable hardware scan + health summary (`duo scan`, `duo doctor`)
tools/power-measure.sh  battery power, package power and S0ix residency (run unplugged)
hardware-scan/          ACPI tables (DSDT/SSDT .dat + .dsl) and the DTT data vault of this model
```

- **Every change is recorded:** `duo_install_file`, `duo_enable_unit`, `duo_enable_user_unit`, `duo_pkg_install`, `duo_cmdline_add` and `duo_dkms_install` write each action to `/var/lib/zenbook-duo/modules/<id>/manifest`. Existing files are backed up before they are replaced. `duo revert` replays the manifest backwards, so there are no hand-written uninstall scripts.
- **Snapshots:** with `snapper` installed, `apply` and `revert` take a snapshot first. On CachyOS, Limine lists these snapshots in the boot menu.
- **Kernel command line:** a marked block in `/etc/default/limine` (then `limine-update`) or in `/etc/default/grub` (then `grub-mkconfig`).
- **No patched distribution packages:** fixes are kernel parameters, DKMS modules, udev/hwdb rules, firmware in `/usr/lib/firmware/updates`, systemd units and small tools. Nothing replaces a file that a package owns, so system updates never fight this repo.

</details>

<details>
<summary><b>📮 Upstream status</b></summary>

| Item | Status |
|---|---|
| Ghost RT722 audio quirk | `ca02ffd4975c` in 7.3-rc1. A 7.2.y backport request together with the ExpertBook and Zephyrus Duo quirks is drafted in [asus-expertbook-linux](https://github.com/burakgon/asus-expertbook-linux/blob/main/upstream-patches/stable-request-7.2-ghost-rt722.txt). |
| CS35L56 OT25 DAI missing in 7.2.11 (no sound card) | `86c8360c97f6` [queued for 7.2.12](https://lore.kernel.org/all/2026-10-16-1-daily-reply-0008-cs35l56-ot25-dai-7-2@kernel.org/) on 2026-10-17, carried as DKMS in `audio-cs35l56-ot25` |
| `raydium_i2c_ts` leaves HID-over-I2C devices to `i2c-hid` | [`kernel/patches/0001`](kernel/patches/), to be submitted |
| VRR DC balance (DSB poll errors) | `c034e8a46e4c` in 7.3-rc6, `Cc: stable` ([`kernel/patches/0002`](kernel/patches/)) |
| Panel Replay Early Transport ghost cursor | to be reported to drm/xe |
| Bottom panel after a docked power-on (TCSS power for Port B) | [xe #9196](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9196); [RFC](https://lore.kernel.org/all/20261006-ptl-port-b-tcss-v1-1-240670342cd3@gmail.com/) on 2026-10-06, [v2](https://lore.kernel.org/all/20261015-ptl-port-b-tcss-v2-0-e00ce882402d@gmail.com/) to intel-gfx / intel-xe on 2026-10-15, carried as DKMS in `display-edp2-tcss` |
| `hid-asus` Zenbook Duo keyboard support (IDs, report length, hotkey descriptor, battery report filter) | to be submitted; 7.3 has none of it |
| mac80211: deauthenticate from the old AP when roaming with MFP | [sent to linux-wireless](https://lore.kernel.org/all/20261015-mac80211-roam-mfp-deauth-v1-1-9ccc69b434fd@gmail.com/) on 2026-10-15, carried as DKMS in `wifi-roam-deauth` |
| Keyboard touchpad palm rejection (libinput quirk) | to be submitted to libinput |
| Touchpad jump detection on `MSC_TIMESTAMP` (Bluetooth touchpads) | to be reported to libinput |
| Keyboard touchpad resolution (31 units/mm on both axes) | to be submitted to systemd `60-evdev.hwdb` |
| Custom touchpad acceleration curves in KWin | [KWin MR 6937](https://invent.kde.org/plasma/kwin/-/merge_requests/6937), planned for Plasma 6.9; `touchpad-accel` can then become settings |
| HDR (DisplayID 2.0 HDR metadata) | fixed in libdisplay-info 0.4.0; Arch packaging update pending |
| KDE: one backlight per built-in panel | KDE bug 525717 |
| KWin crashes when input-device settings are written over D-Bus during a screen change | to be reported to KDE |

</details>

## Kernel and distribution compatibility

| | 7.2.x | 7.3.x | 7.4+ |
|---|---|---|---|
| `audio-ghost-rt722` | DKMS, rebuilt on every kernel update | n/a (fixed upstream) | n/a |
| `audio-cs35l56-ot25` | DKMS on 7.2.11 only (fix queued for 7.2.12) | n/a (fixed upstream) | n/a |
| `keyboard-hid-asus` | DKMS (7.2 source) | DKMS (7.3 source) | needs a new source until upstream |
| `display-edp2-tcss` | DKMS (kernel's own source + patch) | DKMS | DKMS, as long as the patch applies |
| `wifi-roam-deauth` | DKMS (kernel's own source + patch) | DKMS | DKMS, as long as the patch applies |
| everything else | ✅ | ✅ | ✅ |

`./duo status` after a kernel update tells you whether every fix is still active.

Arch and Arch-based distributions (tested on CachyOS) get everything. On Debian, Ubuntu or Fedora, the config-only modules apply as they are (`touchscreen-hid`, `sensors-*`, `display-*`, `power-runtime-pm`, `power-tpm-rng`, `power-kbd-lid-wake`, `wifi-powersave-ac`, `power-profile-sync`, `touchpad-palm`, `touchpad-motion`). The modules that install packages call `pacman`, and the cmdline helper supports Limine and GRUB.

## FAQ

<details>
<summary><b>Do I have to rebuild the kernel?</b></summary>

No. Five modules use DKMS (`audio-ghost-rt722` on 7.2.x only, `audio-cs35l56-ot25` on 7.2.11 only, `keyboard-hid-asus`, `display-edp2-tcss`, `wifi-roam-deauth`), which rebuilds them automatically on kernel updates. `display-edp2-tcss` and `wifi-roam-deauth` build from the new kernel's own graphics driver or mac80211 sources (a few MB). pacman 7.1 runs the DKMS hook without network access, so each of the two installs a small pacman hook that may use the network and downloads the sources just before. Everything else is configuration.
</details>

<details>
<summary><b>How do I undo everything?</b></summary>

`sudo ./duo revert --all`, then reboot. Every file the repo installed is removed or restored from its backup. If you use snapper, there is also a snapshot from before each apply.
</details>

<details>
<summary><b>Why does the laptop draw ~3 W more with the keyboard docked?</b></summary>

The keyboard charges its own battery from the laptop through the pogo pins until it is full. The keyboard backlight costs less than 0.1 W. The same happens on Windows.
</details>

<details>
<summary><b>Why is there no HDR toggle?</b></summary>

The panel supports HDR (PQ, BT.2020, 1060 nits peak), but it puts that information in a CTA-861 block inside a DisplayID 2.0 extension, which libdisplay-info 0.3.0 doesn't read. 0.4.0 does. When your distribution ships it, the toggle appears. `display-dsc-10bit` already provides the 10 bpc that HDR needs.
</details>

<details>
<summary><b>Should I enable VRR?</b></summary>

Not on Panther Lake eDP yet: it gets stuck at the minimum refresh rate and causes DSB errors (xe #8976, #9253, #9296). Keep KDE's Adaptive Sync at *Never*. Thanks to Panel Replay, a static screen costs the same at 144 Hz as at 60 Hz.
</details>

<details>
<summary><b>I use GNOME. Does this help?</b></summary>

Everything except `desktop-kde-duo` is desktop-independent. Rotation and dual-screen layout on GNOME would need a separate tool; contributions welcome.
</details>

<details>
<summary><b>Is it safe?</b></summary>

Each module is small and recorded, and `./duo revert` undoes it. The riskiest pieces are the two DKMS drivers; if one fails to build, the stock driver loads and you lose only that fix.
</details>

## Contributing

Reports and measurements from other UX8407AA units are very welcome. `./duo scan` produces a redacted snapshot you can attach. Before you change a module, check that `./duo apply`, `./duo status` and `./duo revert` still behave.

## Acknowledgements

- Charles Keepax (Cirrus Logic) for the ghost-RT722 SoundWire quirk for this model.
- [asus-expertbook-linux](https://github.com/burakgon/asus-expertbook-linux), the sister project for the ExpertBook Ultra on the same platform: the power-profiles-daemon snap-back fix and the freeze runbook come from there.
- [Omarchy](https://github.com/basecamp/omarchy) for its Panther Lake hardware notes.
- [zenbook-duo-omarchy](https://github.com/scrambletools/zenbook-duo-omarchy) and [zenbook-duo26-Ubuntu26.04](https://github.com/therealarnold666/zenbook-duo26-Ubuntu26.04), the Omarchy and Ubuntu projects for the same laptop: their bottom-screen (eDP-2) investigations, recovery recipe and Panel Replay findings. Do not install them together with this repo: they drive the same displays.

## License

GPL-2.0-only (see [LICENSE](LICENSE)). The DKMS sources are derived from the Linux kernel and keep their original copyright notices. The ACPI tables in `hardware-scan/` are dumped from the firmware for reference.
