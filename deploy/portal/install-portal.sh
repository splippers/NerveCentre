#!/usr/bin/env bash
# Install the Splippers unified web portal from NerveCentre (nginx, port 80).
# Host-agnostic: Brickwise can load-balance across multiple backends (e.g. Eddie + Marvin).
#
# Brickwise / Splippers Archive / SIC / Monyatron defaults: 8756 / 8000 / 8787 / 5050.
#
# Usage (from repo checkout):
#   sudo ./deploy/portal/install-portal.sh
#
# Load-balanced Brickwise (same port on each Gluster node):
#   sudo BRICKWISE_BACKENDS="10.0.0.1:8756 10.0.0.2:8756" ./deploy/portal/install-portal.sh
#
# Archive or SIC only on one node — pin redirects (optional):
#   sudo ARCHIVE_REDIRECT_HOST=marvin.lan SIC_REDIRECT_HOST=eddie.lan ./deploy/portal/install-portal.sh
#
# Monyatron (Flask on Marvin or elsewhere):
#   sudo MONYATRON_BACKENDS="10.0.0.1:5050 10.0.0.2:5050" ./deploy/portal/install-portal.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BW_PORT="${BW_PORT:-8756}"
ARCHIVE_PORT="${ARCHIVE_PORT:-8000}"
SIC_PORT="${SIC_PORT:-8787}"
MONYATRON_PORT="${MONYATRON_PORT:-5050}"
# Space-separated host:port list; unset or empty → single backend 127.0.0.1:$BW_PORT
BRICKWISE_BACKENDS="${BRICKWISE_BACKENDS:-}"
# least_conn (default), "", or ip_hash (sticky by client IP)
BRICKWISE_LB_METHOD="${BRICKWISE_LB_METHOD:-least_conn}"
# Space-separated host:port; unset → 127.0.0.1:$MONYATRON_PORT (Marvin local Monyatron)
MONYATRON_BACKENDS="${MONYATRON_BACKENDS:-}"
MONYATRON_LB_METHOD="${MONYATRON_LB_METHOD:-least_conn}"
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

brickwise_upstream_block() {
  local lb="" backends=""
  if [[ -z "${BRICKWISE_BACKENDS// }" ]]; then
    backends="127.0.0.1:${BW_PORT}"
  else
    backends="${BRICKWISE_BACKENDS}"
  fi

  case "${BRICKWISE_LB_METHOD}" in
    least_conn) lb="least_conn;" ;;
    ip_hash)    lb="ip_hash;" ;;
    round_robin|"")
      lb=""
      ;;
    *)
      echo "Unknown BRICKWISE_LB_METHOD=${BRICKWISE_LB_METHOD} (use least_conn, ip_hash, or round_robin)." >&2
      exit 1
      ;;
  esac

  echo "upstream nerve_brickwise {"
  if [[ -n "${lb}" ]]; then
    echo "    ${lb}"
  fi
  for be in ${backends}; do
    echo "    server ${be};"
  done
  echo "}"
}

monyatron_upstream_block() {
  local lb="" backends=""
  if [[ -z "${MONYATRON_BACKENDS// }" ]]; then
    backends="127.0.0.1:${MONYATRON_PORT}"
  else
    backends="${MONYATRON_BACKENDS}"
  fi

  case "${MONYATRON_LB_METHOD}" in
    least_conn) lb="least_conn;" ;;
    ip_hash)    lb="ip_hash;" ;;
    round_robin|"")
      lb=""
      ;;
    *)
      echo "Unknown MONYATRON_LB_METHOD=${MONYATRON_LB_METHOD} (use least_conn, ip_hash, or round_robin)." >&2
      exit 1
      ;;
  esac

  echo "upstream nerve_monyatron {"
  if [[ -n "${lb}" ]]; then
    echo "    ${lb}"
  fi
  for be in ${backends}; do
    echo "    server ${be};"
  done
  echo "}"
}

archive_redirect_stmt() {
  if [[ -n "${ARCHIVE_REDIRECT_HOST:-}" ]]; then
    echo "return 302 http://${ARCHIVE_REDIRECT_HOST}:${ARCHIVE_PORT}/;"
  else
    echo "return 302 http://\$host:${ARCHIVE_PORT}/;"
  fi
}

sic_redirect_stmt() {
  if [[ -n "${SIC_REDIRECT_HOST:-}" ]]; then
    echo "return 302 http://${SIC_REDIRECT_HOST}:${SIC_PORT}/;"
  else
    echo "return 302 http://\$host:${SIC_PORT}/;"
  fi
}

ARCH_LINE="$(archive_redirect_stmt)"
SIC_LINE="$(sic_redirect_stmt)"

mkdir -p "$WWW"

TMP="$(mktemp)"
{
  brickwise_upstream_block
  monyatron_upstream_block
  cat <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Unified NerveCentre landing page is the default for http://host/ and http://host:80/
    root "${WWW}";
    index index.html;

    location = /brickwise {
        return 301 http://\$host/brickwise/;
    }

    # Brickwise (Flask): strip /brickwise/ prefix; HTML sub_filter fixes /api paths for the browser.
    location /brickwise/ {
        proxy_pass http://nerve_brickwise/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
        proxy_set_header Accept-Encoding "";

        sub_filter_types text/html;
        sub_filter_once off;
        sub_filter '"/api/' '"/brickwise/api/';
        sub_filter "'/api/" "'/brickwise/api/";
    }

    location = /monyatron {
        return 301 http://\$host/monyatron/;
    }

    # Monyatron (Flask): strip /monyatron/ prefix; HTML sub_filter fixes /api paths.
    location /monyatron/ {
        proxy_pass http://nerve_monyatron/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_set_header Accept-Encoding "";

        sub_filter_types text/html;
        sub_filter_once off;
        sub_filter '"/api/' '"/monyatron/api/';
        sub_filter "'/api/" "'/monyatron/api/";
    }

    location = /archive {
        ${ARCH_LINE}
    }
    location /archive/ {
        ${ARCH_LINE}
    }

    location = /sic {
        ${SIC_LINE}
    }
    location /sic/ {
        ${SIC_LINE}
    }

    # Everything else under this host:80 — serve static files; / → index.html (NerveCentre UI)
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX
} >"$TMP"

install -m 0644 "${ROOT}/index.html" "${WWW}/index.html"
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
if [[ -z "${BRICKWISE_BACKENDS// }" ]]; then
  echo "  Brickwise upstream: 127.0.0.1:${BW_PORT} (set BRICKWISE_BACKENDS for load balancing)"
else
  echo "  Brickwise upstream (load-balanced): ${BRICKWISE_BACKENDS}"
fi
echo "  Archive redirect: ${ARCHIVE_REDIRECT_HOST:-\$host}:${ARCHIVE_PORT}"
echo "  SIC redirect: ${SIC_REDIRECT_HOST:-\$host}:${SIC_PORT}"
if [[ -z "${MONYATRON_BACKENDS// }" ]]; then
  echo "  Monyatron upstream: 127.0.0.1:${MONYATRON_PORT} (set MONYATRON_BACKENDS to load-balance)"
else
  echo "  Monyatron upstream (load-balanced): ${MONYATRON_BACKENDS}"
fi
echo "Open http://$(hostname -I 2>/dev/null | awk '{print $1}')/ or your load-balanced VIP."
