# power-profile-sync

Makes the "Power Save" profile really save power (quiet fans, low-power SoC, GPU power saving) and makes every profile switch stick.

## The problem
- Choosing "Power Save" in KDE leaves the firmware in balanced: no quiet fan mode and no Windows "Whisper" power limits, only a different CPU energy preference.
- The kernel's combined `platform_profile` only offers choices that every handler shares. `asus-wmi` calls its low-power mode `quiet`, the Intel SoC Power Slider calls it `low-power`, so neither survives and power-profiles-daemon cannot select them.
- Switching straight from Performance to Power Save snaps back to Balanced within a second: power-profiles-daemon emulates power-saver by writing "balanced" and then reads its own write back as a profile change.
- power-profiles-daemon does not manage the Xe GPU's power profile at all.

## What it changes
- Installs `/usr/lib/zenbook-duo/zenbook-duo-profile-sync` and `/etc/systemd/system/zenbook-duo-profile-sync.service`, then enables and starts the service. It watches the active profile over D-Bus and re-applies after every resume (no periodic wakeups), and writes:
  - power-saver: `asus-wmi` = `quiet`, SoC slider = `low-power`, Xe GPU `power_profile` = `power_saving`
  - balanced / performance: both handlers = the same name, Xe GPU = `base`
- Installs the drop-in `/etc/systemd/system/power-profiles-daemon.service.d/50-zenbook-duo-block-platform-profile.conf`, which starts power-profiles-daemon with `--block-driver=platform_profile`. Apply stops with an error if another drop-in already sets `ExecStart`.
- Restarts `power-profiles-daemon` and restores the profile that was active. No reboot is needed.

## Check
```sh
./duo status power-profile-sync
powerprofilesctl get; grep . /sys/class/platform-profile/*/profile
```

## Undo
`sudo ./duo revert power-profile-sync`. The drop-in is removed and `power-profiles-daemon` restarts without it.

## Notes
- Works on all kernels. Requires power-profiles-daemon.
- Use it together with `power-dtt`: thermald applies the Whisper limits (PL1 20-30 W, PL2 35 W) once the firmware is in quiet mode.
- Also applies to the ROG Zephyrus Duo GX651AX, which has the same two handlers. There it needs no `power-dtt`: the SoC slider's `low-power` caps the CPU by itself, and asus-wmi's `quiet` only slows the fans. Measured on 2026-10-28 on battery, all cores loaded, 30 s in (past the turbo burst; RAPL PL1/PL2 read 75/80 W in every profile):

  | asus-wmi | SoC slider | CPU package | clock | temp | fan |
  |---|---|---|---|---|---|
  | performance | performance | 59.5 W | 3654 MHz | 87 C | 5100 rpm |
  | balanced | balanced | 43.1 W | 3278 MHz | 75 C | 3400 rpm |
  | quiet | low-power | 29.7 W | 2825 MHz | 66 C | 2800 rpm |
  | quiet | balanced | 43.9 W | 3268 MHz | 77 C | 2900 rpm |
  | balanced | low-power | 29.7 W | 2820 MHz | 66 C | 2700 rpm |

  At idle the profiles draw the same (about 12 W from the battery, both panels on).
- On the GX651AX, apply `power-zephyrus-asusd` too, or asusd switches the profile on every plug and unplug.
