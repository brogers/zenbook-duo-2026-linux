# wifi-zephyrus-dock-toggle

On the **ASUS ROG Zephyrus Duo 2026 (GX651AX)**, docking the keyboard on the bottom screen or lifting it off no longer turns Wi-Fi off or on. Only applies to the GX651AX.

## The problem
- Whenever the keyboard docks or lifts, the firmware sends `KEY_WLAN` (scan code `0x5e`) on the "Asus WMI hotkeys" input device.
- The kernel's rfkill input handler (`CONFIG_RFKILL_INPUT=y`) toggles every Wi-Fi radio on that key; NetworkManager reports `Wi-Fi now disabled by radio killswitch`.
- Booted with the keyboard lifted, docking turns Wi-Fi off and lifting turns it back on; booted docked, it is the other way round, so Wi-Fi is off whenever the keyboard is lifted.
- The keyboard has no wireless or airplane-mode key, so nothing else sends this code.

## What it changes
- `/etc/udev/hwdb.d/90-zenbook-duo-zephyrus-wlan-key.hwdb` maps scan code `0x5e` of "Asus WMI hotkeys" to `reserved` (no key), only on a GX651AX board. The hwdb is updated and the input devices re-triggered right away; no reboot.
- Removes `/etc/udev/hwdb.d/90-zephyrus-duo-wlan-key.hwdb`, the same remap installed by hand earlier.

## Check
```sh
./duo status wifi-zephyrus-dock-toggle
journalctl -b | grep 'radio killswitch'          # nothing after a dock or lift
```

## Undo
`sudo ./duo revert wifi-zephyrus-dock-toggle`. Takes effect right away.

## Notes
- Verified on 2026-10-27 (BIOS GX651AX.310): with the remap, a dock and a lift leave Wi-Fi connected; without it each one toggled the kill switch.
