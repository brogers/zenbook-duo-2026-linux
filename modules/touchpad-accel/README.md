# touchpad-accel

Gives the keyboard touchpad Apple's trackpad acceleration: pixel-precise when you move slowly, across the screen with a short flick. Docked and on Bluetooth.

## The problem
- libinput's touchpad curve rises from 0.3 to 0.9 between 0 and 7 mm/s, stays flat up to 130 mm/s, then climbs steeply. Measured on this touchpad with KDE's speed at 0.2, the cursor moved (screen mm per finger mm):

  | finger speed | libinput | macOS |
  |---|---|---|
  | 3–10 mm/s (fine aiming) | 2.0–3.0 | 0.8–1.1 |
  | 50 mm/s | 3.0 | 2.7 |
  | 130 mm/s | 3.0 | 5.9 |
  | 300 mm/s | 6.3 | 10.9 |

  Too fast when aiming, too slow for medium moves. Half of all motion frames in a recording of normal use were under 30 mm/s.
- KWin 6.8 offers only libinput's flat and adaptive profiles. Custom curves are planned for Plasma 6.9 ([KWin MR 6937](https://invent.kde.org/plasma/kwin/-/merge_requests/6937)).
- libinput's custom profile would not be enough anyway: it measures speed from one event's arrival time, so on Bluetooth (two reports 0.5 ms apart every ~130 ms) the speed jumps 10–15× on those events and the cursor lurches.

## What it changes
- Builds `/usr/lib/libzenbook-duo-touchpad-accel.so` and loads it into KWin with a drop-in for `plasma-kwin_wayland.service` (`LD_PRELOAD`).
  - The library has the set-user-ID bit. `kwin_wayland` has the file capability `CAP_SYS_NICE`, so the dynamic loader runs it in secure-execution mode and preloads only bare names from `/usr/lib` that have this bit (ld.so(8)). The bit gives a library no privileges.
  - It replaces only `libinput_event_pointer_get_dx()`/`_get_dy()` for the keyboard touchpad (`0b05:1cd7`, `0b05:1cd8`). Every other device and every other libinput call passes through untouched. Scrolling, taps, gestures, palm detection and disable-while-typing stay libinput's.
  - `LD_PRELOAD` ends at `kwin_wayland` (the loader clears it in secure-execution mode, the library removes itself otherwise), so Xwayland and other programs KWin starts never load it.
- The curve is Apple's, from IOHIDFamily's `IOHIDParametricAcceleration` with the Magic Trackpad 2 `HIDAccelCurves` table: a finger speed of v inches/s moves the pointer 96·f(v) points/s, one point taken as 0.2 mm (its size on a MacBook).
- Speed is measured per event like macOS: an event that arrives within 1.5 scan periods counts as one scan (7.1 ms) of motion, so Bluetooth bunching does not matter; the first event after a pause counts as slow, so a landing finger does not throw the pointer. Against the touchpad's own scan time, 90% of gains are within ±13%, docked and on Bluetooth.
- KDE's touchpad speed slider picks Apple's tracking speed: −1 → 0, 0 → 1 (macOS default), +1 → 3. −0.3 (tracking speed 0.7) covers the same distance as libinput at 0.2 did, with 2.8× finer control when moving slowly.
- `/etc/zenbook-duo/touchpad-accel.conf`: `curve=apple` or `curve=libinput` (stock, for comparison) and the pixel size of the top panel; changes apply within a second.
- Choosing *Flat* acceleration in KDE's touchpad settings also gives libinput's behaviour back.

## Check
```sh
sudo ./duo status touchpad-accel   # only root can read kwin_wayland's memory map
journalctl --user -b -u plasma-kwin_wayland | grep touchpad-accel   # "Apple acceleration for … tracking speed 0.700" after the first touchpad motion
```

## Undo
`sudo ./duo revert touchpad-accel`, then log out and back in. If KWin does not start after a login, switch to a text console (Ctrl+Alt+F3), log in and run `sudo ./duo revert touchpad-accel`.

## Notes
- Any user can preload a set-user-ID library into privileged programs. This one does nothing there: it acts only inside libinput's pointer motion calls.
- Assumption: Apple standardises the curve to 67 Hz frames (`FRAME_RATE`, `kCursorScale = 96/67`). If macOS trackpads deliver pointer events faster than that, macOS accelerates somewhat less at high speed than this; the slider covers the difference.
- Sources: [IOHIDFamily](https://github.com/apple-oss-distributions/IOHIDFamily) `IOHIDAccelerationAlgorithm.cpp` and `IOHIDAcceleration.cpp`; Apple's curve table as carried in [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C)'s `Info.plist` (Custom MT2 Personality).
- When Plasma 6.9 ships custom curves, this can become kcminputrc settings plus a fix in libinput's custom-profile speed measurement.
