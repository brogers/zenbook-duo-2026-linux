# shellcheck shell=bash
# The loaded hid-asus is the patched one when it is out of tree (taint O); when it is
# not loaded, look at what would load. modinfo alone fails once a kernel update has
# removed the running kernel's modules.
if [[ -d /sys/module/hid_asus ]]; then
	[[ $(</sys/module/hid_asus/taint) == *O* ]]
else
	modinfo -n hid_asus 2>/dev/null | grep -q updates/dkms
fi || {
	warn "stock hid-asus in use (backlight writes time out, no Fn keys)"
	return 1
}
if klog | grep -q "Asus failed to set keyboard backlight"; then
	warn "backlight write errors in this boot (reboot after install if they predate it)"
fi
for b in /sys/class/power_supply/asus-keyboard-*-battery; do
	[[ -e $b ]] && info "keyboard battery (Bluetooth): $(<"$b/capacity")%"
done
[[ -e /sys/class/leds/asus::kbd_backlight ]] && ok "patched hid-asus active, kbd backlight $(cat /sys/class/leds/asus::kbd_backlight/brightness)/3" && return 0
ls /sys/bus/hid/devices/ | grep -q -E "0B05:1CD[78]" || { info "keyboard not attached"; return 0; }
return 1
