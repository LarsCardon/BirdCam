# Hardware & power notes

Background on *why* BirdCam is built the way it is, and the physical-setup
details that actually make or break it on a Raspberry Pi 2 Model B. Read this
before buying parts or debugging flaky feeds.

---

## Powering the cameras and Wi-Fi dongle (powered USB hub)

> **Running a single camera?** You can skip the hub. One webcam fits within the
> Pi's USB power budget, so plug it straight into a Pi port. The powered hub
> below matters once you add a **second** camera (or a Wi-Fi dongle alongside
> two cameras). BirdCam's installer auto-detects a single camera and configures
> for it; add the hub and a second camera later, then `sudo ./install.sh
> --reconfig`.

This is the single most important physical detail *for a two-camera setup*. Get
it wrong and you'll see random camera disconnects, corrupt frames, or Wi-Fi
dropouts — usually only under load, with no clear error.

### The core idea: two separate power sources

A **powered** (a.k.a. *self-powered* / *active*) USB hub has its **own AC power
adapter** that plugs into the wall. Your peripherals draw current from *that*
adapter — **not** from the Pi. The Pi only provides the **data** connection.

So you have two independent power feeds: the Pi runs on its own PSU, and the
peripherals run on the hub's adapter.

```
                                        ┌─────────────── Wall outlet #1
                                        │
                                  ┌─────┴─────┐
                                  │  Pi PSU   │  (5V, its own supply — powers the Pi only)
                                  └─────┬─────┘
                                        │ power
                                  ┌─────┴───────────┐
                                  │  Raspberry Pi 2 │
                                  └─────┬───────────┘
                                        │  ← ONE USB cable (DATA flows here)
                                        │     (upstream port of the hub)
                                  ┌─────┴───────────────────────┐
   Wall outlet #2 ───────────────┤   POWERED USB HUB            │
        │ (hub's own AC adapter)  │   (its adapter powers all   │
        └────────────────────────┤    the ports below)         │
                                  └──┬───────┬───────┬──────────┘
                                     │       │       │
                                 Camera 1  Camera 2  Wi-Fi dongle
                                 (power + data come through the hub)
```

The single USB cable from Pi → hub carries **data for all three devices**
(USB 2.0, 480 Mbps, shared — fine for MJPEG). The **power** for those devices
comes from the hub's wall adapter, so the Pi's limited USB power budget is no
longer the bottleneck.

### Why it's necessary (the numbers)

The Pi 2's USB ports can supply only roughly **~1.2 A total across all four
ports combined** (and only if the Pi's own PSU has headroom). Peak draw of the
peripherals:

| Device | Typical peak draw |
|---|---|
| LifeCam Cinema ×2 | ~0.5 A each → **~1.0 A** |
| USB Wi-Fi dongle | ~0.3–0.5 A (spikes on transmit) |
| **Total** | **~1.3–1.5 A peak** |

That exceeds what the Pi can safely deliver, which is exactly why a powered hub
is needed.

### Buying / wiring checklist

1. **It must be truly *powered*, with its adapter plugged in.** A "powered hub"
   running on bus power (adapter unplugged) is just a passive hub and helps
   nothing.
2. **Size the adapter with headroom:** 5 V and **at least 2 A, ideally 3–4 A** —
   covers ~1.5 A of devices plus inrush spikes.
3. **Prefer a hub with "backfeed / back-power protection."** Cheap hubs can push
   power *back up* the data cable into the Pi's 5 V rail, bypassing the Pi's
   safety fuse and causing odd behaviour (e.g. won't reboot/shut down cleanly).
   Keep the **Pi on its own PSU** and the **hub on its own adapter**; don't power
   the Pi *through* the hub unless it's specifically designed for that.

### Layout tip

Put the **two cameras on the hub** (they're the heavy, spiky loads). The **Wi-Fi
dongle** can go on the hub *or* directly into a Pi port — its draw alone won't
overload the Pi. If Wi-Fi feels flaky, move the dongle straight into the Pi or
onto a short USB extension a few cm away from the hub: USB 2.0 traffic can add
2.4 GHz noise that drags Wi-Fi performance down.

**Bottom line:** wall → hub adapter → hub powers the peripherals; Pi → one data
cable → hub; Pi keeps its own separate PSU. Two power sources, one data path.

---

## Why MJPEG passthrough (and not H.264 / WebRTC)

The LifeCam Cinema — like most UVC webcams — compresses video to **MJPEG in
hardware**. BirdCam exploits that: each uStreamer instance simply *relays* the
already-compressed frames to the browser. **No transcoding**, so CPU stays near
idle even with two streams on an old Pi, and a browser displays MJPEG with a
plain `<img>` tag — no plugins, no client-side JavaScript required.

H.264 or WebRTC would use less network bandwidth, but transcoding is heavy on a
Pi 2 and the setup is far more complex. For a LAN, **MJPEG is the right
trade-off**: trivial, low-latency, and the cameras already speak it natively.

---

## USB bandwidth (one shared bus)

All four USB ports on a Pi 2 share **one USB 2.0 bus (480 Mbps total)**. Two
MJPEG streams fit comfortably, but it's a shared budget — which is why the
**resolution / frame-rate knobs** in `/etc/birdcam/camN.conf` matter. If feeds
stutter, lowering one stream's `RESOLUTION` or `FPS` often smooths both, because
you're freeing shared bus (and, on Wi-Fi, shared radio) capacity.

Rough guidance:

| Setting | Use when |
|---|---|
| `1280x720` @ `30` | Wired/Ethernet, good light — the default |
| `1280x720` @ `15` | Wi-Fi production, or if 30 fps stutters |
| `640x480` @ `15` | Weak Wi-Fi, or a struggling Pi 2 |

Apply changes with `sudo systemctl restart ustreamer@cam1 ustreamer@cam2`.

---

## Networking notes (Pi 2 specifics)

- ⚠️ **The Pi 2 Model B has no built-in Wi-Fi.** Wireless requires a **USB Wi-Fi
  dongle**, which uses one USB port (still fine alongside two cameras). Deploy
  over **Ethernet**; switch to Wi-Fi for production.
- ⚠️ **On a Pi 2 the Ethernet port is itself a USB device** (`smsc95xx` on the
  internal hub). Two consequences: a misbehaving USB Wi-Fi driver can wedge the
  USB bus and take *wired* networking down with it; and a USB power/hub problem
  can disrupt Ethernet too. If Ethernet dies right after a Wi-Fi change, suspect
  the Wi-Fi driver/USB, not the network config.
- **The dongle chipset is everything — buy by chipset, not brand.** Vendors
  silently swap chipsets between hardware revisions (e.g. a "TP-Link Archer T2U
  Nano" can be an in-kernel RTL8811AU on one revision and a poorly-supported
  Wi-Fi 6 RTL8852AU on another). Always check the **USB ID** (`lsusb`) and look
  up the real chipset.
  - **Strongly prefer in-kernel chipsets** — they work the instant you plug them
    in, need no DKMS, and survive kernel upgrades: **MediaTek MT7601U** (Wi-Fi N,
    cheapest reliable), **Ralink RT5370** (Wi-Fi N), **Realtek RTL8188EU**
    (Wi-Fi N), or **MediaTek MT7610U/MT7612U** (Wi-Fi AC). A Pi 2's USB 2.0 bus
    can't push much, so even Wi-Fi N is plenty for camera streams.
  - **Avoid out-of-tree Realtek** (`RTL8811AU/8821AU/8821CU/8852AU`): they need a
    DKMS driver that **breaks on every kernel upgrade** and must be matched to the
    exact chip variant. See the dongle box in Step 6 of
    [DEPLOY-FROM-WINDOWS.md](DEPLOY-FROM-WINDOWS.md) for the full decision tree,
    the kernel-pinning workaround, and `scripts/wifi-check.sh`.
  - Always **verify the dongle connects while Ethernet is still attached** before
    cutting the cable.
- ⚠️ **Shut down cleanly — always `sudo shutdown -h now`, then wait for the green
  ACT LED to stop before pulling power.** The Pi 2's SD card corrupts easily on an
  abrupt power loss, which can leave it unable to boot or reach the network at
  all. If that happens, re-flashing and re-running the installer is the quickest
  recovery (the whole setup lives in this repo).
- **The IP changes when the Pi moves between Ethernet and Wi-Fi.** Rely on the
  hostname **`birdcam.local`** (mDNS), which follows the Pi across networks, or
  look the new IP up on your router.
- **`.local` not resolving?** Modern Windows resolves mDNS out of the box, but
  some networks block it — fall back to the Pi's IP from the router's
  "connected devices" list.

---

## Software gotchas worth knowing

- **`libjpeg` dev package name varies by OS version.** The installer tries
  `libjpeg-dev` then falls back to `libjpeg62-turbo-dev` automatically, so the
  uStreamer build works across Raspberry Pi OS releases.
- **Stable camera identity.** Cameras are bound by `/dev/v4l/by-path/...` (the
  physical USB port), not `/dev/videoN` (which can reorder between boots). Keep
  each camera in its port and the cam1/cam2 mapping survives reboots. If you swap
  ports, re-run `sudo ./install.sh --reconfig`.

---

See also: **[DEPLOY-FROM-WINDOWS.md](DEPLOY-FROM-WINDOWS.md)** for the full
flash-to-live-feeds walkthrough, and the [README](../README.md) for the
architecture overview.
