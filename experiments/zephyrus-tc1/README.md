# zephyrus-tc1 (experiment)

Makes the bottom screen of the ASUS ROG Zephyrus Duo 2026 (board GX651AX, Panther Lake + RTX 5090, GPU MUX in dGPU mode) work. Not a `duo` module yet: the repo's machine check only accepts the Zenbook Duo, so the scripts here are run by hand with sudo.

## The problem
- The bottom OLED panel (Samsung ATNA60HR07, the Zenbook's panel) is wired to the Intel Type-C port TC1 in legacy mode, 2 lanes. The top panel is on NVIDIA in dGPU mode (`gpu_mux_mode=0`) and is not covered here.
- The firmware's VBT lists TC1 as an external DisplayPort, so xe drives the panel as DP-1. Then:
  - any modeset of DP-1 after the first one (the console handing over to Hyprland, DPMS, mode changes) ends in `vblank wait timed out` on its pipe, wedged until a suspend or reboot;
  - the cursor and window drags stutter on that screen;
  - when Hyprland or Plymouth hands DP-1 back to the console at shutdown, the reboot hangs.
- Driven as eDP (edited VBT), it lights only with Panel Replay and LOBF (ALPM link off between frames) both off. `xe.enable_psr=0` does not turn Panel Replay off; `xe.enable_panel_replay=0` does. LOBF has no module parameter, only the debugfs flag `i915_edp_lobf_debug`.

## What it changes
- `vbt-tc1-edp.py` writes an edited copy of the VBT: TC1's child device becomes a second internal panel (handle LFP2, type INTERNAL_CONNECTOR) with 2 lanes. `install-vbt.sh` installs it as `/usr/lib/firmware/zephyrus-duo/vbt-tc1-edp.bin` and packs it into the initramfs (xe loads there).
- `install-edp.sh`:
  - adds `xe.vbt_firmware=zephyrus-duo/vbt-tc1-edp.bin xe.enable_psr=0 xe.enable_panel_replay=0` (and the `xe.zephyrus_*` options below) to `/etc/limine-entry-tool.d/zephyrus-duo-dp1-off.conf`;
  - installs `/etc/udev/rules.d/90-zephyrus-duo-lobf.rules`, which runs `/usr/local/lib/zephyrus-duo/lobf-off` when an xe eDP connector appears. That sets `i915_edp_lobf_debug`, and the flag applies from the next modeset on (Hyprland's first one; xe has no console with `zephyrus_no_fbdev`).
- `install.sh` builds a patched xe with DKMS (`zephyrus-duo-xe`) for every installed 7.x kernel, using the Zenbook module's `dkms/build.sh` (this kernel's own xe/i915 sources, sparse clone, cached in `/var/cache/zephyrus-duo/xe-src`; Omarchy's kernel takes kernel.org stable). It also installs the pacman hook `65-zephyrus-duo-xe-sources.hook` (fetches a new kernel's sources before DKMS builds) and `/etc/mkinitcpio.conf.d/zephyrus-duo-xe.conf` (`MODULES+=(xe)`).
- `dkms/patches/` adds module parameters to xe and nothing else; each is off by default:
  - `0001-…`: `zephyrus_tc_legacy_keep` keeps a legacy Type-C port's PHY connected while the port is idle (on the cmdline); `zephyrus_tc_connect_delay_ms` (experiment, unused).
  - `0002-…`: `zephyrus_pll_off_delay_ms` (experiment, unused).
  - `0003-…`: `zephyrus_no_fbdev` skips xe's fbdev console, so nothing re-lights the bottom panel when Hyprland exits or crashes at shutdown (on the cmdline). The console stays on the NVIDIA screen, and so does the LUKS prompt.
- Plymouth's reboot/poweroff screens are masked (`systemctl mask plymouth-{reboot,poweroff,halt,kexec}.service`): they take over every output and hung the shutdown.
- Hyprland: `~/.config/hypr/monitors.lua` leaves monitors at their defaults when the cmdline has `xe.vbt_firmware=`. `~/.local/bin/zephyrus-duo-dp1-enable` and `zephyrus-duo-dp1.service` are the DP-1 workaround and do nothing in eDP mode.

## Check
```sh
grep -o 'xe\.[^ ]*' /proc/cmdline
dkms status zephyrus-duo-xe
modinfo -F filename xe                           # .../updates/dkms/xe.ko.zst
journalctl -b -t zephyrus-duo-lobf               # LOBF off on eDP-2
journalctl -k -b | grep -E 'vblank wait timed out|flip_done timed out|link not ok'   # empty
```

## Undo
`sudo ./revert.sh` (patched xe, pacman hook, `xe.zephyrus_*` options), then reboot. For the eDP setup, remove the udev rule and helper, the vbt/psr options from the drop-in, `/usr/lib/firmware/zephyrus-duo` and `/etc/mkinitcpio.conf.d/zephyrus-duo-vbt.conf`, and run `limine-update`.

## Notes
- Verified on 2026-10-27 (7.2.8-9-omarchy, BIOS GX651AX.310, hand-built xe with the same patches): cold boot and reboot clean, all three screens on at login, no stutter; s2idle suspend and resume; DPMS off/on after 5 s, 30 s and 5 s, no errors.
- Not yet known whether `zephyrus_tc_legacy_keep` and `zephyrus_no_fbdev` are still needed in eDP mode; the DP-1 failures they work around may have been the eDP-as-DP mismatch.
- If the patches stop applying to a new kernel, DKMS fails, the stock xe loads and the boot still works, but a reboot can hang again. Check `dkms status` after kernel updates.
