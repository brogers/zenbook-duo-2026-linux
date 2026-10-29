# touchpad-motion

Stops libinput from throwing away the keyboard touchpad's motion on Bluetooth, and makes up/down move as fast as left/right.

## The problem
- **Bluetooth: lost motion.** The touchpad scans every 7.1 ms (141 Hz), the Bluetooth LE link has a connection event every 7.5 ms (the shortest LE allows). About every 130 ms two reports leave in the same connection event and reach the host 0.4–0.8 ms apart.
  - libinput's jump detection divides the distance moved by that arrival gap and sees 10–40 mm per 12 ms frame, far above its 20 mm limit. It logs `kernel bug: Touch jump detected and discarded` (five times a day, then the log is rate-limited) and drops the motion.
  - Measured with `libinput record` while moving the cursor: 43 discards in 30 s, ~2 mm of finger travel each (up to 4.5 mm), 4.3% of all motion. Each one is a hitch: the cursor stalls for a frame and lands short.
  - Every report carries the touchpad's own scan time (HID *Scan Time*, `MSC_TIMESTAMP`): consecutive reports are 7.1 ms apart however they arrive. Windows uses it, libinput does not (it drops `MSC_TIMESTAMP` on all but a few Dell touchpads).
  - Docked (USB, 1 ms polling) reports arrive on time; libinput's jump detection found nothing in 7 minutes of use.
- **Both: slower up/down.** The HID descriptor gives 124.2 × 75.6 mm for 3911 × 2382 units, 31.5 units/mm on both axes. The kernel rounds each axis on its own, to 31 (x) and 32 (y), so the same finger travel moved the cursor 3% less up/down than left/right, and circles came out as ellipses.

## What it changes
- `/etc/libinput/plugins/50-zenbook-duo-touchpad-bt-jumps.lua`, a [libinput plugin](https://wayland.freedesktop.org/libinput/doc/latest/lua-plugins.html) for the Bluetooth touchpad (`0b05:1cd8`) only:
  - turns libinput's jump detection off for that device (`disable_feature("touchpad-jump-detection")`, which exists for devices where it misfires),
  - runs the same test (more than 20 mm in a 12 ms frame, or 7 mm more than the frame before) on the scan time instead, and discards a real jump the way libinput does.
  - KWin (Plasma 6.8) loads libinput plugins; any other libinput user that loads plugins gets the same.
- `/etc/udev/hwdb.d/61-zenbook-duo-touchpad.hwdb`: 31 units/mm on the y axes as well (`EVDEV_ABS_01`, `EVDEV_ABS_36`), docked and on Bluetooth.
- Both take effect at the next login. The axis fix also needs the touchpad to be re-added (log in again after a reboot, or detach and dock the keyboard).

## Check
```sh
./duo status touchpad-motion
sudo libinput debug-events --enable-plugins --verbose --device /dev/input/eventN 2>&1 | grep 'scan time'   # Bluetooth touchpad
```

## Undo
`sudo ./duo revert touchpad-motion`, then log out and back in. The kernel keeps the corrected y resolution until the touchpad is re-added.

## Notes
- Verified by replaying the Bluetooth recording into a virtual device with and without the plugin: 0 instead of 47 discards, 1789 mm of finger travel delivered instead of 1715 mm, no real jumps on the scan time.
- Upstream:
  - libinput: jump detection should use `MSC_TIMESTAMP` where the device has it. Found on the way: `tp_process_msc()` returns early for `MSC_TIMESTAMP` instead of for everything else, so the Dell `AttrMscTimestamp=watch` jump fix never runs; `--set-plugin-path` of the tools adds the default paths instead of the given one; the plugin API's `usages()` skips the highest code of every event type.
  - systemd: the resolution entry belongs in `hwdb.d/60-evdev.hwdb`.
