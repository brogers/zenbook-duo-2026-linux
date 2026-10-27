# shellcheck shell=bash
# 0 = the firmware's dock/lift KEY_WLAN is remapped away, 1 = Wi-Fi still toggles.

dev=""
for n in /sys/class/input/event*/device/name; do
	[[ $(<"$n") == "Asus WMI hotkeys" ]] && { dev="/dev/input/$(basename "$(dirname "$(dirname "$n")")")"; break; }
done
if [[ -z $dev ]]; then
	warn "no \"Asus WMI hotkeys\" input device (asus-nb-wmi not loaded?)"
	return 1
fi
if ! udevadm info "$dev" 2>/dev/null | grep -qx 'E: KEYBOARD_KEY_5e=reserved'; then
	warn "docking or lifting the keyboard toggles Wi-Fi (KEY_WLAN from $dev)"
	return 1
fi
ok "docking and lifting the keyboard leave Wi-Fi alone"
return 0
