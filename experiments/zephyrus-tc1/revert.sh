#!/bin/bash
# revert.sh: undo install-vbt.sh and install-edp.sh (and the patched xe of the
# earlier experiments, if still there). The bottom panel is DP-1 again after a
# reboot, with its modeset hangs and reboot hangs; see README.md.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

for v in $(dkms status -m zephyrus-duo-xe 2>/dev/null | sed -n 's|^zephyrus-duo-xe/\([^,]*\),.*|\1|p' | sort -u); do
	dkms remove -m zephyrus-duo-xe -v "$v" --all
	rm -rf "/usr/src/zephyrus-duo-xe-$v"
done
rm -rf /usr/lib/modules/*/updates/zephyrus-duo
rm -f /etc/pacman.d/hooks/65-zephyrus-duo-xe-sources.hook /etc/mkinitcpio.conf.d/zephyrus-duo-xe.conf

rm -f /etc/udev/rules.d/90-zephyrus-duo-lobf.rules
rm -rf /usr/local/lib/zephyrus-duo
rm -f /etc/limine-entry-tool.d/zephyrus-duo-edp.conf /etc/limine-entry-tool.d/zephyrus-duo-dp1-off.conf
rm -rf /usr/lib/firmware/zephyrus-duo
rm -f /etc/mkinitcpio.conf.d/zephyrus-duo-vbt.conf
for k in /usr/lib/modules/*; do depmod "${k##*/}"; done
limine-update

echo "reverted; reboot"
