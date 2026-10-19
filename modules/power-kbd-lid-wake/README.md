# power-kbd-lid-wake

Keeps the laptop asleep when the lid is closed over the docked keyboard.

## The problem
- Docked on the bottom screen, the keyboard is a USB device (`0b05:1cd7`) with remote wakeup enabled.
- With the lid closed it keeps waking the laptop from s2idle. KDE puts the laptop back to sleep about 10 s later, and the keyboard wakes it again 10–60 s after that.
- Seen in two boots: 134 suspend cycles in one hour, and 18 in ten minutes. The keyboard's own wakeup counter (`power/wakeup_count`) was at 30 in the second boot.
- In a bag the battery drains and the laptop warms up.

## What it changes
- Installs the systemd-sleep hook `/usr/lib/systemd/system-sleep/zenbook-duo-kbd-lid-wake`.
- Before a suspend with the lid closed, the hook turns the docked keyboard's USB wakeup off. After resume it turns it back on.
- With the lid open, a key press still wakes the laptop. Opening the lid always wakes it.

## Check
```sh
./duo status power-kbd-lid-wake
journalctl -b | grep -E "Lid closed|Lid opened|Performing sleep operation 'suspend'"   # one suspend per lid close
cat /sys/bus/usb/devices/*/power/wakeup_count   # the keyboard's counter stays put while the lid is closed
```

## Undo
`sudo ./duo revert power-kbd-lid-wake`
