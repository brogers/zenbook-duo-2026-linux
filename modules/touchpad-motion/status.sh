# shellcheck shell=bash
# Exit status: 0 = healthy, 1 = needs fix.

rc=0
if [[ -f /etc/libinput/plugins/50-zenbook-duo-touchpad-bt-jumps.lua ]]; then
	ok "Bluetooth touchpad: jump detection on the touchpad's scan time"
else
	warn "Bluetooth touchpad: libinput throws away motion as pointer jumps"
	rc=1
fi
for d in /sys/class/input/event*; do
	[[ "$(cat "$d/device/id/vendor" 2>/dev/null)" == 0b05 ]] || continue
	[[ "$(cat "$d/device/id/product" 2>/dev/null)" == 1cd[78] ]] || continue
	udevadm info -q property "$d" | grep -qx 'ID_INPUT_TOUCHPAD=1' || continue
	if udevadm info -q property "$d" | grep -qx 'EVDEV_ABS_36=::31'; then
		ok "$(cat "$d/device/name"): both axes at 31 units/mm"
	else
		warn "$(cat "$d/device/name"): up/down moves 3% slower than left/right"
		rc=1
	fi
done
return "$rc"
