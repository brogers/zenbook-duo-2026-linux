# shellcheck shell=bash
# Remap the firmware's KEY_WLAN to nothing; the transaction updates the hwdb and
# re-triggers the input devices, so it takes effect without a reboot.
duo_install_file "$MOD_DIR/files/90-zenbook-duo-zephyrus-wlan-key.hwdb" /etc/udev/hwdb.d/90-zenbook-duo-zephyrus-wlan-key.hwdb

# The same remap, installed by hand before this module existed.
old=/etc/udev/hwdb.d/90-zephyrus-duo-wlan-key.hwdb
if [[ -e $old ]]; then
	rm -f "$old"
	info "removed $old (replaced by this module)"
fi
