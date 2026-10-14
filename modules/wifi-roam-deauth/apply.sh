# shellcheck shell=bash
# Rebuild mac80211 with dkms/patches for every installed 7.x kernel. build.sh
# fetches the kernel's own net/mac80211 sources (sparse clone), so the module
# matches the running kernel exactly apart from the patch. mac80211 is not in
# the initramfs; it loads from updates/dkms/ at the next boot.

pkgs=(git patch pahole)
grep -q '^CONFIG_CC_IS_CLANG=y' "/usr/lib/modules/$(uname -r)/build/.config" 2>/dev/null && pkgs+=(clang llvm lld)
duo_pkg_install "${pkgs[@]}"
duo_dkms_install "$MOD_DIR/dkms" zenbook-duo-mac80211 1.0
