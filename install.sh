#!/usr/bin/env bash
#
# BirdCam installer — sets up MJPEG streaming for one or two USB webcams on a
# Raspberry Pi. Run on the Pi as root:
#
#   sudo ./install.sh                 # auto-detect 1 or 2 cameras and set up
#   sudo ./install.sh --cameras 1     # force a single-camera setup
#   sudo ./install.sh --cameras 2     # force a two-camera setup
#   sudo ./install.sh --reconfig      # re-detect cameras + rewrite config only
#
# --cameras and --reconfig can be combined, e.g. once you add a second camera:
#   sudo ./install.sh --reconfig --cameras 2
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USTREAMER_REPO="https://github.com/pikvm/ustreamer"
USTREAMER_SRC="/opt/ustreamer"
CONF_DIR="/etc/birdcam"
WEB_DIR="/var/www/birdcam"
MAX_CAMERAS=2          # ports 8081/8082 and the 2-column web grid cap us at 2
RECONFIG=0
CAMERAS=0                              # resolved later (requested or detected)
REQUESTED_CAMERAS="${BIRDCAM_CAMERAS:-}"  # empty = auto-detect

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reconfig)   RECONFIG=1 ;;
        --cameras)    shift; REQUESTED_CAMERAS="${1:-}" ;;
        --cameras=*)  REQUESTED_CAMERAS="${1#*=}" ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "Unknown option: $1 (try --help)" ;;
    esac
    shift
done

if [[ -n "$REQUESTED_CAMERAS" ]]; then
    [[ "$REQUESTED_CAMERAS" =~ ^[1-9][0-9]*$ ]] \
        || die "--cameras takes a number (1 or 2), got: $REQUESTED_CAMERAS"
    (( REQUESTED_CAMERAS >= 1 && REQUESTED_CAMERAS <= MAX_CAMERAS )) \
        || die "--cameras must be between 1 and $MAX_CAMERAS."
fi

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
    log "Detecting cameras and their supported MJPEG modes..."
    python3 "$REPO_DIR/scripts/detect_cameras.py" || true

    # Each line: "<device>\t<WxH>\t<fps>" — resolution/fps are auto-selected to
    # a mode the camera actually supports, so uStreamer always starts cleanly.
    mapfile -t CAMS < <(python3 "$REPO_DIR/scripts/detect_cameras.py" --config)
    local detected=${#CAMS[@]}
    [[ $detected -eq 0 ]] && die "No cameras detected — connect a camera and retry."

    # Decide how many cameras to configure: an explicit --cameras wins;
    # otherwise use however many were detected (capped at MAX_CAMERAS).
    if [[ -n "$REQUESTED_CAMERAS" ]]; then
        CAMERAS=$REQUESTED_CAMERAS
        if [[ $detected -lt $CAMERAS ]]; then
            warn "Requested $CAMERAS camera(s) but only detected $detected."
            warn "Configuring $CAMERAS anyway and writing a placeholder for the missing one."
            warn "Use a powered USB hub, reseat the camera, then: sudo ./install.sh --reconfig"
        fi
    else
        CAMERAS=$(( detected < MAX_CAMERAS ? detected : MAX_CAMERAS ))
        if [[ $CAMERAS -eq 1 ]]; then
            log "Detected 1 camera; configuring BirdCam for a single camera."
            log "Adding a second later? Plug it in, then: sudo ./install.sh --reconfig"
        fi
    fi

    mkdir -p "$CONF_DIR"
    # Record the camera count so --reconfig, nginx, and the web page agree.
    printf 'CAMERAS=%s\n' "$CAMERAS" > "$CONF_DIR/birdcam.conf"

    local i port dev res fps
    for i in $(seq 1 "$CAMERAS"); do
        port=$((8080 + i))
        if [[ -n "${CAMS[$((i - 1))]:-}" ]]; then
            IFS=$'\t' read -r dev res fps <<<"${CAMS[$((i - 1))]}"
        else
            # Requested more cameras than detected; write a placeholder so a
            # later --reconfig fills it in once the camera is connected.
            dev="/dev/video$((($i - 1) * 2))"; res="1280x720"; fps="30"
        fi
        cat > "$CONF_DIR/cam${i}.conf" <<EOF
# uStreamer settings for cam${i} (managed by BirdCam install.sh).
# DEVICE is a stable by-path device tied to the physical USB port.
# RESOLUTION/FPS were auto-selected from what the camera reported; edit freely.
DEVICE=${dev}
PORT=${port}
RESOLUTION=${res}
FORMAT=MJPEG
FPS=${fps}
EOF
        log "Wrote $CONF_DIR/cam${i}.conf -> ${dev}  ${res}@${fps} fps  (port ${port})"
    done
}

# --- Enable the right services for the chosen camera count ----------------
# Enable/start cam1..CAMERAS; disable/stop any beyond that (e.g. dropping from
# two cameras back to one), so stale instances don't linger.
apply_camera_services() {
    local i
    for i in $(seq 1 "$MAX_CAMERAS"); do
        if [[ $i -le $CAMERAS ]]; then
            systemctl enable "ustreamer@cam$i" >/dev/null 2>&1 || true
            systemctl restart "ustreamer@cam$i" || true
        else
            systemctl disable --now "ustreamer@cam$i" >/dev/null 2>&1 || true
        fi
    done
}

# --- Generate the nginx config with one proxy block per camera ------------
# nginx/birdcam.conf is a template; its @@CAM_LOCATIONS@@ marker is replaced
# with a reverse-proxy block for each configured camera.
gen_nginx() {
    local i port blocks="" nl=$'\n'
    for i in $(seq 1 "$CAMERAS"); do
        port=$((8080 + i))
        blocks+="    # Buffering MUST be off so the multipart/x-mixed-replace MJPEG${nl}"
        blocks+="    # stream is passed through frame-by-frame instead of buffered.${nl}"
        blocks+="    location /cam${i}/ {${nl}"
        blocks+="        proxy_pass http://127.0.0.1:${port}/;${nl}"
        blocks+="        proxy_buffering off;${nl}"
        blocks+="        proxy_request_buffering off;${nl}"
        blocks+="        proxy_http_version 1.1;${nl}"
        blocks+="        proxy_set_header Connection \"\";${nl}"
        blocks+="        chunked_transfer_encoding off;${nl}"
        blocks+="        proxy_read_timeout 3600s;   # long-lived MJPEG stream; don't time out${nl}"
        blocks+="    }${nl}"
        [[ $i -lt $CAMERAS ]] && blocks+="${nl}"
    done
    awk -v blocks="$blocks" \
        '/^[[:space:]]*@@CAM_LOCATIONS@@[[:space:]]*$/{printf "%s", blocks; next} {print}' \
        "$REPO_DIR/nginx/birdcam.conf" > /etc/nginx/sites-available/birdcam.conf
}

# --- Generate the web page for the chosen camera count --------------------
# web/index.html ships with CAM_COUNT defaulting to 2; rewrite it to match.
gen_web() {
    mkdir -p "$WEB_DIR"
    sed "s/const CAM_COUNT = [0-9]\+;/const CAM_COUNT = ${CAMERAS};/" \
        "$REPO_DIR/web/index.html" > "$WEB_DIR/index.html"
}

if [[ $RECONFIG -eq 1 ]]; then
    # Free the cameras so detection can probe them, then bring services back.
    systemctl stop ustreamer@cam1 ustreamer@cam2 2>/dev/null || true
    configure_cameras
    apply_camera_services
    log "Regenerating web page and nginx config for $CAMERAS camera(s)..."
    gen_web
    gen_nginx
    nginx -t && systemctl reload nginx || warn "nginx reload skipped (config test failed)."
    log "Reconfigured for $CAMERAS camera(s). Done."
    exit 0
fi

# --- Dependencies ---------------------------------------------------------
preflight

log "Installing dependencies..."
apt-get update
apt-get install -y \
    git build-essential pkg-config \
    libevent-dev libbsd-dev \
    nginx v4l-utils python3 \
    avahi-daemon
# avahi-daemon makes the Pi reachable as <hostname>.local (e.g. birdcam.local)
# so viewers don't need to chase the IP address.
systemctl enable --now avahi-daemon 2>/dev/null || true
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
apply_camera_services

# --- Web page -------------------------------------------------------------
log "Installing web page ($CAMERAS camera(s))..."
gen_web

# --- nginx ----------------------------------------------------------------
log "Configuring nginx..."
gen_nginx
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
# Build "ustreamer@cam1 ustreamer@cam2 ..." for the configured cameras.
SERVICES=""
for i in $(seq 1 "$CAMERAS"); do SERVICES+="ustreamer@cam$i "; done
log "Status:  systemctl status ${SERVICES}nginx"
