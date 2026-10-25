# shellcheck shell=bash
# 0 = hook installed, 1 = missing.

hook=/usr/lib/systemd/system-sleep/zenbook-duo-kbd-lid-wake
if [[ ! -x $hook ]]; then
	warn "sleep hook missing: $hook"
	return 1
fi
ok "the docked keyboard cannot wake the laptop while the lid is closed"
return 0
