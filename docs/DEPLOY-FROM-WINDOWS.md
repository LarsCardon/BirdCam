# Deploying BirdCam from Windows (start to finish)

This walks you from a **blank SD card on a Windows PC** to **live webcam feeds
on a web page**, assuming nothing is set up yet. No prior Raspberry Pi or Linux
experience required.

> **Just one camera (no USB hub yet)?** That works — the installer auto-detects
> a single camera and sets everything up for it. A single camera plugs straight
> into the Pi; the powered USB hub is only needed for two. Wherever this guide
> says "two cameras" or "the hub," do the one-camera equivalent and read on.

> You do **not** need VS Code or any developer tools on Windows. Everything you
> need is the free Raspberry Pi Imager plus the `ssh` command that ships with
> Windows 10/11. (If you *prefer* VS Code, see the optional note at the end.)

---

## Hardware checklist

- Raspberry Pi 2 Model B + its power supply
- microSD card (8 GB+) and a way to write to it from the PC (built-in slot or a
  USB adapter)
- One or two USB webcams
- **A powered USB hub** (strongly recommended *for two cameras* — they can
  exceed the Pi's USB power budget; not needed for a single camera)
- An **Ethernet cable** for setup (we deploy over Ethernet)
- A **USB Wi-Fi dongle** for "production" use — ⚠️ **the Pi 2 Model B has no
  built-in Wi-Fi**, so wireless needs a dongle plugged into a USB port.
  **Buy by chipset, not brand** (see the dongle box in Step 6): pick one with an
  **in-kernel driver** (e.g. MediaTek **MT7601U** for Wi-Fi N, or **MT7610U/
  MT7612U** for Wi-Fi AC) so it works the moment you plug it in. **Avoid** Realtek
  `RTL8811AU/8821AU/8821CU/8852AU`-class sticks — they need fragile out-of-tree
  drivers that break on every kernel update.

---

## Step 1 — Flash Raspberry Pi OS with Raspberry Pi Imager

1. On Windows, install **Raspberry Pi Imager**: <https://www.raspberrypi.com/software/>
2. Insert the microSD card.
3. Open Imager and choose:
   - **Device:** Raspberry Pi 2
   - **Operating System:** *Raspberry Pi OS (other)* → **Raspberry Pi OS Lite
     (32-bit)**. (Lite = no desktop; the Pi 2 runs 32-bit.)
   - **Storage:** your SD card
4. Click **Next**, then **Edit Settings** (the "OS customisation" dialog). This
   is the part that makes the rest hands-off — fill in:
   - **Set hostname:** `birdcam`  → the Pi will be reachable as `birdcam.local`
   - **Enable SSH** → *Use password authentication* and set a username
     (e.g. `pi`) and password. **Write these down.**
   - **Configure wireless LAN:** enter your home Wi-Fi **SSID + password** and
     set your **Wi-Fi country** (e.g. `SE`). We deploy over Ethernet, but
     pre-filling this means production Wi-Fi connects automatically *once a
     **supported** dongle is recognized* — see Step 6 for how to confirm yours
     is supported before you rely on it.
   - **Set locale / time zone** as appropriate.
5. **Save**, then **Write**. Wait for it to finish and verify.

## Step 2 — First boot (over Ethernet)

1. Put the SD card in the Pi.
2. Plug in the **Ethernet cable** and your camera(s). For two cameras, use the
   **powered USB hub** and plug **both webcams into the hub**; for one camera,
   plug it straight into a Pi USB port. (Skip the Wi-Fi dongle for now.)
3. Power on the Pi. Give it **~60–90 seconds** to boot the first time.

## Step 3 — Connect from Windows over SSH

1. Open **Windows Terminal** or **PowerShell** (Start menu → type "PowerShell").
2. Connect using the hostname you set:
   ```powershell
   ssh pi@birdcam.local
   ```
   (Replace `pi` if you chose a different username.)
   - The first time, it asks to trust the host — type `yes`.
   - Enter the password from Step 1.
   - **If `birdcam.local` doesn't resolve:** find the Pi's IP from your router's
     "connected devices" page (look for `birdcam`) and use that instead, e.g.
     `ssh pi@192.168.1.42`. Modern Windows resolves `.local` out of the box, but
     some networks block mDNS.

You're now on the Pi. The prompt changes to something like `pi@birdcam:~ $`.

## Step 4 — Get the code and install

The repo is public, so this needs no login. On the Pi:

```bash
sudo apt update
sudo apt install -y git    # Raspberry Pi OS Lite doesn't ship with git
git clone https://github.com/LarsCardon/BirdCam.git birdcam
cd birdcam
sudo ./install.sh
```

> If `git clone` reports a certificate "not yet valid" / date error, the Pi 2
> has no battery clock — wait ~30 s after boot for it to sync time, then retry.

The installer checks you're on the Pi and online, installs everything, builds
uStreamer, auto-detects your camera(s), and starts the services. It finishes by
printing the URL.

> Building uStreamer on a Pi 2 takes a few minutes — that's normal.
>
> **Want to force a single camera** even if two are connected? Run
> `sudo ./install.sh --cameras 1` instead.

## Step 5 — Watch your cameras

From **any** device on the network (your Windows PC, phone, etc.) open:

```
http://birdcam.local/
```

Your feed(s) should appear. Done. 🎉

(If `.local` doesn't work on a viewing device, use `http://<pi-ip>/` — the same
IP from Step 3.)

---

## Step 6 — Switch to Wi-Fi for production

The Wi-Fi **credentials** you entered in Step 1 are already saved on the Pi.
They apply to whatever wireless interface exists — so the moment a *supported*
dongle is recognized as `wlan0`, the Pi connects automatically. The steps below
plug it in and **verify** that actually happened (don't assume — the dongle's
chipset is the #1 surprise here, and a "Wi-Fi dongle that doesn't work" is by far
the most time-consuming thing that can go wrong in this whole guide).

> **⚠️ Always shut down cleanly.** On a Pi 2 the SD card's filesystem corrupts
> easily if you pull power while it's running — which can leave it unable to boot
> *or even bring up Ethernet* on the next start. Every time: run
> `sudo shutdown -h now`, wait for the green **ACT** LED to stop blinking, *then*
> unplug power. (Note: on a Pi 2 the Ethernet port is itself a USB device, so a
> bad shutdown — or a misbehaving USB Wi-Fi driver — can take wired networking
> down too.)

> **Run the built-in checker.** Once you've cloned the repo (Step 4), the fastest
> way to see exactly which layer is failing is:
> ```bash
> bash ~/birdcam/scripts/wifi-check.sh
> ```
> It prints the dongle's USB ID + chipset hint, whether an interface exists, and
> whether it's connected — and tells you what each result means.

1. `sudo shutdown -h now` on the Pi, then unplug power.
2. Plug the **USB Wi-Fi dongle** into a free USB port.
3. Power the Pi back on **with Ethernet still attached** for now — that gives you
   a guaranteed way back in to check the dongle before you cut the cable.
4. SSH in (`ssh pi@birdcam.local`) and confirm the dongle is recognized and
   connected:
   ```bash
   lsusb                       # is the dongle even on the USB bus? note its ID, e.g. 2357:0141
   ip link show wlan0          # should list a wlan0 interface
   iw dev                      # lists ONLY wireless interfaces — empty = no driver bound
   nmcli device status         # wlan0 should say "connected" to your SSID
   ip -4 addr show wlan0       # should show an IP once connected
   ```
   (or just `bash ~/birdcam/scripts/wifi-check.sh`, which runs all of these and
   interprets them.)
   - **Dongle not in `lsusb`?** Power/cable/port problem — move it to a direct Pi
     port and reseat it, *before* touching any software.
   - **In `lsusb` but no `wlan0` / `iw dev` empty?** The kernel has no driver bound
     to it — see the troubleshooting box below. **Note the USB ID and look it up
     now**, before installing anything.
   - **`wlan0` exists but not connected?** Connect it manually (this also re-saves
     the credentials):
     ```bash
     sudo nmcli device wifi connect "YOUR_SSID" password "YOUR_PASSWORD"
     ```
     The friendly alternative is `sudo raspi-config` → *System Options* →
     *Wireless LAN*, which walks you through SSID + password.
5. Once `wlan0` shows "connected" with an IP, shut down, **remove the Ethernet
   cable**, and power back on. The Pi now runs on Wi-Fi alone.
6. **The IP address changes** when it moves from Ethernet to Wi-Fi. Use
   `http://birdcam.local/` (the hostname follows it across networks), or look up
   the new IP on your router.

> **Dongle in `lsusb` but no `wlan0`? Work out *why* before installing anything.**
> First, **identify the chipset** — search the web for your exact USB ID (the
> `lsusb` value such as `2357:0141`). The fix depends entirely on which of three
> cases you're in:
>
> **Case A — in-kernel chipset, just needs firmware.** If it's a MediaTek
> (MT7601U/MT7610U/MT7612U), Ralink (RT5370), or Realtek **RTL8188EU**, the driver
> ships with the kernel and it usually only needs a firmware blob. With Ethernet
> attached:
> ```bash
> dmesg | grep -i -E 'firmware|wlan|80211'       # look for "firmware load failed"
> sudo apt update && sudo apt install -y firmware-misc-nonfree firmware-realtek firmware-atheros
> sudo reboot
> ```
>
> **Case B — out-of-tree Realtek (RTL8811AU/8821AU/8821CU/8852AU, etc.).** These
> have **no in-kernel driver** and need a DKMS driver (e.g. the `morrownr`
> repos). It can be made to work, but be warned this is a rabbit hole:
> - You must install kernel headers (`sudo apt install -y bc dkms build-essential linux-headers-$(uname -r)`)
>   and build the driver — slow on a Pi 2.
> - **It breaks on every kernel upgrade.** If `apt` pulls a newer kernel, the
>   module no longer matches (`iw dev` goes empty again). Rebuild with
>   `sudo apt install -y linux-headers-$(uname -r) && sudo dkms autoinstall`, and
>   consider pinning the kernel: `sudo apt-mark hold` the `linux-image-*` /
>   `linux-headers-*` packages.
> - **Match the driver to the exact chip.** `RTL8811CU/8821CU` use the `8821cu`
>   driver, *not* `8821au`; Wi-Fi 6 `RTL8852AU/8832AU` use `rtl8852au`/`rtw89`.
>   Installing the wrong one builds fine but never binds (no `wlan0`). Check the
>   driver actually lists your USB ID: `modinfo <module> | grep <vendorid>`.
> - **Honestly: don't.** A Pi 2's USB 2.0 bus can't use Wi-Fi 6 speeds anyway.
>   The reliable fix is to swap in an in-kernel dongle (next case).
>
> **Case C — the right answer: use a dongle with an in-kernel driver.** It works
> the instant you plug it in, needs no DKMS, and survives kernel upgrades. Buy by
> **chipset, not brand** (vendors silently swap chipsets between hardware
> revisions). Known-good, widely available:
>
> | Chipset | Type | Example models | Notes |
> |---|---|---|---|
> | **MediaTek MT7601U** | Wi-Fi 4 (N150) | EDUP MS8551, many "nano" sticks | Cheapest reliable option (~€8–12); plenty for a Pi 2 |
> | **Ralink RT5370** | Wi-Fi 4 (N150) | Panda PAU03/PAU05 | "It just works"; common |
> | **Realtek RTL8188EU** | Wi-Fi 4 (N150) | TP-Link TL-WN725N **v2/v3**, Edimax EW-7811Un v2 | In-kernel since modern kernels; cheap |
> | **MediaTek MT7610U** | Wi-Fi 5 (AC600) | various AC600 "nano" sticks | Dual-band; verify the chipset before buying |
> | **MediaTek MT7612U** | Wi-Fi 5 (AC1200) | PIX-LINK LV-UAC04 (~€11), Panda PAU0D, Alfa AWUS036ACM | Most headroom; pricier |
>
> When ordering, look for the chipset **in the listing or reviews** (Linux users
> usually mention it), and prefer sellers/revisions that state it. Avoid generic
> AliExpress sticks that don't name a chipset — they're a coin flip.


### Wi-Fi performance tuning

Video over Wi-Fi (especially through a USB dongle on a Pi 2) needs more headroom
than wired — and two streams more than one. If feeds stutter on Wi-Fi, lower the
load — edit each camera config on the Pi:

```bash
sudo nano /etc/birdcam/cam1.conf     # and cam2.conf if you have two cameras
```

Try `RESOLUTION=640x480` and/or `FPS=15`, then restart that camera (add
`ustreamer@cam2` if you have two):

```bash
sudo systemctl restart ustreamer@cam1
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ssh: could not resolve hostname birdcam.local` | Use the Pi's IP from your router instead. |
| Pi won't boot / no Ethernet **after a power cut** (not on the router at all) | Likely SD-card filesystem corruption from pulling power without `sudo shutdown -h now`. Put the card in your PC: the boot/FAT partition should still mount. Easiest recovery is to **re-flash** (Step 1) and re-run the installer — your setup is fully reproducible from this repo. Always shut down cleanly to avoid this. |
| Wi-Fi dongle shows in `lsusb` but there's no `wlan0` | The kernel has no driver bound. Identify the chipset from the USB ID and follow the dongle box in **Step 6** — most often the real fix is a dongle with an in-kernel driver. |
| `git clone` fails with a certificate "not yet valid" / date error | The Pi 2 has no battery clock; on first boot it briefly has the wrong time. Wait ~30 s after boot for it to sync over the network, then retry. |
| Installer says "not on the Pi" | You ran it on Windows. SSH into the Pi first (Step 3), then run it *there*. |
| Installer says "can't reach the internet" | Check the Ethernet cable / router; the Pi needs internet to install. |
| Want two cameras but only one shows up | The installer set up for one camera. Use a **powered** USB hub, plug in both, then re-run `sudo ./install.sh --reconfig` (or `--cameras 2`). |
| Set up one camera, now adding a second | Plug both in via a powered hub, then `sudo ./install.sh --reconfig`. |
| Page loads but a feed is black/red dot | `journalctl -u ustreamer@cam1 -f` on the Pi to see why; often a power/bandwidth issue → powered hub + lower resolution. |
| Cameras swapped (cam1 shows the wrong view) | Swap which port each camera is in, or rerun `sudo ./install.sh --reconfig`. |

Useful commands on the Pi:

```bash
sudo birdcam-detect                        # list detected cameras
systemctl status ustreamer@cam1 ustreamer@cam2 nginx
journalctl -u ustreamer@cam1 -f            # live log for cam1
```

---

## Optional: VS Code instead of plain SSH

If you'd rather use VS Code on Windows: install the **Remote - SSH** extension,
run *Remote-SSH: Connect to Host…*, enter `pi@birdcam.local`, and you get a full
editor + integrated terminal **on the Pi**. Then run Steps 4–5 in that terminal.
It's a nicer experience but entirely optional — the `ssh` route above is enough.
