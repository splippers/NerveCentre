#!/usr/bin/env bash
# Install the Splippers unified web portal from NerveCentre (nginx, port 80).
# Host-agnostic: Brickwise can load-balance across multiple backends (e.g. Eddie + Marvin).
#
# Brickwise / Archive / SIC / Monyatron / Jonotron / CEO-Simulator / Deanotron / Projects / WorkAdventure: 8756 / 8000 / 8787 / 5050 / 8011 / 8080 / 8791 / 8765 / (WA: see WORKADVENTURE_*).
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
# Replicated Archive + SIC (Marvin + Eddie) — reverse-proxy under /archive/ and /sic/ instead of redirects:
#   sudo ARCHIVE_BACKENDS="10.0.0.1:8000 10.0.0.2:8000" \
#        SIC_BACKENDS="10.0.0.1:8787 10.0.0.2:8787" ./deploy/portal/install-portal.sh
# When ARCHIVE_BACKENDS / SIC_BACKENDS are unset, portal uses HTTP redirects to :ARCHIVE_PORT / :SIC_PORT (same as $host).
#
# Monyatron (Flask on Marvin or elsewhere):
#   sudo MONYATRON_BACKENDS="10.0.0.1:5050 10.0.0.2:5050" ./deploy/portal/install-portal.sh
#
# Jonotron (FastAPI harness — default backend 8011 so Splippers Archive can keep 8000):
#   sudo JONOTRON_BACKENDS="10.0.0.1:8011 10.0.0.2:8011" ./deploy/portal/install-portal.sh
#
# CEO-Simulator (Flask central — Framework :8080; default backend 8080):
#   sudo CEO_SIMULATOR_BACKENDS="10.0.0.1:8080" ./deploy/portal/install-portal.sh
#
# Project prioritiser (moneymakers/projectscan.py — default 8765, path /projects/):
#   PROJECTSCAN_BACKENDS unset → proxy to 127.0.0.1:${PROJECTSCAN_PORT}
#
# WorkAdventure (Traefik on host port 9080 by default when NerveCentre owns :80):
#   sudo NERVECENTRE_LAN_IP=192.168.1.1 ./deploy/portal/install-portal.sh
# Redirect becomes http://192.168.1.1:9080/ and a /workadventure-hosts.txt helper is installed.
# Or full URL (302 target), e.g. staging:
#   sudo WORKADVENTURE_URL='https://play.staging.workadventu.re/' ./deploy/portal/install-portal.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BW_PORT="${BW_PORT:-8756}"
ARCHIVE_PORT="${ARCHIVE_PORT:-8000}"
SIC_PORT="${SIC_PORT:-8787}"
# Optional: load-balance Splippers Archive + SIC like Brickwise (strip /archive|/sic prefix toward backends)
ARCHIVE_BACKENDS="${ARCHIVE_BACKENDS:-}"
ARCHIVE_LB_METHOD="${ARCHIVE_LB_METHOD:-least_conn}"
SIC_BACKENDS="${SIC_BACKENDS:-}"
SIC_LB_METHOD="${SIC_LB_METHOD:-least_conn}"
MONYATRON_PORT="${MONYATRON_PORT:-5050}"
# Space-separated host:port list; unset or empty → single backend 127.0.0.1:$BW_PORT
BRICKWISE_BACKENDS="${BRICKWISE_BACKENDS:-}"
# least_conn (default), "", or ip_hash (sticky by client IP)
BRICKWISE_LB_METHOD="${BRICKWISE_LB_METHOD:-least_conn}"
# Space-separated host:port; unset → 127.0.0.1:$MONYATRON_PORT (Marvin local Monyatron)
MONYATRON_BACKENDS="${MONYATRON_BACKENDS:-}"
MONYATRON_LB_METHOD="${MONYATRON_LB_METHOD:-least_conn}"
JONOTRON_PORT="${JONOTRON_PORT:-8011}"
JONOTRON_BACKENDS="${JONOTRON_BACKENDS:-}"
JONOTRON_LB_METHOD="${JONOTRON_LB_METHOD:-least_conn}"
CEO_SIMULATOR_PORT="${CEO_SIMULATOR_PORT:-8080}"
CEO_SIMULATOR_BACKENDS="${CEO_SIMULATOR_BACKENDS:-}"
CEO_SIMULATOR_LB_METHOD="${CEO_SIMULATOR_LB_METHOD:-least_conn}"
DEANOTRON_PORT="${DEANOTRON_PORT:-8791}"
# WorkAdventure: optional full redirect URL; else NERVECENTRE_LAN_IP + WORKADVENTURE_PORT (Traefik publish port); else *.localhost
NERVECENTRE_LAN_IP="${NERVECENTRE_LAN_IP:-}"
WORKADVENTURE_URL="${WORKADVENTURE_URL:-}"
WORKADVENTURE_PLAY_HOST="${WORKADVENTURE_PLAY_HOST:-play.workadventure.localhost}"
# Host port where WorkAdventure Traefik listens (docker compose reverse-proxy 9080:80).
WORKADVENTURE_PORT="${WORKADVENTURE_PORT:-9080}"
# moneymakers/projectscan.py dashboard (nginx strips /projects/ → backend /)
PROJECTSCAN_PORT="${PROJECTSCAN_PORT:-8765}"
PROJECTSCAN_BACKENDS="${PROJECTSCAN_BACKENDS:-}"
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

generic_lb_upstream_block() {
  local name="$1"
  local backends_list="$2"
  local lb_method="$3"
  local lb="" backends="${backends_list}"

  case "${lb_method}" in
    least_conn) lb="least_conn;" ;;
    ip_hash)    lb="ip_hash;" ;;
    round_robin|"")
      lb=""
      ;;
    *)
      echo "Unknown LB_METHOD=${lb_method} for ${name} (use least_conn, ip_hash, or round_robin)." >&2
      exit 1
      ;;
  esac

  echo "upstream ${name} {"
  if [[ -n "${lb}" ]]; then
    echo "    ${lb}"
  fi
  for be in ${backends}; do
    echo "    server ${be};"
  done
  echo "}"
}

archive_upstream_block() {
  generic_lb_upstream_block nerve_archive "${ARCHIVE_BACKENDS}" "${ARCHIVE_LB_METHOD}"
}

sic_upstream_block() {
  generic_lb_upstream_block nerve_sic "${SIC_BACKENDS}" "${SIC_LB_METHOD}"
}

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

projectscan_upstream_block() {
  local backends=""
  if [[ -z "${PROJECTSCAN_BACKENDS// }" ]]; then
    backends="127.0.0.1:${PROJECTSCAN_PORT}"
  else
    backends="${PROJECTSCAN_BACKENDS}"
  fi

  echo "upstream nerve_projectscan {"
  echo "    least_conn;"
  for be in ${backends}; do
    echo "    server ${be};"
  done
  echo "}"
}

jonotron_upstream_block() {
  local lb="" backends=""
  if [[ -z "${JONOTRON_BACKENDS// }" ]]; then
    backends="127.0.0.1:${JONOTRON_PORT}"
  else
    backends="${JONOTRON_BACKENDS}"
  fi

  case "${JONOTRON_LB_METHOD}" in
    least_conn) lb="least_conn;" ;;
    ip_hash)    lb="ip_hash;" ;;
    round_robin|"")
      lb=""
      ;;
    *)
      echo "Unknown JONOTRON_LB_METHOD=${JONOTRON_LB_METHOD} (use least_conn, ip_hash, or round_robin)." >&2
      exit 1
      ;;
  esac

  echo "upstream nerve_jonotron {"
  if [[ -n "${lb}" ]]; then
    echo "    ${lb}"
  fi
  for be in ${backends}; do
    echo "    server ${be};"
  done
  echo "}"
}

ceosimulator_upstream_block() {
  local lb="" backends=""
  if [[ -z "${CEO_SIMULATOR_BACKENDS// }" ]]; then
    backends="127.0.0.1:${CEO_SIMULATOR_PORT}"
  else
    backends="${CEO_SIMULATOR_BACKENDS}"
  fi

  case "${CEO_SIMULATOR_LB_METHOD}" in
    least_conn) lb="least_conn;" ;;
    ip_hash)    lb="ip_hash;" ;;
    round_robin|"")
      lb=""
      ;;
    *)
      echo "Unknown CEO_SIMULATOR_LB_METHOD=${CEO_SIMULATOR_LB_METHOD} (use least_conn, ip_hash, or round_robin)." >&2
      exit 1
      ;;
  esac

  echo "upstream nerve_ceo_simulator {"
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

deanotron_redirect_stmt() {
  if [[ -n "${DEANOTRON_REDIRECT_HOST:-}" ]]; then
    echo "return 302 http://${DEANOTRON_REDIRECT_HOST}:${DEANOTRON_PORT}/;"
  else
    echo "return 302 http://\$host:${DEANOTRON_PORT}/;"
  fi
}

workadventure_redirect_stmt() {
  if [[ -n "${WORKADVENTURE_URL:-}" ]]; then
    echo "return 302 ${WORKADVENTURE_URL};"
    return
  fi
  if [[ -n "${NERVECENTRE_LAN_IP:-}" ]]; then
    local ip="${NERVECENTRE_LAN_IP}"
    local p="${WORKADVENTURE_PORT}"
    if [[ "${p}" == "80" ]]; then
      echo "return 302 http://${ip}/;"
    else
      echo "return 302 http://${ip}:${p}/;"
    fi
    return
  fi
  local h="${WORKADVENTURE_PLAY_HOST}"
  local p="${WORKADVENTURE_PORT}"
  if [[ "${p}" == "80" ]]; then
    echo "return 302 http://${h}/;"
  else
    echo "return 302 http://${h}:${p}/;"
  fi
}

ARCH_LINE="$(archive_redirect_stmt)"
SIC_LINE="$(sic_redirect_stmt)"
DEAN_LINE="$(deanotron_redirect_stmt)"
WA_LINE="$(workadventure_redirect_stmt)"

if [[ -n "${ARCHIVE_BACKENDS// }" ]]; then
  ARCHIVE_LOC_BODY="$(cat <<'ARCHLOC'


    location = /archive {
        return 301 http://\$host/archive/;
    }

    # Splippers Archive — load-balanced; strip /archive/ toward backends (VIP-friendly).
    location /archive/ {
        proxy_pass http://nerve_archive/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 600s;
        proxy_set_header Accept-Encoding "";

        sub_filter_types application/javascript application/json;
        sub_filter_once off;
        sub_filter '"/api/' '"/archive/api/';
        sub_filter "'/api/" "'/archive/api/";
    }
ARCHLOC
)"
else
  ARCHIVE_LOC_BODY="$(cat <<ARCHLOC


    location = /archive {
        ${ARCH_LINE}
    }
    location /archive/ {
        ${ARCH_LINE}
    }
ARCHLOC
)"
fi

if [[ -n "${SIC_BACKENDS// }" ]]; then
  SIC_LOC_BODY="$(cat <<'SICLOC'


    location = /sic {
        return 301 http://\$host/sic/;
    }

    location /sic/ {
        proxy_pass http://nerve_sic/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 600s;
        proxy_set_header Accept-Encoding "";

        sub_filter_types application/javascript application/json;
        sub_filter_once off;
        sub_filter '"/api/' '"/sic/api/';
        sub_filter "'/api/" "'/sic/api/";
    }
SICLOC
)"
else
  SIC_LOC_BODY="$(cat <<SICLOC


    location = /sic {
        ${SIC_LINE}
    }
    location /sic/ {
        ${SIC_LINE}
    }
SICLOC
)"
fi

mkdir -p "$WWW"

TMP="$(mktemp)"
{
  if [[ -n "${ARCHIVE_BACKENDS// }" ]]; then
    archive_upstream_block
  fi
  if [[ -n "${SIC_BACKENDS// }" ]]; then
    sic_upstream_block
  fi
  brickwise_upstream_block
  monyatron_upstream_block
  jonotron_upstream_block
  ceosimulator_upstream_block
  projectscan_upstream_block
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

        sub_filter_once off;
        sub_filter '"/api/' '"/monyatron/api/';
        sub_filter "'/api/" "'/monyatron/api/";
    }

    location = /jonotron {
        return 301 http://\$host/jonotron/;
    }

    # Jonotron (FastAPI): strip /jonotron/ prefix; rewrite /api and /ui in HTML + JS for the browser.
    location /jonotron/ {
        proxy_pass http://nerve_jonotron/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 600s;
        proxy_set_header Accept-Encoding "";

        sub_filter_types application/javascript;
        sub_filter_once off;
        sub_filter '"/api/' '"/jonotron/api/';
        sub_filter "'/api/" "'/jonotron/api/";
        sub_filter '"/ui/' '"/jonotron/ui/';
        sub_filter "'/ui/" "'/jonotron/ui/";
    }

    location = /ceo-simulator {
        return 301 http://\$host/ceo-simulator/;
    }

    # CEO-Simulator (Flask central): strip /ceo-simulator/ prefix; sub_filter for JSON/HTML clients using relative /api.
    location /ceo-simulator/ {
        proxy_pass http://nerve_ceo_simulator/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 600s;
        proxy_set_header Accept-Encoding "";

        sub_filter_types application/javascript application/json;
        sub_filter_once off;
        sub_filter '"/api/' '"/ceo-simulator/api/';
        sub_filter "'/api/" "'/ceo-simulator/api/";
    }
${ARCHIVE_LOC_BODY}
${SIC_LOC_BODY}

    # Deanotron (Expo web) — absolute asset paths; redirect to dedicated port (see Deanotron deploy/).
    location = /deanotron {
        ${DEAN_LINE}
    }
    location /deanotron/ {
        ${DEAN_LINE}
    }

    # WorkAdventure — Traefik multi-host setup; redirect to play URL (configure WORKADVENTURE_* env vars).
    location = /workadventure {
        return 301 http://\$host/workadventure/;
    }
    location /workadventure/ {
        ${WA_LINE}
    }

    location = /projects {
        return 301 http://\$host/projects/;
    }

    # Project prioritiser (Python http.server — run from sibling moneymakers checkout)
    location /projects/ {
        proxy_pass http://nerve_projectscan/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }

    # Everything else under this host:80 — serve static files; / → index.html (NerveCentre UI)
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX
} >"$TMP"

install -m 0644 "${ROOT}/index.html" "${WWW}/index.html"
if [[ -f "${ROOT}/moneymakers-drive-guide.html" ]]; then
  install -m 0644 "${ROOT}/moneymakers-drive-guide.html" "${WWW}/moneymakers-drive-guide.html"
fi

# One-line /etc/hosts helper so clients resolve *.workadventure.localhost to the NerveCentre host (LAN IP).
WA_HOST_LINE="play.workadventure.localhost front.workadventure.localhost room-api.workadventure.localhost maps.workadventure.localhost api.workadventure.localhost map-storage.workadventure.localhost uploader.workadventure.localhost redis.workadventure.localhost icon.workadventure.localhost oidc.workadventure.localhost matrix.workadventure.localhost traefik.workadventure.localhost pusher.workadventure.localhost xmpp.workadventure.localhost"
if [[ -n "${NERVECENTRE_LAN_IP:-}" ]]; then
  cat >"${WWW}/workadventure-hosts.txt" <<EOF
# Add this line to /etc/hosts (Linux/macOS) or C:\\Windows\\System32\\drivers\\etc\\hosts (Windows Administrator).
# Then open http://${NERVECENTRE_LAN_IP}:${WORKADVENTURE_PORT}/ or use NerveCentre → WorkAdventure.
${NERVECENTRE_LAN_IP} ${WA_HOST_LINE}
EOF
else
  cat >"${WWW}/workadventure-hosts.txt" <<'EOF'
# Re-run install-portal.sh with NERVECENTRE_LAN_IP set to this machine’s LAN address, e.g.:
#   sudo NERVECENTRE_LAN_IP=192.168.1.1 ./deploy/portal/install-portal.sh
# A one-line hosts entry will be generated here automatically.
EOF
fi
chmod 0644 "${WWW}/workadventure-hosts.txt"

install -m 0644 "$TMP" "/etc/nginx/sites-available/${SITE_NAME}.conf"
rm -f "$TMP"

if [[ -e "/etc/nginx/sites-enabled/default" ]]; then
  echo "Disabling stock nginx default site (was claiming port 80)."
  rm -f /etc/nginx/sites-enabled/default
fi

ln -sf "/etc/nginx/sites-available/${SITE_NAME}.conf" "/etc/nginx/sites-enabled/${SITE_NAME}.conf"

nginx -t
if systemctl is-active --quiet nginx; then
  systemctl reload nginx
else
  systemctl start nginx
fi

echo "Splippers portal (NerveCentre) installed."
echo "  Static files: ${WWW}"
echo "  Config: /etc/nginx/sites-available/${SITE_NAME}.conf"
if [[ -z "${BRICKWISE_BACKENDS// }" ]]; then
  echo "  Brickwise upstream: 127.0.0.1:${BW_PORT} (set BRICKWISE_BACKENDS for load balancing)"
else
  echo "  Brickwise upstream (load-balanced): ${BRICKWISE_BACKENDS}"
fi
if [[ -z "${ARCHIVE_BACKENDS// }" ]]; then
  echo "  Splippers Archive: redirect → http://${ARCHIVE_REDIRECT_HOST:-\$host}:${ARCHIVE_PORT}/ (set ARCHIVE_BACKENDS for load-balanced /archive/ proxy)"
else
  echo "  Splippers Archive (/archive/): upstream ${ARCHIVE_BACKENDS}"
fi
if [[ -z "${SIC_BACKENDS// }" ]]; then
  echo "  SIC: redirect → http://${SIC_REDIRECT_HOST:-\$host}:${SIC_PORT}/ (set SIC_BACKENDS for load-balanced /sic/ proxy)"
else
  echo "  SIC (/sic/): upstream ${SIC_BACKENDS}"
fi
if [[ -z "${MONYATRON_BACKENDS// }" ]]; then
  echo "  Monyatron upstream: 127.0.0.1:${MONYATRON_PORT} (set MONYATRON_BACKENDS to load-balance)"
else
  echo "  Monyatron upstream (load-balanced): ${MONYATRON_BACKENDS}"
fi
if [[ -z "${JONOTRON_BACKENDS// }" ]]; then
  echo "  Jonotron upstream: 127.0.0.1:${JONOTRON_PORT} (set JONOTRON_BACKENDS to load-balance; default 8011 avoids clash with Archive on 8000)"
else
  echo "  Jonotron upstream (load-balanced): ${JONOTRON_BACKENDS}"
fi
if [[ -z "${CEO_SIMULATOR_BACKENDS// }" ]]; then
  echo "  CEO-Simulator upstream: 127.0.0.1:${CEO_SIMULATOR_PORT} (set CEO_SIMULATOR_BACKENDS to load-balance)"
else
  echo "  CEO-Simulator upstream (load-balanced): ${CEO_SIMULATOR_BACKENDS}"
fi
echo "  Deanotron redirect: ${DEANOTRON_REDIRECT_HOST:-\$host}:${DEANOTRON_PORT} (Expo web)"
if [[ -n "${WORKADVENTURE_URL:-}" ]]; then
  echo "  WorkAdventure (/workadventure/): redirect → ${WORKADVENTURE_URL}"
elif [[ -n "${NERVECENTRE_LAN_IP:-}" ]]; then
  if [[ "${WORKADVENTURE_PORT}" == "80" ]]; then
    echo "  WorkAdventure (/workadventure/): redirect → http://${NERVECENTRE_LAN_IP}/ · /workadventure-hosts.txt"
  else
    echo "  WorkAdventure (/workadventure/): redirect → http://${NERVECENTRE_LAN_IP}:${WORKADVENTURE_PORT}/ · /workadventure-hosts.txt"
  fi
else
  if [[ "${WORKADVENTURE_PORT}" == "80" ]]; then
    echo "  WorkAdventure (/workadventure/): redirect → http://${WORKADVENTURE_PLAY_HOST}/"
  else
    echo "  WorkAdventure (/workadventure/): redirect → http://${WORKADVENTURE_PLAY_HOST}:${WORKADVENTURE_PORT}/ (set WORKADVENTURE_URL or NERVECENTRE_LAN_IP to override)"
  fi
fi
if [[ -z "${PROJECTSCAN_BACKENDS// }" ]]; then
  echo "  Project prioritiser (/projects/): upstream 127.0.0.1:${PROJECTSCAN_PORT} (PROJECTSCAN_BACKENDS for load-balancing)"
else
  echo "  Project prioritiser (/projects/): upstream ${PROJECTSCAN_BACKENDS}"
fi
echo "Open http://$(hostname -I 2>/dev/null | awk '{print $1}')/ or your load-balanced VIP."
