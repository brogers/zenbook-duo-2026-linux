# shellcheck shell=bash
# libinput reads a single local quirks file: keep anything else in it and
# replace only this module's section.
dest=/etc/libinput/local-overrides.quirks
tmp="$(mktemp)"
if [[ -f $dest ]]; then
	sed '/^# >>> zenbook-duo-2026-linux touchpad-palm$/,/^# <<< zenbook-duo-2026-linux touchpad-palm$/d' "$dest" >"$tmp"
	[[ -s $tmp ]] && echo >>"$tmp"
fi
cat "$MOD_DIR/files/zenbook-duo-touchpad.quirks" >>"$tmp"
duo_install_file "$tmp" "$dest"
rm -f "$tmp"
# libinput loads quirks when the compositor starts
warn "log out and back in (or reboot) for the touchpad change to take effect"
