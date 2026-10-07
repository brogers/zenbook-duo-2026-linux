# touchpad-palm

Turns on palm rejection and disable-while-typing for the keyboard's touchpad, docked and on Bluetooth.

## The problem
- Resting a palm on the touchpad while typing moves the cursor and clicks.
- The touchpad reaches the laptop over USB pogo pins when the keyboard is docked (`0b05:1cd7`) and over Bluetooth when it is detached (`0b05:1cd8`). systemd's `65-integration.rules` marks both as external, and libinput only runs disable-while-typing and palm detection on internal touchpads: `libinput list-devices` shows `Disable-w-typing: n/a`, and the touchpad's own palm flag (`ABS_MT_TOOL_TYPE` = `MT_TOOL_PALM`) is ignored too.

## What it changes
- Adds a section to `/etc/libinput/local-overrides.quirks` (the file is created if missing; anything else in it is kept) that marks the touchpad as the lower half of a touchpad+keyboard combo (`AttrTPKComboLayout=below`), for both product IDs.
- With that, libinput pairs the touchpad with the keyboard of the same device and turns on:
  - disable-while-typing (touches that start while you type are ignored for a moment; it can be switched off in System Settings → Touchpad),
  - palm zones along the left, right and top edges,
  - the touchpad's own palm reports.
- The touchpad and keyboard stay "external" otherwise, so closing the lid does not disable the touchpad or count key presses as an open lid. That matters when the keyboard is detached and the laptop is closed with an external monitor.
- Applies to every libinput user (KWin, GNOME, the X11 libinput driver). It takes effect at the next login, when the compositor starts libinput.

## Check
```sh
./duo status touchpad-palm
sudo libinput list-devices | grep -A20 'Zenbook Duo Keyboard Touchpad' | grep Disable-w-typing   # enabled
```

## Undo
`sudo ./duo revert touchpad-palm`, then log out and back in. The file is restored to what it was before the module was applied (or removed if it did not exist).

## Notes
- libinput's ROG Flow Z13 quirk marks a detachable USB keyboard as internal instead. That would also pair the Bluetooth keyboard with the lid switch, so a key press with the laptop closed would report the lid as open. The combo layout avoids that.
- Upstream: a candidate for libinput's `quirks/50-system-asus.quirks`.
