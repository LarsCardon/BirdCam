#!/usr/bin/env bash
#
# BirdCam installer — sets up two-camera MJPEG streaming on a Raspberry Pi.
# Run on the Pi as root:  sudo ./install.sh   (add --reconfig to only
# re-detect cameras and rewrite the per-camera conf files).
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USTREAMER_REPO="https://github.com/pikvm/ustreamer"
USTREAMER_SRC="/opt/ustreamer"
CONF_DIR="/etc/birdcam"
WEB_DIR="/var/www/birdcam"
RECONFIG=0

[[ "${1:-}" == "--reconfig" ]] && RECONFIG=1

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Please run as root (sudo ./install.sh)."

# --- Preflight: confirm we're on the Pi, not the Windows PC ---------------
preflight() {
    if [[ "$(uname -s)" != "Linux" ]] || ! command -v apt-get >/dev/null; then
        die "This installer runs ON the Raspberry Pi (Raspberry Pi OS / Debian).
     It looks like you're not on the Pi. SSH into the Pi first, then run it there."
    fi
    log "Checking internet access (needed to install packages and build uStreamer)..."
    if ! ping -c1 -W3 github.com >/dev/null 2>&1 && ! ping -c1 -W3 deb.debian.org >/dev/null 2>&1; then
        die "Can't reach the internet from the Pi. Connect Ethernet (or Wi-Fi) and retry."
    fi
}

# --- Detect cameras and write per-camera config --------------------------
configure_cameras() {
    log "Detecting cameras..."
    python3 "$REPO_DIR/scripts/detect_cameras.py" || true

    mapfile -t PATHS < <(python3 "$REPO_DIR/scripts/detect_cameras.py" --paths-only)
    if [[ ${#PATHS[@]} -lt 2 ]]; then
        warn "Found ${#PATHS[@]} camera(s); expected 2."
        warn "Check connections / powered USB hub, then re-run: sudo ./install.sh --reconfig"
        [[ ${#PATHS[@]} -eq 0 ]] && die "No cameras detected — aborting."
    fi

    mkdir -p "$CONF_DIR"
    local i port
    for i in 1 2; do
        port=$((8080 + i))
        local dev="${PATHS[$((i - 1))]:-/dev/video$((($i - 1) * 2))}"
        cat > "$CONF_DIR/cam${i}.conf" <<EOF
# uStreamer settings for cam${i} (managed by BirdCam install.sh).
# DEVICE is a stable by-path device tied to the physical USB port.
DEVICE=${dev}
PORT=${port}
RESOLUTION=1280x720
FORMAT=MJPEG
FPS=30
EOF
        log "Wrote $CONF_DIR/cam${i}.conf -> ${dev} (port ${port})"
    done
}

if [[ $RECONFIG -eq 1 ]]; then
    configure_cameras
    systemctl restart ustreamer@cam1 ustreamer@cam2 || true
    log "Reconfigured. Done."
    exit 0
fi

# --- Dependencies ---------------------------------------------------------
preflight

log "Installing dependencies..."
apt-get update
apt-get install -y \
    git build-essential pkg-config \
    libevent-dev libbsd-dev \
    nginx v4l-utils python3
# The libjpeg development package is named differently across Raspberry Pi OS
# versions; try the modern name, then the older one.
apt-get install -y libjpeg-dev \
    || apt-get install -y libjpeg62-turbo-dev \
    || die "Could not install a libjpeg development package (tried libjpeg-dev and libjpeg62-turbo-dev)."

# --- Build uStreamer ------------------------------------------------------
if [[ ! -x /usr/local/bin/ustreamer ]]; then
    log "Building uStreamer..."
    if [[ -d "$USTREAMER_SRC/.git" ]]; then
        git -C "$USTREAMER_SRC" pull --ff-only || true
    else
        rm -rf "$USTREAMER_SRC"
        git clone --depth=1 "$USTREAMER_REPO" "$USTREAMER_SRC"
    fi
    make -C "$USTREAMER_SRC" -j"$(nproc)"
    install -m 0755 "$USTREAMER_SRC/ustreamer" /usr/local/bin/ustreamer
    log "Installed $(/usr/local/bin/ustreamer --version 2>&1 | head -n1 || echo ustreamer)"
else
    log "uStreamer already installed, skipping build."
fi

# --- Cameras --------------------------------------------------------------
configure_cameras

# --- systemd service ------------------------------------------------------
log "Installing systemd service..."
install -m 0644 "$REPO_DIR/systemd/ustreamer@.service" /etc/systemd/system/ustreamer@.service
systemctl daemon-reload
systemctl enable ustreamer@cam1 ustreamer@cam2
systemctl restart ustreamer@cam1 ustreamer@cam2

# --- Web page -------------------------------------------------------------
log "Installing web page..."
mkdir -p "$WEB_DIR"
install -m 0644 "$REPO_DIR/web/index.html" "$WEB_DIR/index.html"

# --- nginx ----------------------------------------------------------------
log "Configuring nginx..."
install -m 0644 "$REPO_DIR/nginx/birdcam.conf" /etc/nginx/sites-available/birdcam.conf
ln -sf /etc/nginx/sites-available/birdcam.conf /etc/nginx/sites-enabled/birdcam.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl restart nginx

# --- Install the detect helper for later reconfiguration ------------------
install -m 0755 "$REPO_DIR/scripts/detect_cameras.py" /usr/local/bin/birdcam-detect

# --- Done -----------------------------------------------------------------
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
HOST="$(hostname).local"
echo
log "BirdCam is up. Open it from any device on your network:"
echo "      http://${IP:-<pi-ip>}/"
echo "      http://${HOST}/   (if mDNS/Bonjour is available)"
echo
log "Status:  systemctl status ustreamer@cam1 ustreamer@cam2 nginx"
