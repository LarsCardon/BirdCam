#!/usr/bin/env bash
#
# BirdCam uninstaller. Removes services, web page and nginx config.
# Leaves installed packages (nginx, v4l-utils, uStreamer) in place.
#
set -euo pipefail

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
[[ $EUID -eq 0 ]] || { echo "Please run as root (sudo ./uninstall.sh)." >&2; exit 1; }

log "Stopping and disabling services..."
systemctl disable --now ustreamer@cam1 ustreamer@cam2 2>/dev/null || true

log "Removing files..."
rm -f /etc/systemd/system/ustreamer@.service
systemctl daemon-reload
rm -f /etc/nginx/sites-enabled/birdcam.conf /etc/nginx/sites-available/birdcam.conf
rm -rf /var/www/birdcam
rm -rf /etc/birdcam
rm -f /usr/local/bin/birdcam-detect

if command -v nginx >/dev/null; then
    nginx -t 2>/dev/null && systemctl restart nginx || true
fi

log "Done. (uStreamer binary at /usr/local/bin/ustreamer and apt packages left intact.)"
