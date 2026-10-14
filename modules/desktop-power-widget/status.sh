# shellcheck shell=bash
rc=0
if [[ -f /usr/lib/qt6/qml/org/zenbookduo/power/libzenbookduopowerplugin.so && -f /usr/share/plasma/plasmoids/org.zenbookduo.power/metadata.json ]]; then
	ok "widget installed (add \"Zenbook Duo Power\" to a panel)"
else
	warn "widget not installed"; rc=1
fi
if [[ -r /sys/class/powercap/intel-rapl:1/energy_uj && -r /sys/class/powercap/intel-rapl:0/energy_uj ]]; then
	ok "energy counters readable: whole-laptop draw (psys) and breakdown available"
else
	warn "energy counters not readable for $(id -un): no whole-laptop draw on AC, no breakdown (needs the wheel group and the udev rule)"; rc=1
fi
charger=/run/zenbook-duo/charger
if [[ -r $charger ]]; then
	w="$(sed -n 's/^watts=//p' $charger)"
	if [[ ${w:-0} == 0 ]]; then
		ok "charger helper works (no USB-C charger plugged in)"
	else
		ok "charger: $w W ($(sed -n 's/^volts=//p' $charger) V, $(sed -n 's/^amps=//p' $charger) A)$(grep -qx 'slow=1' $charger && echo ', reported as a slow charger')"
	fi
else
	warn "no $charger: the widget cannot tell how much the charger can give"; rc=1
fi
state="$HOME/.local/state/zenbook-duo/power-widget.ini"
if [[ -r $state ]]; then
	info "psys scale $(sed -n 's/^scale=//p' "$state"), refined over $(sed -n 's/^calibrations=//p' "$state") windows on battery"
else
	info "psys scale: built-in value (the widget refines it whenever it runs on battery)"
fi
return $rc
