# desktop-power-widget

A KDE panel widget that shows what the laptop draws right now, on battery and plugged in, and how fast the battery charges or drains; click it for where the power comes from and goes, a breakdown, temperatures, fans, the power mode and battery health.

## The problem
- KDE shows the battery percentage, but not how much power the laptop draws or what draws it. Plugged in, the battery fuel gauge cannot tell: it only sees the battery's own current.
- The firmware's battery numbers mislead on this model (ACPI `_BST`):
  - `power_now` is |current| × the battery's *design* voltage (16.06 V), so it reads up to ~10% low on a full battery at 17.6–17.8 V.
  - The sign is dropped and "Charging" only means the EC allows charging. On a charger weaker than the load the battery drains while it says "Charging" (seen on a 40 W charger: 100% → 84% in 1¾ hours, "Charging" all along), or while it says "Full".
  - The EC smooths the current: every 10 s it reports the mean of the new reading and the previous report.
- The kernel cannot tell what a USB-C charger delivers: the EC's UCSI does not advertise PDO details, so `ucsi-source-psy-*` reports 0 V.
- The processor's energy counters (Intel RAPL) are readable only by root.

## How it measures
- **What the laptop draws**: the RAPL `psys` counter. It integrates the charger's system power monitor (PSYS): the power going into the laptop from the charger and the battery together, *without* the power that goes into the battery (stopping the charge at a fixed load leaves it unchanged). So it works plugged in as well as on battery. On this model it counts about twice the real value: the widget scales it and refines the scale whenever it runs on battery, where psys must equal the power the battery gives (fuel gauge, corrected to the real voltage). The scale is kept in `~/.local/state/zenbook-duo/power-widget.ini`.
- **The battery's flow**: on battery, what the laptop draws. Plugged in, the charger's USB-PD contract decides the direction: the charger cannot give more than the contract, so whatever the laptop draws beyond it comes from the battery ("draining although plugged in"); below it the battery takes what it accepts (the fuel gauge's current at the real voltage).
- **The charger**: `/usr/lib/zenbook-duo/charger-info`, run by udev when a charger is plugged in, renegotiates or is unplugged, reads the negotiated contract with two read-only UCSI commands through debugfs (connector status and the requested source PDO) and writes `/run/zenbook-duo/charger` (`watts`, `volts`, `amps`, `slow`).

## What it changes
- Installs packages if missing: `gcc`, `pkgconf`, `qt6-base`, `qt6-declarative`.
- Builds a small QML plugin from `src/powermonitor.cpp` into `/usr/lib/qt6/qml/org/zenbookduo/power/` (with its `qmldir`).
- Installs the widget "Zenbook Duo Power" into `/usr/share/plasma/plasmoids/org.zenbookduo.power/`.
- Installs `/etc/udev/rules.d/70-zenbook-duo-rapl.rules`: the RAPL energy counters (`package-0`, `core`, `uncore`, `dram`, `psys`) become readable for the `wheel` group only (they stay closed for other users because of CVE-2020-8694).
- Installs `/usr/lib/zenbook-duo/charger-info` and `/etc/udev/rules.d/71-zenbook-duo-charger.rules`.
- Add it to a panel: right-click the panel > Add or Manage Widgets > "Zenbook Duo Power". No reboot needed; an updated widget loads at the next login (or `systemctl --user restart plasma-plasmashell`).

What the widget shows:
- **Panel:** what the laptop draws; plugged in, also the battery's flow: `+8.7 W` in green while it charges, `−4.1 W` in red while it drains although plugged in. The icon shows the charge level and whether it charges.
- **Popup:** the same with time left or time to full (to the charge limit), the power flow (from the charger, e.g. "37 W of 40 W · 20 V 2.0 A"; the laptop; the battery), a note when the charger cannot keep up with the load, the breakdown (processor cores, graphics and the rest of the chip, memory, and everything else: screens, Wi-Fi, SSD, keyboard, power conversion), processor/SSD/Wi-Fi temperatures, fan speeds, power mode buttons (Quiet / Balanced / Performance, same as KDE's power profiles), battery health, cycles and charge limit.

Accuracy: the laptop's draw follows the psys scale (refined on battery, see `./duo status`). Within about 2 W of the charger's limit the battery alternates between charging and helping out; the widget then says the charger is fully used and shows the small net flow as an estimate.

Cost: it reads a few small sysfs files every 2 s while it sits in the panel and every 1 s while the popup is open, inside plasmashell, without starting any process. The charger helper runs only when a charger is plugged in or out (about 0.1 s).

## Check
```sh
./duo status desktop-power-widget                 # charger contract, psys scale
cat /sys/class/powercap/intel-rapl:1/energy_uj    # psys, must work as your user
cat /run/zenbook-duo/charger
```

## Undo
`sudo ./duo revert desktop-power-widget`, then remove the widget from the panel.
