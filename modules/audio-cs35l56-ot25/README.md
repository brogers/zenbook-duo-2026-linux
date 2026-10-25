# audio-cs35l56-ot25

Gives you working speakers, headphones and microphones on kernel 7.2.11.

## The problem
- On 7.2.11 there is no sound card, only "Dummy Output". The kernel log shows `sof_sdw sof_sdw: ASoC: CODEC DAI cs35l56-ot25 not registered`.
- 7.2.11 backported `4b7f393a01f8 ASoC: sdw_utils: Switch CS35L56/57/62/63 to use OT25 DAI`. The machine driver now connects the amplifier feedback to the codec DAI `cs35l56-ot25` (SoundWire DP4).
- The first patch of the same series, `86c8360c97f6 ASoC: cs35l56: Add DAI for SDCA OT25 stream`, adds that DAI to the CS35L56 driver. It was not backported, so the card waits for a DAI that never appears.
- This hits every laptop with CS35L56/57/62/63 amplifiers on SoundWire running 7.2.11. It was reported on the stable list on 2026-10-16, and `86c8360c97f6` was queued for 7.2.12 the next day.

## What it changes
- Registers and builds the DKMS package `zenbook-duo-cs35l56` version `7.2.11.1` (source copied to `/usr/src/zenbook-duo-cs35l56-7.2.11.1`). It is `snd-soc-cs35l56` and `snd-soc-cs35l56-sdw` from Linux 7.2.11 plus `86c8360c97f6` exactly as queued for 7.2.12 (`dkms/patches/`), installed to `/updates/dkms`.
- `dkms.conf` limits builds to 7.2.11 kernels (`BUILD_EXCLUSIVE_KERNEL`).
- A reboot is required. Without one, reload the codec; the waiting card registers as soon as the DAI appears:
  `sudo modprobe -r snd_soc_cs35l56_sdw snd_soc_cs35l56 && sudo modprobe snd_soc_cs35l56_sdw`

## Check
```sh
./duo status audio-cs35l56-ot25
cat /proc/asound/cards                     # should list a sofsoundwire card
cat /sys/module/snd_soc_cs35l56/taint      # O = the DKMS build is loaded
```

## Undo
`sudo ./duo revert audio-cs35l56-ot25`, then reboot.

## Notes
- Kernel range: 7.2.11 only (`KERNEL_MIN="7.2.11"`, `KERNEL_MAX="7.2.12"`). 7.3 has both patches; 7.3-rc6 and earlier have neither, which also works.
- On 7.2.x `audio-ghost-rt722` is still needed as well.
