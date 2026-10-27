# zephyrus-tc1 (experiment)

Makes the bottom screen of the ASUS ROG Zephyrus Duo 2026 (board GX651AX, Panther Lake + RTX 5090, GPU MUX in dGPU mode) work with the stock kernel. Not a `duo` module yet: the repo's machine check only accepts the Zenbook Duo, so the scripts here are run by hand with sudo.

## The problem
- The bottom OLED panel (Samsung ATNA60HR07, the Zenbook's panel) is wired to the Intel Type-C port TC1 in legacy mode, 2 lanes. The top panel is on NVIDIA in dGPU mode (`gpu_mux_mode=0`) and is not covered here.
- The firmware's VBT lists TC1 as an external DisplayPort, so xe drives the panel as DP-1. Then:
  - any modeset of DP-1 after the first one (the console handing over to Hyprland, DPMS, mode changes) ends in `vblank wait timed out` on its pipe, wedged until a suspend or reboot;
  - the cursor and window drags stutter on that screen;
  - when Hyprland or Plymouth hands DP-1 back to the console at shutdown, the reboot hangs.
- Driven as eDP (edited VBT), all of that is gone, but the panel stays black unless Panel Replay and LOBF (ALPM link off between frames) are both off. `xe.enable_psr=0` does not turn Panel Replay off; `xe.enable_panel_replay=0` does. LOBF has no module parameter, only the debugfs flag `i915_edp_lobf_debug`.

## What it changes
- `vbt-tc1-edp.py IN OUT` writes an edited copy of the VBT: TC1's child device becomes a second internal panel (handle LFP2, type INTERNAL_CONNECTOR) with 2 lanes. `install-vbt.sh` installs it as `/usr/lib/firmware/zephyrus-duo/vbt-tc1-edp.bin` and packs it into the initramfs (xe loads there).
- `install-edp.sh`:
  - adds `xe.vbt_firmware=zephyrus-duo/vbt-tc1-edp.bin xe.enable_psr=0 xe.enable_panel_replay=0` to the kernel command line (`/etc/limine-entry-tool.d/zephyrus-duo-edp.conf`);
  - installs `/etc/udev/rules.d/90-zephyrus-duo-lobf.rules`, which runs `/usr/local/lib/zephyrus-duo/lobf-off` when an xe eDP connector appears. That sets `i915_edp_lobf_debug`, and the flag applies from the next modeset on. The kernel console lights the panel earlier, with LOBF still on: a few `8b/10b link not ok, retraining` lines at boot, and the LUKS prompt may not show on the bottom screen (it does on the top one). Hyprland's first modeset has LOBF off.
- Plymouth's reboot/poweroff screens need nothing: with the panel as DP-1 they hung the shutdown (they had to be masked), in eDP mode they work, with the keyboard docked or lifted.
- Hyprland: `~/.config/hypr/monitors.lua` leaves monitors at their defaults when the cmdline has `xe.vbt_firmware=`.

## Check
```sh
grep -o 'xe\.[^ ]*' /proc/cmdline
journalctl -b -t zephyrus-duo-lobf               # LOBF off on eDP-2
journalctl -k -b | grep -E 'vblank wait timed out|flip_done timed out'   # empty
```

## Undo
`sudo ./revert.sh`, then reboot.

## Notes
- Verified on 2026-10-27 (7.2.8-9-omarchy, BIOS GX651AX.310, stock xe): boot and reboot clean, all screens on at login, no stutter; s2idle suspend and resume; DPMS off/on after 30 s and 5 s; a reboot where Hyprland segfaulted on exit and the console re-lit the panel.
- The earlier DP-1 workarounds are in git history: a DKMS-built patched xe (`zephyrus_tc_legacy_keep` kept the TC1 PHY connected, `zephyrus_no_fbdev` dropped xe's console so nothing re-lit DP-1 at shutdown) and a login script/service that enabled DP-1 in its own commit. None of them is needed in eDP mode (tested with the patched xe's options off, then with stock xe).
