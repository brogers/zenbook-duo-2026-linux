# shellcheck shell=bash
# 0 = bottom panel runs as eDP with Panel Replay and LOBF off, 1 = not (yet), 3 = panel
# missing this boot (booted with the keyboard docked).

missing=()
for p in xe.vbt_firmware=zenbook-duo/zephyrus-vbt-tc1-edp.bin xe.enable_psr=0 xe.enable_panel_replay=0; do
	grep -qw -- "$p" /proc/cmdline || missing+=("$p")
done
if ((${#missing[@]})); then
	if [[ -f /usr/lib/firmware/zenbook-duo/zephyrus-vbt-tc1-edp.bin ]]; then
		info "edited VBT installed; reboot pending (cmdline lacks: ${missing[*]})"
	elif grep -q 'xe\.vbt_firmware=' /proc/cmdline; then
		info "a VBT from elsewhere is loaded; apply this module to take it over"
	else
		warn "bottom panel driven as DisplayPort (stock VBT): modesets and reboots can hang"
	fi
	return 1
fi

conn=""
# the bottom panel is xe's eDP on TC1 (in hybrid mode xe also has the top one, on port A)
for c in /sys/class/drm/card*-eDP-*; do
	[[ $(basename "$(readlink -f "$c/device/device/driver")") == xe ]] || continue
	[[ $(cat "$c"/drm_dp_aux*/name 2>/dev/null) == *TC1* ]] && { conn="${c##*/}"; break; }
done
if [[ -z $conn ]]; then
	warn "no bottom panel this boot: it was powered off at boot (keyboard docked); reboot with the keyboard lifted"
	return 3
fi
if ! journalctl -b -t zenbook-duo-lobf --no-pager -q -o cat 2>/dev/null | grep -q "LOBF off on ${conn#card*-}"; then
	warn "LOBF not turned off on ${conn#card*-} in this boot (see: journalctl -b -t zenbook-duo-lobf)"
	return 1
fi
if klog | grep -qE 'vblank wait timed out|flip_done timed out'; then
	warn "edited VBT active, but a display pipe hung in this boot (see journalctl -k -b)"
	return 1
fi
pad=/sys/class/backlight/asus_screenpad
if [[ -r $pad/brightness && $(<"$pad/brightness") != "$(<"$pad/max_brightness")" ]]; then
	warn "asus_screenpad at $(<"$pad/brightness")/$(<"$pad/max_brightness"): the bottom panel is dimmer than its backlight says"
	return 1
fi
ok "bottom panel is ${conn#card*-} (eDP on TC1), Panel Replay and LOBF off"
return 0
