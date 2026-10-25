# shellcheck shell=bash
# 0 = audio card ok, 1 = broken, 2 = not applicable.

# taint O = an out-of-tree (DKMS) build of the codec is loaded
dkms_loaded=no
[[ $(cat /sys/module/snd_soc_cs35l56/taint 2>/dev/null) == *O* ]] && dkms_loaded=yes
if grep -q sofsoundwire /proc/asound/cards; then
	ok "SoundWire card registered (CS35L56 codec with the OT25 DAI from dkms: $dkms_loaded)"
	return 0
fi
if klog | grep -q 'CODEC DAI cs35l56-ot25 not registered'; then
	warn "the sound card waits for the CS35L56 OT25 DAI (no internal speakers/mic)"
	[[ $dkms_loaded == no ]] && dkms status zenbook-duo-cs35l56 2>/dev/null | grep -q "$(uname -r).*installed" &&
		info "fixed codec installed for $(uname -r); reboot pending"
	return 1
fi
warn "no SoundWire sound card"
return 1
