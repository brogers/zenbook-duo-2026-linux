# display-zephyrus-bottom-edp

Makes the bottom screen of the **ASUS ROG Zephyrus Duo 2026 (GX651AX)** usable: no hangs when it turns on or off, clean reboots, no cursor stutter. Only applies to the GX651AX.

## The problem
- The bottom OLED panel (Samsung ATNA60HR07, the Zenbook Duo's panel) is wired to Intel Type-C port TC1 in legacy mode, 2 lanes. The firmware's VBT lists that port as an external DisplayPort, so xe drives it as `DP-1`:
  - every modeset after the first one (console to desktop hand-over, DPMS, mode change) ends in `vblank wait timed out`, wedged until suspend or reboot;
  - cursor and window drags stutter on that screen;
  - a reboot hangs when the console takes the screen back (Hyprland or Plymouth handing over at shutdown).
- Driven as eDP, all of that is gone, but the panel stays black while Panel Replay or LOBF (ALPM link off between frames) is on. `xe.enable_psr=0` leaves Panel Replay on; `xe.enable_panel_replay=0` turns it off. LOBF has no module parameter, only the debugfs flag `i915_edp_lobf_debug`.

## What it changes
- `files/vbt-tc1-edp.py` edits the VBT xe is using (read from debugfs `i915_vbt`): TC1's child device becomes a second internal panel (handle LFP2, type INTERNAL_CONNECTOR) limited to 2 lanes. Re-applying is safe: an edited VBT is copied unchanged. Installs `python` if missing.
- `/usr/lib/firmware/zenbook-duo/zephyrus-vbt-tc1-edp.bin`, packed into the initramfs by `/etc/mkinitcpio.conf.d/zenbook-duo-zephyrus-vbt.conf` (xe loads there); the initramfs is rebuilt.
- Kernel cmdline: `xe.vbt_firmware=zenbook-duo/zephyrus-vbt-tc1-edp.bin xe.enable_psr=0 xe.enable_panel_replay=0`.
- `/etc/udev/rules.d/90-zenbook-duo-zephyrus-lobf.rules` runs `/usr/lib/zenbook-duo/zephyrus-lobf-off` when an xe eDP connector appears; it sets `i915_edp_lobf_debug`, which applies from the connector's next modeset.
- NVIDIA is dropped from the initramfs (the same `mkinitcpio.conf.d` file filters `nvidia*` out of `MODULES`, which Omarchy's `nvidia.conf` adds). Loaded there, before xe, it left xe's panels black in hybrid mode (`gpu_mux_mode=1`): the LUKS prompt, and the top panel after login until the dGPU runtime-suspended (the panel latched DSC errors, `0x20f` = `04`). The panel registers showed why: with NVIDIA loaded first, the top panel was left with ASSR (DPCD `0x10a`) and Panel Replay (`0x1b0`) enabled, out of sync with symbol errors, a bright random pattern or black. NVIDIA now loads from the root filesystem; in dGPU mode the firmware framebuffer shows the LUKS prompt on the top panel until then.
- Removes the files of the earlier hand-installed experiment (`/etc/limine-entry-tool.d/zephyrus-duo-*.conf`, `/etc/udev/rules.d/90-zephyrus-duo-lobf.rules`, `/usr/local/lib/zephyrus-duo/`, `/etc/mkinitcpio.conf.d/zephyrus-duo-vbt.conf`, `/usr/lib/firmware/zephyrus-duo/`).

## Check
```sh
./duo status display-zephyrus-bottom-edp
grep -o 'xe\.[^ ]*' /proc/cmdline
journalctl -b -t zenbook-duo-lobf                 # LOBF off on eDP-2
```

## Undo
`sudo ./duo revert display-zephyrus-bottom-edp`, then reboot. The bottom panel is `DP-1` again, with the problems above.

## Notes
- The panel only exists if the laptop boots with the keyboard lifted. Docked, the firmware keeps the panel powered off; xe finds no panel on TC1 ("failed to retrieve link info, disabling eDP") and never looks again, so lifting the keyboard later does not bring it back. Reboot with the keyboard lifted. (`asus_screenpad`'s `bl_power` switches the panel while lifted, 1 on and 0 off, but cannot power it while docked.)
- While docked the firmware cuts the panel's power; after lifting, the panel shows a bright random pattern until it is enabled afresh. The desktop has to disable it while docked and enable it after lifting (on Hyprland: a udev watcher that reloads the config, with `disabled = <keyboard on USB 0b05:1ce6>` in the monitor rule).
- The top panel is NVIDIA's in dGPU mode (`gpu_mux_mode=0`). In hybrid mode (`gpu_mux_mode=1`) xe drives both panels, the top one on port A. Connector names shift with the MUX and with whether NVIDIA registers its connectors first (hybrid: top eDP-1 and bottom eDP-2, or eDP-2 and eDP-3), so tell the panels apart by AUX channel: `AUX A` is the top, `AUX USBC1` (TC1) the bottom.
- xe's own console lights the panels before the LOBF rule runs (it is not in the initramfs): a few `8b/10b link not ok, retraining` lines at boot. The LUKS prompt shows anyway, in both GPU modes, since NVIDIA is out of the initramfs.
- Every enable and disable of the panel logs a `drm_WARN_ON(... aux_io == POWER_DOMAIN_INVALID)` from `intel_display_power_aux_io_domain`; harmless.
- Verified on 2026-10-27 (BIOS GX651AX.310, linux-omarchy 7.2.8, stock xe): boot and reboot clean (Plymouth shutdown screens included), DPMS off/on after 5 s and 30 s, s2idle, keyboard dock and lift.
