# Deploying BirdCam from Windows (start to finish)

This walks you from a **blank SD card on a Windows PC** to **two live webcam
feeds on a web page**, assuming nothing is set up yet. No prior Raspberry Pi or
Linux experience required.

> You do **not** need VS Code or any developer tools on Windows. Everything you
> need is the free Raspberry Pi Imager plus the `ssh` command that ships with
> Windows 10/11. (If you *prefer* VS Code, see the optional note at the end.)

---

## Hardware checklist

- Raspberry Pi 2 Model B + its power supply
- microSD card (8 GB+) and a way to write to it from the PC (built-in slot or a
  USB adapter)
- Two USB webcams
- **A powered USB hub** (strongly recommended — two cameras can exceed the Pi's
  USB power budget)
- An **Ethernet cable** for setup (we deploy over Ethernet)
- A **USB Wi-Fi dongle** for "production" use — ⚠️ **the Pi 2 Model B has no
  built-in Wi-Fi**, so wireless needs a dongle plugged into a USB port

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
     pre-filling this means production Wi-Fi "just works" once the dongle is in.
   - **Set locale / time zone** as appropriate.
5. **Save**, then **Write**. Wait for it to finish and verify.

## Step 2 — First boot (over Ethernet)

1. Put the SD card in the Pi.
2. Plug in: **Ethernet cable**, the **powered USB hub**, and **both webcams into
   the hub**. (Skip the Wi-Fi dongle for now.)
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
git clone https://github.com/LarsCardon/BirdCam.git birdcam
cd birdcam
sudo ./install.sh
```

The installer checks you're on the Pi and online, installs everything, builds
uStreamer, auto-detects both cameras, and starts the services. It finishes by
printing the URL.

> Building uStreamer on a Pi 2 takes a few minutes — that's normal.

## Step 5 — Watch your cameras

From **any** device on the network (your Windows PC, phone, etc.) open:

```
http://birdcam.local/
```

Both feeds should appear. Done. 🎉

(If `.local` doesn't work on a viewing device, use `http://<pi-ip>/` — the same
IP from Step 3.)

---

## Step 6 — Switch to Wi-Fi for production

1. `sudo shutdown -h now` on the Pi, then unplug power.
2. Plug the **USB Wi-Fi dongle** into a free USB port.
3. Remove the Ethernet cable and power the Pi back on. It joins the Wi-Fi you
   pre-configured in Step 1.
4. **The IP address changes** when it moves from Ethernet to Wi-Fi. Use
   `http://birdcam.local/` (the hostname follows it across networks), or look up
   the new IP on your router.

### Wi-Fi performance tuning

Two video streams over Wi-Fi (especially through a USB dongle on a Pi 2) need
more headroom than wired. If feeds stutter on Wi-Fi, lower the load — edit each
camera config on the Pi:

```bash
sudo nano /etc/birdcam/cam1.conf     # and cam2.conf
```

Try `RESOLUTION=640x480` and/or `FPS=15`, then:

```bash
sudo systemctl restart ustreamer@cam1 ustreamer@cam2
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ssh: could not resolve hostname birdcam.local` | Use the Pi's IP from your router instead. |
| Installer says "not on the Pi" | You ran it on Windows. SSH into the Pi first (Step 3), then run it *there*. |
| Installer says "can't reach the internet" | Check the Ethernet cable / router; the Pi needs internet to install. |
| "Found 1 camera; expected 2" | Use a **powered** USB hub; reseat both cameras; re-run `sudo ./install.sh --reconfig`. |
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
