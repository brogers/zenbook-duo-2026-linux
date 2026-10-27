#!/bin/bash
# install.sh: build the patched xe (dkms/patches) with DKMS for every installed
# 7.x kernel, so kernel updates keep it. Replaces the hand-built module of the
# first experiments (updates/zephyrus-duo/). The module goes to updates/dkms/,
# which depmod searches before the stock one; mkinitcpio packs it explicitly
# (the kms hook only takes GPU drivers from kernel/drivers/gpu/drm/).
# revert.sh undoes it.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
name=zephyrus-duo-xe
ver="$(sed -n 's/^PACKAGE_VERSION="\(.*\)"$/\1/p' "$here/dkms/dkms.conf")"

# the Zenbook's display-edp2-tcss builds its own xe into the same place
if dkms status -m zenbook-duo-xe 2>/dev/null | grep -q .; then
	echo "zenbook-duo-xe (display-edp2-tcss) is installed; revert it first" >&2
	exit 1
fi

pkgs=(dkms git patch pahole)
grep -q '^CONFIG_CC_IS_CLANG=y' "/usr/lib/modules/$(uname -r)/build/.config" 2>/dev/null && pkgs+=(clang llvm lld)
pacman -S --needed --noconfirm "${pkgs[@]}"

# drop other registered versions of the package
for old in $(dkms status -m "$name" 2>/dev/null | sed -n "s|^$name/\([^,]*\),.*|\1|p" | sort -u); do
	[[ $old == "$ver" ]] && continue
	dkms remove -m "$name" -v "$old" --all && rm -rf "/usr/src/$name-$old"
done
rm -rf "/usr/src/$name-$ver"
cp -a "$here/dkms" "/usr/src/$name-$ver"
dkms add -m "$name" -v "$ver" 2>/dev/null || true

for k in /usr/lib/modules/*; do
	k="${k##*/}"
	[[ -d /usr/lib/modules/$k/build ]] || continue
	if dkms install -m "$name" -v "$ver" -k "$k"; then
		# the hand-built module from the first experiments
		rm -rf "/usr/lib/modules/$k/updates/zephyrus-duo"
		depmod "$k"
	else
		echo "warning: $name not built for $k; the stock xe stays in use there" >&2
	fi
done

# pacman 7.1 runs hooks without network; the hook asks for it where pacman knows the option
hook=/etc/pacman.d/hooks/65-zephyrus-duo-xe-sources.hook
mkdir -p "${hook%/*}"
if grep -qa NetworkAccess /usr/lib/libalpm.so; then
	install -m644 "$here/files/65-zephyrus-duo-xe-sources.hook" "$hook"
else
	grep -v '^NetworkAccess' "$here/files/65-zephyrus-duo-xe-sources.hook" >"$hook"
fi

printf '%s\n' \
	"# zenbook-duo-2026-linux (experiments/zephyrus-tc1): pack the patched xe from" \
	"# updates/dkms/ into the initramfs; the kms hook would only take the stock one." \
	"MODULES+=(xe)" >/etc/mkinitcpio.conf.d/zephyrus-duo-xe.conf
limine-mkinitcpio

kver="$(uname -r)"
echo "xe for $kver now resolves to: $(modinfo -k "$kver" -F filename xe)"
