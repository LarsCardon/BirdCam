#!/usr/bin/env bash
#
# wifi-check.sh — one-shot Wi-Fi dongle diagnostic for BirdCam on a Raspberry Pi.
#
# Run it (with the dongle plugged in, ideally while Ethernet is still attached)
# to see, in order, exactly WHICH layer is failing:
#
#   1. Is the dongle visible on the USB bus at all?   (power / cable / port)
#   2. Did the kernel create a wireless interface?     (driver bound or not)
#   3. Is that interface associated to your Wi-Fi?     (credentials / range)
#
# The single most useful output is the USB ID + chipset hint: look the ID up
# BEFORE installing any driver, so you know whether your dongle uses an
# in-kernel driver (great) or a fragile out-of-tree one (avoid).
#
#   Usage:  bash scripts/wifi-check.sh
#
set -u

say() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

say "Kernel"
uname -a

say "Pinned kernel packages (apt holds)"
apt-mark showhold 2>/dev/null | grep -i linux || echo "(none held)"

say "USB devices (Wi-Fi candidates highlighted)"
if command -v lsusb >/dev/null; then
  lsusb
  echo
  echo "--- likely Wi-Fi adapters (Realtek/MediaTek/Ralink/TP-Link/etc.) ---"
  lsusb | grep -i -E 'wlan|wireless|wi-?fi|802\.11|realtek|ralink|mediatek|atheros|tp-link|ralink|0bda|2357|148f|0e8d' \
    || echo "No obvious Wi-Fi adapter in lsusb — check power/cable/port FIRST."
else
  echo "lsusb not installed (sudo apt install usbutils)"
fi

say "All network interfaces (ip link)"
ip -br link show

say "Wireless interfaces only (iw dev)"
if command -v iw >/dev/null; then
  out=$(iw dev 2>/dev/null)
  if [ -n "$out" ]; then echo "$out"; else echo "NONE — no wireless interface exists yet."; fi
else
  echo "iw not installed (sudo apt install iw)"
fi

say "NetworkManager device status"
command -v nmcli >/dev/null && nmcli device status || echo "nmcli not available"

say "Loaded Wi-Fi kernel modules"
lsmod | grep -i -E '8821|8812|8852|8188|8192|rtw|mt76|rt2800|cfg80211|rtl' || echo "(no Wi-Fi driver module loaded)"

say "Recent kernel messages about USB / Wi-Fi"
dmesg 2>/dev/null | grep -i -E 'usb [0-9].*(wlan|802\.11|realtek|mediatek)|firmware|wlan|cfg80211|rtw|mt76|rtl8|8821|8852' | tail -25 \
  || echo "(nothing — try: sudo dmesg)"

cat <<'EOF'

------------------------------------------------------------------
How to read this:

* Dongle NOT in lsusb        -> power/cable/port problem. Move it to a
                                direct Pi port, reseat, try another port.
* In lsusb but iw dev empty  -> no driver bound. Note the USB ID
                                (e.g. 2357:0141) and LOOK IT UP before
                                installing anything:
                                  - In-kernel chipset (MediaTek MT7601U/
                                    MT7610U/MT7612U, Ralink RT5370,
                                    Realtek RTL8188EU)  -> should just work;
                                    a missing driver here usually only needs
                                    `apt install firmware-misc-nonfree`.
                                  - Out-of-tree Realtek (RTL8811AU/8821AU/
                                    8821CU/8852AU) -> needs a DKMS driver that
                                    breaks on kernel upgrades. Strongly prefer
                                    swapping in an in-kernel dongle instead.
* Interface exists, not
  connected                  -> credentials/range. Run:
                                  sudo nmcli device wifi connect "SSID" password "PASS"
------------------------------------------------------------------
EOF
