#!/bin/bash
# install-vbt.sh VBT_BIN: install an edited VBT as firmware for xe.vbt_firmware.
# xe loads from the initramfs, so the file is packed there too; nothing uses it
# until the kernel command line has xe.vbt_firmware=zephyrus-duo/vbt-tc1-edp.bin.
# Undo: rm -r /usr/lib/firmware/zephyrus-duo /etc/mkinitcpio.conf.d/zephyrus-duo-vbt.conf; limine-mkinitcpio
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
vbt="${1:?usage: install-vbt.sh VBT_BIN}"
[[ $(head -c 4 "$vbt") == '$VBT' ]] || { echo "$vbt is not a VBT" >&2; exit 1; }

install -Dm644 "$vbt" /usr/lib/firmware/zephyrus-duo/vbt-tc1-edp.bin
printf '%s\n' \
	"# zenbook-duo-2026-linux (experiments/zephyrus-tc1): edited VBT for" \
	"# xe.vbt_firmware=zephyrus-duo/vbt-tc1-edp.bin, needed when xe loads." \
	"FILES+=(/usr/lib/firmware/zephyrus-duo/vbt-tc1-edp.bin)" >/etc/mkinitcpio.conf.d/zephyrus-duo-vbt.conf
limine-mkinitcpio

echo "installed /usr/lib/firmware/zephyrus-duo/vbt-tc1-edp.bin"
