# shellcheck shell=bash
# 0 = patched mac80211 running, 1 = not running or turned off, 2 = not applicable.

param=/sys/module/mac80211/parameters/zenbook_duo_roam_deauth
if [[ ! -e $param ]]; then
	if [[ ! -d /usr/lib/modules/$(uname -r) ]]; then
		info "the running kernel was updated: the patched mac80211 loads after a reboot"
	elif dkms status zenbook-duo-mac80211 2>/dev/null | grep -q "$(uname -r).*installed"; then
		info "patched mac80211 built for $(uname -r); reboot pending"
	else
		warn "patched mac80211 not built for $(uname -r) (see: dkms status zenbook-duo-mac80211)"
	fi
	return 1
fi
if [[ $(<"$param") != Y ]]; then
	warn "patched mac80211 loaded but turned off (mac80211.zenbook_duo_roam_deauth=0)"
	return 1
fi
ok "patched mac80211 loaded: deauthenticates from the old AP when roaming with PMF"
# A timeout can still happen when the new AP is out of reach; many of them point at this bug.
timeouts=$(klog | grep -cE 'wlan[0-9]+: association with .* timed out')
((timeouts)) && info "$timeouts association timeout(s) in this boot (journalctl -k -b | grep -E 'disconnect from AP|timed out')"
return 0
