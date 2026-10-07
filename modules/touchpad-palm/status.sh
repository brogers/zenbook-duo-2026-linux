# shellcheck shell=bash
# Exit status: 0 = healthy, 1 = needs fix.

if ! grep -qx 'AttrTPKComboLayout=below' /etc/libinput/local-overrides.quirks 2>/dev/null; then
	warn "keyboard touchpad counts as external: no palm rejection, no disable-while-typing"
	return 1
fi
for d in /sys/class/input/event*; do
	[[ "$(cat "$d/device/id/vendor" 2>/dev/null)" == 0b05 ]] || continue
	[[ "$(cat "$d/device/id/product" 2>/dev/null)" == 1cd[78] ]] || continue
	udevadm info -q property "$d" | grep -qx 'ID_INPUT_TOUCHPAD=1' || continue
	if ((EUID == 0)) && ! libinput quirks list "/dev/${d#/sys/class/}" 2>/dev/null | grep -qx 'AttrTPKComboLayout=below'; then
		warn "quirk installed but libinput does not apply it to $(cat "$d/device/name")"
		return 1
	fi
	ok "$(cat "$d/device/name"): palm rejection and disable-while-typing"
	return 0
done
ok "quirk installed (keyboard touchpad not connected right now)"
return 0
