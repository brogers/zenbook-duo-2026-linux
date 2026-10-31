# shellcheck shell=bash
duo_install_file "$MOD_DIR/files/50-zenbook-duo-touchpad-bt-jumps.lua" \
	/etc/libinput/plugins/50-zenbook-duo-touchpad-bt-jumps.lua
duo_install_file "$MOD_DIR/files/61-zenbook-duo-touchpad.hwdb" /etc/udev/hwdb.d/61-zenbook-duo-touchpad.hwdb
# libinput loads plugins and reads the touchpad's axes when the compositor starts
warn "log out and back in (or reboot) for the touchpad change to take effect"
