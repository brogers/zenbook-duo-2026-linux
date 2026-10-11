# touchscreen-hid

Makes touch and pen work on the top screen, under the finger.

## The problem
- Touch and pen on the top screen are completely dead. libinput rejects the device (`kernel bug: device has min == max on ABS_X`), and in one boot the kernel crashed with an Oops in `raydium_i2c_irq`.
- The top touchscreen (ACPI `RAYD0001`, `_CID PNP0C50`) speaks the standard HID-over-I2C protocol, but the `raydium_i2c_ts` driver claims it by its ACPI ID and cannot drive it.
- The top panel is mounted upside down but its digitizer is not, so touch and pen coordinates are turned 180 degrees from the panel's own frame: touches land mirrored through the centre of the screen.
- The bottom touchscreen (`RAYD0002`) is not affected.

## What it changes
- Installs `/etc/modprobe.d/zenbook-duo-touchscreen.conf`, which contains `blacklist raydium_i2c_ts` and `install raydium_i2c_ts /bin/false`. With that driver kept away, `i2c_hid_acpi` + `hid-multitouch` bind the top touchscreen instead.
- Installs `/etc/udev/rules.d/61-zenbook-duo-touchscreen.rules`, which gives the top touchscreen and pen the libinput calibration matrix `-1 0 1 0 -1 1` (a 180-degree turn) as their default. It works in every desktop, and KWin keeps it through rotations and screen changes.
- A reboot is required.

## Check
```sh
./duo status touchscreen-hid
readlink /sys/bus/i2c/devices/i2c-RAYD0001:00/driver   # should end in i2c_hid_acpi
sudo libinput list-devices | grep -A20 'RAYD0001' | grep Calibration   # -1.00 0.00 1.00 0.00 -1.00 1.00
```

## Undo
`sudo ./duo revert touchscreen-hid`, then reboot.

## Notes
- Works on all kernels.
- Upstream: a kernel patch (`Input: raydium_i2c_ts: skip HID-over-I2C devices`) is in `kernel/patches/`, not yet submitted.
- Rotation and touch-to-screen mapping are handled by `sensors-accel-mount` and `desktop-kde-duo`.
- A first attempt at this calibration, as a KWin `CalibrationMatrix` in `kcminputrc`, had the offsets in the wrong column of KWin's 4x4 matrix and collapsed every touch onto one point; earlier versions of `desktop-kde-duo` used KWin's per-device touch orientation instead, which KWin resets on every screen change.
