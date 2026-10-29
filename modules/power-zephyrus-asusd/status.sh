# shellcheck shell=bash
# 0 = asusd leaves the platform profile and EPP alone, 1 = it still switches them.

if ! systemctl is-active --quiet asusd.service; then
	info "asusd is not running"
	return 3
fi
on=()
for prop in ChangePlatformProfileOnAc ChangePlatformProfileOnBattery PlatformProfileLinkedEpp; do
	[[ $(busctl --system get-property xyz.ljones.Asusd /xyz/ljones xyz.ljones.Platform "$prop" 2>/dev/null) == "b false" ]] || on+=("$prop")
done
if ((${#on[@]})); then
	warn "asusd still switches the power profile or EPP (${on[*]})"
	return 1
fi
if [[ ! -f /etc/systemd/system/asusd.service.d/10-zenbook-duo-power-profiles.conf ]]; then
	warn "asusd settings are off, but no drop-in keeps them off"
	return 1
fi
ok "asusd leaves the power profile and EPP to power-profiles-daemon"
return 0
