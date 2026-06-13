# BirdCam

Stream two USB webcams from a Raspberry Pi to a single web page on your local
network. Plug in the cameras, power on the Pi, and both live feeds appear at
`http://<pi-address>/`.

Built and tested against a **Raspberry Pi 2 Model B** with two **Microsoft
LifeCam Cinema** webcams, but it works with any UVC webcam that can output
**MJPEG** (which is almost all of them).

## Documentation

* **[docs/DEPLOY-FROM-WINDOWS.md](docs/DEPLOY-FROM-WINDOWS.md)** — full
  walkthrough from a blank SD card on a Windows PC to live feeds.
* **[docs/HARDWARE.md](docs/HARDWARE.md)** — powered-USB-hub wiring, power
  budget, USB bandwidth, MJPEG rationale, and Pi-2 networking notes.

## How it works

```
LifeCam #1 ──USB──┐                         ┌── uStreamer :8081 ──┐
                  ├── Raspberry Pi ─────────┤                     ├── nginx :80 ── browser
LifeCam #2 ──USB──┘                         └── uStreamer :8082 ──┘
```

* Each webcam compresses video to **MJPEG in hardware**. The Pi just *relays*
  those already-compressed frames — no transcoding, almost no CPU.
* One **uStreamer** process per camera serves an MJPEG stream on a localhost
  port (`8081`, `8082`).
* **nginx** serves the web page on port 80 and reverse-proxies the two streams
  under `/cam1/` and `/cam2/`, so the page is single-origin and works no matter
  what IP or hostname the Pi has.
* **systemd** starts everything on boot and restarts anything that dies.

The browser shows MJPEG with a plain `<img>` tag — no plugins, no JavaScript
required to view.

## What you need

* Raspberry Pi (2 Model B or better recommended) running **Raspberry Pi OS**
  (Lite is fine — no desktop needed).
* Two UVC / MJPEG USB webcams.
* **A powered USB hub is strongly recommended.** Two webcams can exceed the
  Pi's USB power budget, and all four USB ports share a single bus — a powered
  hub avoids brown-outs and bandwidth starvation. See
  **[docs/HARDWARE.md](docs/HARDWARE.md)** for exactly how to wire and size it.
* The Pi connected to your network (Ethernet or Wi-Fi). ⚠️ **The Pi 2 Model B
  has no built-in Wi-Fi** — wireless requires a USB Wi-Fi dongle. Ethernet is
  the easy path for setup.

## Install

> **First time, from a Windows PC and a blank SD card?** Follow the complete
> step-by-step guide: **[docs/DEPLOY-FROM-WINDOWS.md](docs/DEPLOY-FROM-WINDOWS.md)**.
> It covers flashing the SD card, finding and SSHing into the Pi, and everything
> below — no prior Linux experience needed.

Once you have Raspberry Pi OS running and can SSH in, run these **on the Pi**:

```bash
git clone https://github.com/LarsCardon/BirdCam.git birdcam
cd birdcam
sudo ./install.sh
```

The installer will:

1. Install dependencies (`nginx`, `v4l-utils`, build tools).
2. Build and install uStreamer.
3. Detect your two cameras and write `/etc/birdcam/cam1.conf` and
   `/etc/birdcam/cam2.conf` pointing at their stable USB-port device paths.
4. Install the systemd services, web page, and nginx config.
5. Enable and start everything.

When it finishes it prints the URL to open. From any device on the LAN:

```
http://<pi-ip-or-hostname>/
```

(e.g. `http://raspberrypi.local/`).

## Configuration

Per-camera settings live in `/etc/birdcam/cam1.conf` and
`/etc/birdcam/cam2.conf`:

```ini
DEVICE=/dev/v4l/by-path/...-video-index0   # stable, tied to the physical port
PORT=8081
RESOLUTION=1280x720
FORMAT=MJPEG
FPS=30
```

After editing, restart the affected camera:

```bash
sudo systemctl restart ustreamer@cam1
```

### Tuning tips

* **Choppy or laggy?** Lower the resolution (`640x480`) or frame rate
  (`FPS=15`). Two 720p30 MJPEG streams share one USB 2.0 bus, so dropping one
  setting often smooths both.
* **`DEVICE` paths** use `/dev/v4l/by-path/`, which is tied to the *physical USB
  port*. As long as you don't move a camera to a different port, the mapping
  survives reboots. If you do rearrange them, re-run detection:
  ```bash
  sudo birdcam-detect          # show detected cameras
  sudo ./install.sh --reconfig # re-detect and rewrite the conf files
  ```

## Managing the services

```bash
systemctl status ustreamer@cam1 ustreamer@cam2   # health
journalctl -u ustreamer@cam1 -f                  # live logs for cam1
sudo systemctl restart nginx                      # reload web/proxy layer
```

Direct (un-proxied) stream URLs for debugging, from the Pi itself:
`http://127.0.0.1:8081/stream` and `http://127.0.0.1:8082/stream`.

## Uninstall

```bash
sudo ./uninstall.sh
```

## Scope / non-goals

Deliberately kept to "two live feeds on the LAN." Not included (each would be a
separate, optional layer): recording, motion detection, authentication,
HTTPS, or exposure to the public internet. Don't port-forward this as-is.
