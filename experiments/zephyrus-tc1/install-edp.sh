#!/bin/bash
# install-edp.sh: make the bottom panel's eDP setup persistent.
# With the edited VBT (install-vbt.sh) TC1 is an eDP connector, and it only
# shows a picture with Panel Replay and LOBF (ALPM link off between frames)
# both off. Panel Replay has a module parameter; LOBF only has a debugfs flag,
# set by a udev rule when the connector appears (read at the next modeset,
# which is Hyprland's first one: xe has no fbdev with zephyrus_no_fbdev=1).
# Undo: rm /etc/udev/rules.d/90-zephyrus-duo-lobf.rules /usr/local/lib/zephyrus-duo/lobf-off,
# put back the KERNEL_CMDLINE line without the vbt/psr options, limine-update
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
[[ -f /usr/lib/firmware/zephyrus-duo/vbt-tc1-edp.bin ]] || { echo "run install-vbt.sh first" >&2; exit 1; }

install -d /usr/local/lib/zephyrus-duo
cat >/usr/local/lib/zephyrus-duo/lobf-off <<'EOF'
#!/bin/sh
# lobf-off CONNECTOR (e.g. card0-eDP-2): disable LOBF on an xe eDP connector.
# Run by /etc/udev/rules.d/90-zephyrus-duo-lobf.rules.
name=${1#card*-}
for i in 1 2 3 4 5 6 7 8 9 10; do
	for f in /sys/kernel/debug/dri/*/"$name"/i915_edp_lobf_debug; do
		[ -e "$f" ] && { echo 1 >"$f"; logger -t zephyrus-duo-lobf "LOBF off on $name"; exit 0; }
	done
	sleep 0.2
done
logger -t zephyrus-duo-lobf "no i915_edp_lobf_debug for $name"
EOF
chmod 755 /usr/local/lib/zephyrus-duo/lobf-off

cat >/etc/udev/rules.d/90-zephyrus-duo-lobf.rules <<'EOF'
# zenbook-duo-2026-linux (experiments/zephyrus-tc1): the Zephyrus Duo's bottom
# panel (eDP via the edited VBT) stays black with LOBF on.
ACTION=="add", SUBSYSTEM=="drm", KERNEL=="card*-eDP-*", DRIVERS=="xe", RUN+="/usr/local/lib/zephyrus-duo/lobf-off %k"
EOF

cat >/etc/limine-entry-tool.d/zephyrus-duo-dp1-off.conf <<'EOF'
# Zephyrus Duo GX651AX: patched xe from experiments/zephyrus-tc1 (keep the
# bottom panel's Type-C PHY TC1 connected, no xe fbdev), the edited VBT that
# makes TC1 an eDP connector, and no PSR/Panel Replay (black panel otherwise).
KERNEL_CMDLINE[default]+=" xe.zephyrus_tc_legacy_keep=1 xe.zephyrus_no_fbdev=1"
KERNEL_CMDLINE[default]+=" xe.vbt_firmware=zephyrus-duo/vbt-tc1-edp.bin xe.enable_psr=0 xe.enable_panel_replay=0"
EOF
limine-update

echo "installed; reboot without editing the Limine entry"
