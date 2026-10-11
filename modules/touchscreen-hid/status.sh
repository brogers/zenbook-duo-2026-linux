# shellcheck shell=bash
# Exit status: 0 = healthy, 1 = needs fix.

rc=0
drv="$(basename "$(readlink /sys/bus/i2c/devices/i2c-RAYD0001:00/driver 2>/dev/null)" 2>/dev/null)"
inputs="$(grep -c 'RAYD0001' /proc/bus/input/devices)"
case "$drv" in
i2c_hid_acpi)
	ok "RAYD0001 bound to i2c_hid_acpi (${inputs} input nodes)"
	;;
raydium_ts)
	warn "RAYD0001 bound to raydium_ts (wrong protocol, touch/pen unusable)"
	[[ -f /etc/modprobe.d/zenbook-duo-touchscreen.conf ]] && info "fix installed, reboot pending"
	return 1
	;;
*)
	warn "RAYD0001 driver: ${drv:-none}"
	return 1
	;;
esac
nodes=0 calibrated=0
for e in /sys/class/input/event*; do
	[[ "$(cat "$e/device/name" 2>/dev/null)" == "RAYD0001:00 2386:8C05"* ]] || continue
	nodes=$((nodes + 1))
	udevadm info -q property "$e" 2>/dev/null | grep -qx 'LIBINPUT_CALIBRATION_MATRIX=-1 0 1 0 -1 1' && calibrated=$((calibrated + 1))
done
if ((nodes && calibrated == nodes)); then
	ok "top touch and pen rotated back 180 degrees (libinput calibration)"
else
	warn "top touch/pen calibration missing on $((nodes - calibrated)) of ${nodes} devices: touches land mirrored"
	[[ -f /etc/udev/rules.d/61-zenbook-duo-touchscreen.rules ]] && info "rule installed, reboot pending"
	rc=1
fi
return $rc
