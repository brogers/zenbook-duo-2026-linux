# shellcheck shell=bash
# "Zenbook Duo Power" KDE panel widget. A small QML plugin (src/powermonitor.cpp) reads
# sysfs directly: what the whole laptop draws (RAPL psys, scaled), the battery's flow,
# the RAPL breakdown (processor cores, graphics/SoC, memory), temperatures and fans.
# Sampling: every 2 s in the panel, every 1 s while the popup is open; no helper processes.
# The USB-C charger's contract comes from a small udev helper (files/charger-info).
duo_pkg_install gcc pkgconf qt6-base qt6-declarative
build="$(mktemp -d)"
# shellcheck disable=SC2046
/usr/lib/qt6/moc $(pkg-config --cflags-only-I Qt6Qml Qt6DBus Qt6Core) "$MOD_DIR/src/powermonitor.cpp" -o "$build/powermonitor.moc"
# shellcheck disable=SC2046
g++ -std=c++20 -O2 -fPIC -shared "$MOD_DIR/src/powermonitor.cpp" -o "$build/libzenbookduopowerplugin.so" -I"$build" \
	$(pkg-config --cflags --libs Qt6Qml Qt6DBus Qt6Core) || die "power widget plugin build failed"
qml=/usr/lib/qt6/qml/org/zenbookduo/power
duo_install_file "$build/libzenbookduopowerplugin.so" "$qml/libzenbookduopowerplugin.so" 0755
rm -rf "$build"
duo_install_file "$MOD_DIR/files/qmldir" "$qml/qmldir"
pkg=/usr/share/plasma/plasmoids/org.zenbookduo.power
duo_install_file "$MOD_DIR/plasmoid/metadata.json" "$pkg/metadata.json"
duo_install_file "$MOD_DIR/plasmoid/contents/ui/main.qml" "$pkg/contents/ui/main.qml"
duo_install_file "$MOD_DIR/files/70-zenbook-duo-rapl.rules" /etc/udev/rules.d/70-zenbook-duo-rapl.rules
duo_install_file "$MOD_DIR/files/charger-info" /usr/lib/zenbook-duo/charger-info 0755
duo_install_file "$MOD_DIR/files/71-zenbook-duo-charger.rules" /etc/udev/rules.d/71-zenbook-duo-charger.rules
udevadm control --reload
udevadm trigger --subsystem-match=powercap --action=add
/usr/lib/zenbook-duo/charger-info
info "add it to a panel: right-click the panel > Add or Manage Widgets > \"Zenbook Duo Power\""
info "an updated widget loads after the next login (or: systemctl --user restart plasma-plasmashell)"
