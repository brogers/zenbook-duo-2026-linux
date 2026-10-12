# shellcheck shell=bash
# Same detection as files/zenbook-duo-wifi-ps: any online Mains supply, every wireless interface.
ac=0
for s in /sys/class/power_supply/*; do
	[[ $(cat "$s/type" 2>/dev/null) == Mains && $(cat "$s/online" 2>/dev/null) == 1 ]] && ac=1
done
[[ $ac == 1 ]] && want=off || want=on
rc=0 found=0
for d in /sys/class/net/*/wireless; do
	[[ -e $d ]] || continue
	dev="$(basename "$(dirname "$d")")"; found=1
	ps="$(iw dev "$dev" get power_save 2>/dev/null | awk '{print $3}')"
	if [[ $ps == "$want" ]]; then ok "$dev: Wi-Fi power save $ps (AC=$ac)"; else warn "$dev: Wi-Fi power save ${ps:-unknown} while AC=$ac"; rc=1; fi
done
[[ $found == 1 ]] || { warn "no Wi-Fi interface found"; rc=1; }
return $rc
