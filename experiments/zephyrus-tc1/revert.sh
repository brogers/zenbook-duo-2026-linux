#!/bin/bash
# revert.sh: remove the patched xe that install.sh put in place and go back to
# the stock module. Leaves the VBT and cmdline of install-vbt.sh/install-edp.sh,
# but takes xe.zephyrus_* out of the cmdline drop-in (stock xe does not know them;
# without zephyrus_no_fbdev the reboot hang can come back, see README.md).
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
name=zephyrus-duo-xe

for v in $(dkms status -m "$name" 2>/dev/null | sed -n "s|^$name/\([^,]*\),.*|\1|p" | sort -u); do
	dkms remove -m "$name" -v "$v" --all
	rm -rf "/usr/src/$name-$v"
done
rm -rf /usr/lib/modules/*/updates/zephyrus-duo
rm -f /etc/pacman.d/hooks/65-zephyrus-duo-xe-sources.hook /etc/mkinitcpio.conf.d/zephyrus-duo-xe.conf
sed -i 's/ xe\.zephyrus_[a-z_]*=[^ "]*//g' /etc/limine-entry-tool.d/zephyrus-duo-dp1-off.conf
for k in /usr/lib/modules/*; do depmod "${k##*/}"; done
limine-update

kver="$(uname -r)"
echo "xe for $kver now resolves to: $(modinfo -k "$kver" -F filename xe)"
