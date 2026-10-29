# shellcheck shell=bash
# The drop-in turns the settings off at every asusd start; set them on the running
# asusd too, so nothing waits for a restart. Revert restores the values found here.
systemctl is-active --quiet asusd.service || die "asusd is not running"
duo_install_file "$MOD_DIR/files/10-zenbook-duo-power-profiles.conf" /etc/systemd/system/asusd.service.d/10-zenbook-duo-power-profiles.conf
for prop in ChangePlatformProfileOnAc ChangePlatformProfileOnBattery PlatformProfileLinkedEpp; do
	duo_busctl_set xyz.ljones.Asusd /xyz/ljones xyz.ljones.Platform "$prop" b false
done
