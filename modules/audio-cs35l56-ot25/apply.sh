# shellcheck shell=bash
# 7.2.11 binds the CS35L56 amp feedback to the codec DAI "cs35l56-ot25", but the
# CS35L56 driver in 7.2.11 does not register that DAI. The sound card waits for
# it forever (only "Dummy Output").
# Rebuild snd-soc-cs35l56 and snd-soc-cs35l56-sdw from the 7.2.11 sources plus
# upstream 86c8360c97f6 as queued for 7.2.12; dkms.conf restricts builds to 7.2.11.

pkgs=(patch pahole)
grep -q '^CONFIG_CC_IS_CLANG=y' "/usr/lib/modules/$(uname -r)/build/.config" 2>/dev/null && pkgs+=(clang llvm lld)
duo_pkg_install "${pkgs[@]}"
duo_dkms_install "$MOD_DIR/dkms" zenbook-duo-cs35l56 7.2.11.1
