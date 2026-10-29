# power-zephyrus-asusd

On the **ASUS ROG Zephyrus Duo 2026 (GX651AX)**, asusd stops changing the power profile and the CPU energy preference on its own, so the profile Omarchy picks for AC or battery is the one that runs. Only applies to the GX651AX.

## The problem
- Omarchy sets the power profile through power-profiles-daemon whenever the charger is plugged in or out, and power-profiles-daemon sets the CPU energy performance preference (EPP) to match.
- asusd does the same jobs by default: `ChangePlatformProfileOnAc` and `ChangePlatformProfileOnBattery` switch the platform profile on every plug and unplug, and `PlatformProfileLinkedEpp` rewrites the EPP from asusd's own table after every profile change, whoever made it. The two race, and asusd's EPP can replace the one power-profiles-daemon chose.
- On this machine asusd's switch also fails: it asks for `Quiet`, which the combined `platform_profile` does not offer (asus-wmi says `quiet`, the SoC Power Slider says `low-power`), and logs `Failed to set platform profile Quiet on AC/BAT change: ... Operation not supported`.

## What it changes
- `/etc/systemd/system/asusd.service.d/10-zenbook-duo-power-profiles.conf` sets those three asusd settings to false over D-Bus whenever asusd starts. Everything else asusd does is unchanged.
- Sets them to false on the running asusd as well, so no restart or reboot is needed. asusd saves them in `/etc/asusd/asusd.ron`.
- The same fix as omacom/omarchy#15667 (from omarchy-asus's `asus/asusd-power-profiles`); drop this module once Omarchy ships it.

## Check
```sh
./duo status power-zephyrus-asusd
journalctl -b -u asusd | grep 'AC/BAT change'      # nothing after a plug or unplug
powerprofilesctl get; cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
```

## Undo
`sudo ./duo revert power-zephyrus-asusd`. The three settings get back the values they had before apply, the drop-in is removed and asusd restarts.
