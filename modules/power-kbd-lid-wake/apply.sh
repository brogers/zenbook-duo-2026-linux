# shellcheck shell=bash
# systemd-sleep hook: before a suspend with the lid closed, turn off the docked keyboard's
# USB wakeup; turn it back on after resume.
duo_install_file "$MOD_DIR/files/zenbook-duo-kbd-lid-wake" /usr/lib/systemd/system-sleep/zenbook-duo-kbd-lid-wake 0755
