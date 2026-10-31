# shellcheck shell=bash
have cc || die "a C compiler is needed to build the KWin library (pacman -S gcc)"
[[ -f /usr/include/libinput.h ]] || die "libinput headers missing (/usr/include/libinput.h)"

# kwin_wayland has the file capability CAP_SYS_NICE, so ld.so runs it in
# secure-execution mode: it ignores preload paths and preloads a bare name only
# from /usr/lib, and only if the file has the set-user-ID bit (ld.so(8)). The
# bit gives a library no privileges; it only marks it as safe to preload.
lib=/usr/lib/libzenbook-duo-touchpad-accel.so
tmp="$(mktemp -d)"
cc -O2 -fPIC -shared -fvisibility=hidden -Wall -Wextra -Werror -Wl,-z,relro,-z,now \
	-o "$tmp/lib.so" "$MOD_DIR/files/zenbook-duo-touchpad-accel.c" -lm ||
	{ rm -rf "$tmp"; die "building $lib failed"; }
duo_install_file "$tmp/lib.so" "$lib" 4755
rm -rf "$tmp"

# Size of one KWin pixel on the top panel (301.6 mm wide, 2880 px), at the
# scale KWin uses for it.
scale="$(python3 -I - "${SUDO_USER:+/home/$SUDO_USER}/.config/kwinoutputconfig.json" <<'EOF' 2>/dev/null || echo 1.8
import json, sys
for sect in json.load(open(sys.argv[1])):
    if sect.get("name") == "outputs":
        for o in sect["data"]:
            if o.get("connectorName") == "eDP-1" and o.get("scale"):
                print(o["scale"])
                sys.exit()
print(1.8)
EOF
)"
px_mm="$(awk -v s="$scale" 'BEGIN { printf "%.4f", 301.6 / (2880 / s) }')"
duo_write_file /etc/zenbook-duo/touchpad-accel.conf <<EOF
# Keyboard touchpad acceleration inside KWin (module touchpad-accel).
# Changes apply within a second; no need to log out.
#
# curve: apple (Apple's trackpad acceleration) or libinput (stock libinput)
curve=apple
# size of one KWin pixel on the top panel in mm: 301.6 mm / (2880 px / scale $scale)
px_mm=$px_mm
EOF

duo_write_file /etc/systemd/user/plasma-kwin_wayland.service.d/60-zenbook-duo-touchpad-accel.conf <<EOF
# Apple's trackpad acceleration for the keyboard touchpad (module touchpad-accel).
# A bare name: kwin_wayland runs in secure-execution mode, where ld.so ignores
# preload paths. The library only acts on that touchpad, and LD_PRELOAD ends at
# kwin_wayland, so Xwayland and other children never load it.
[Service]
Environment=LD_PRELOAD=${lib##*/}
EOF
warn "log out and back in (or reboot): KWin loads the library when it starts"
