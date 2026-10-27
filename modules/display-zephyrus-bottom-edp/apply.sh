# shellcheck shell=bash
# Edit the VBT xe is using (stock, or edited by an earlier apply: the script then copies
# it unchanged), load it with xe.vbt_firmware, turn Panel Replay off on the cmdline and
# LOBF off through debugfs when the panel's connector appears. xe lives in the initramfs,
# so the VBT has to be there too.

duo_pkg_install python

vbt=""
for f in /sys/kernel/debug/dri/*/i915_vbt; do
	[[ -e $f ]] && { vbt="$f"; break; }
done
[[ -n $vbt ]] || die "no i915_vbt in debugfs: is xe loaded and /sys/kernel/debug mounted?"
work="$(mktemp -d)"
cat "$vbt" >"$work/vbt.bin"
python3 -I "$MOD_DIR/files/vbt-tc1-edp.py" "$work/vbt.bin" "$work/edited.bin" | while read -r line; do info "$line"; done
[[ -s $work/edited.bin ]] || die "editing the VBT failed (see the lines above)"
duo_install_file "$work/edited.bin" /usr/lib/firmware/zenbook-duo/zephyrus-vbt-tc1-edp.bin
rm -rf "$work"

duo_install_file "$MOD_DIR/files/zenbook-duo-zephyrus-vbt.conf" /etc/mkinitcpio.conf.d/zenbook-duo-zephyrus-vbt.conf
duo_install_file "$MOD_DIR/files/zephyrus-lobf-off" /usr/lib/zenbook-duo/zephyrus-lobf-off 0755
duo_install_file "$MOD_DIR/files/90-zenbook-duo-zephyrus-lobf.rules" /etc/udev/rules.d/90-zenbook-duo-zephyrus-lobf.rules
duo_cmdline_add xe.vbt_firmware=zenbook-duo/zephyrus-vbt-tc1-edp.bin xe.enable_psr=0 xe.enable_panel_replay=0
duo_need_initramfs

# The earlier hand-installed experiment used other paths; drop it once all of the above
# is in place (the bootloader and initramfs are regenerated after this anyway).
for old in /etc/limine-entry-tool.d/zephyrus-duo-edp.conf /etc/limine-entry-tool.d/zephyrus-duo-dp1-off.conf \
	/etc/udev/rules.d/90-zephyrus-duo-lobf.rules /usr/local/lib/zephyrus-duo/lobf-off \
	/etc/mkinitcpio.conf.d/zephyrus-duo-vbt.conf /usr/lib/firmware/zephyrus-duo/vbt-tc1-edp.bin; do
	[[ -e $old ]] || continue
	rm -f "$old"
	_mark_for_path "$old"
	info "removed $old (from the experiment, replaced by this module)"
done
rmdir /usr/local/lib/zephyrus-duo /usr/lib/firmware/zephyrus-duo 2>/dev/null || true
