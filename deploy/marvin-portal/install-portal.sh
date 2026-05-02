#!/usr/bin/env bash
# Install the Splippers unified web portal from NerveCentre (nginx, port 80).
# Run on Marvin (or any host) after nginx is installed.
#
# Defaults match Splippers conventions:
#   Brickwise dashboard: 8756
#   Splippers Archive API/UI: 8000
#   SIC (massdeb8 arena): 8787
#
# Usage (from this repo):
#   sudo ./deploy/marvin-portal/install-portal.sh
#   sudo BW_PORT=8756 ARCHIVE_PORT=8000 SIC_PORT=8787 ./deploy/marvin-portal/install-portal.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BW_PORT="${BW_PORT:-8756}"
ARCHIVE_PORT="${ARCHIVE_PORT:-8000}"
SIC_PORT="${SIC_PORT:-8787}"
WWW="${WWW:-/var/www/splippers-portal}"
SITE_NAME="${SITE_NAME:-splippers-portal}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx is not installed. On Debian/Ubuntu: sudo apt install nginx" >&2
  exit 1
fi

mkdir -p "$WWW"
install -m 0644 "${ROOT}/index.html" "${WWW}/index.html"

TMP="$(mktemp)"
sed -e "s/@@BRICKWISE_PORT@@/${BW_PORT}/g" \
    -e "s/@@ARCHIVE_PORT@@/${ARCHIVE_PORT}/g" \
    -e "s/@@SIC_PORT@@/${SIC_PORT}/g" \
    "${ROOT}/nginx-splippers-portal.conf.in" >"$TMP"
install -m 0644 "$TMP" "/etc/nginx/sites-available/${SITE_NAME}.conf"
rm -f "$TMP"

if [[ -e "/etc/nginx/sites-enabled/default" ]]; then
  echo "Disabling stock nginx default site (was claiming port 80)."
  rm -f /etc/nginx/sites-enabled/default
fi

ln -sf "/etc/nginx/sites-available/${SITE_NAME}.conf" "/etc/nginx/sites-enabled/${SITE_NAME}.conf"

nginx -t
systemctl reload nginx

echo "Splippers portal (NerveCentre) installed."
echo "  Static files: ${WWW}"
echo "  Config: /etc/nginx/sites-available/${SITE_NAME}.conf"
echo "  Ports: Brickwise→${BW_PORT}, Archive→${ARCHIVE_PORT}, SIC→${SIC_PORT}"
echo "Open http://$(hostname -I 2>/dev/null | awk '{print $1}')/ (or this host's LAN IP)."
