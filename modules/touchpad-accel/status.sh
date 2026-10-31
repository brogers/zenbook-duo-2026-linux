# shellcheck shell=bash
# Exit status: 0 = healthy, 1 = needs fix.

lib=/usr/lib/libzenbook-duo-touchpad-accel.so
dropin=/etc/systemd/user/plasma-kwin_wayland.service.d/60-zenbook-duo-touchpad-accel.conf
if [[ ! -f $lib || ! -f $dropin ]]; then
	warn "keyboard touchpad: libinput's acceleration (fast when slow, slow when fast)"
	return 1
fi
if [[ ! -u $lib ]]; then
	warn "$lib lacks the set-user-ID bit, so KWin cannot preload it (re-apply touchpad-accel)"
	return 1
fi
curve="$(sed -n 's/^curve=//p' /etc/zenbook-duo/touchpad-accel.conf 2>/dev/null)"
state=loaded
for pid in $(pgrep -x kwin_wayland); do
	# kwin_wayland is not dumpable (file capability): only root reads its maps
	grep -q "$lib" "/proc/$pid/maps" 2>/dev/null
	case $? in
	1) state=missing ;;
	2) state=unknown ;;
	esac
done
case $state in
missing) info "installed; KWin picks it up at the next login" ;;
unknown) info "installed; run as root to see whether KWin loaded it" ;;
*) ok "keyboard touchpad: ${curve:-apple} acceleration" ;;
esac
return 0
