#!/usr/bin/env bash
# All-in-one prep for Splippers stack on a single host:
#   Brickwise (Gluster dashboard), Splippers Archive, SIC / massdeb8 arena.
#
# Intended layout (run from anywhere; paths are derived from this script):
#   Projects/NerveCentre/           ← this repo (contains deploy/install-all-splippers.sh)
#   Projects/Brickwise/
#   Projects/Splippers-Archive/
#   Projects/massdeb8/
#
# Requires: sudo root, python3, python3-venv, pip; Node.js + npm for UI builds; nginx for the portal step.
#
# Usage:
#   cd /path/to/Projects/NerveCentre
#   sudo ./deploy/install-all-splippers.sh
#   sudo ./deploy/install-all-splippers.sh --dry-run
#
# Environment (optional):
#   INSTALL_ALL_SPLIPPERS_DRY_RUN=1   Same as --dry-run
#   RUN_USER              User for Splippers + SIC venvs and UI builds (default: SUDO_USER or root)
#   REBUILD_UI=1          Force npm install && npm run build even if dist/ exists
#   SKIP_PORTAL=1         Do not run deploy/portal/install-portal.sh at the end
#   MASSDEB8_PORT=8787    Port for sic-arena.service
#   SPLIPPERS_PORT=8000   Passed through to Splippers systemd install

set -euo pipefail

DRY_RUN="${INSTALL_ALL_SPLIPPERS_DRY_RUN:-0}"
SKIP_PORTAL="${SKIP_PORTAL:-0}"

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=1 ;;
  esac
done

die() {
  echo "error: $*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID:-0}" -ne 0 ]]; then
    die "Run with sudo: sudo $0 $*"
  fi
}

NERVECENTRE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS="$(cd "${NERVECENTRE}/.." && pwd)"

BRICKWISE="${PROJECTS}/Brickwise"
SPLIPPERS="${PROJECTS}/Splippers-Archive"
MASSDEB8="${PROJECTS}/massdeb8"

RUN_USER="${RUN_USER:-${SUDO_USER:-}}"
if [[ -z "${RUN_USER}" ]] || [[ "${RUN_USER}" == root ]]; then
  RUN_USER="$(logname 2>/dev/null || true)"
fi
if [[ -z "${RUN_USER}" ]]; then
  RUN_USER="root"
fi

export SPLIPPERS_PORT="${SPLIPPERS_PORT:-8000}"
export MASSDEB8_PORT="${MASSDEB8_PORT:-8787}"

echo "==> NerveCentre all-in-one Splippers installer"
echo "    NerveCentre: ${NERVECENTRE}"
echo "    Projects:    ${PROJECTS}"
echo "    Brickwise:   ${BRICKWISE}"
echo "    Archive:     ${SPLIPPERS}"
echo "    SIC/massdeb8:${MASSDEB8}"
echo "    RUN_USER (venv/UI): ${RUN_USER}"
echo

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "(dry run — exiting)"
  exit 0
fi

need_root

[[ -d "${BRICKWISE}" ]] || die "Brickwise clone not found: ${BRICKWISE}"
[[ -d "${SPLIPPERS}" ]] || die "Splippers-Archive clone not found: ${SPLIPPERS}"
[[ -d "${MASSDEB8}" ]] || die "massdeb8 clone not found: ${MASSDEB8}"
[[ -f "${BRICKWISE}/deploy/setup-venv.sh" ]] || die "Missing ${BRICKWISE}/deploy/setup-venv.sh"
[[ -f "${SPLIPPERS}/splippers-api/app.py" ]] || die "Missing Splippers API app.py"
[[ -f "${MASSDEB8}/arena/app.py" ]] || die "Missing massdeb8 arena app (arena/app.py)"

command -v python3 >/dev/null || die "python3 not found"
command -v npm >/dev/null || die "npm not found (install Node.js for UI builds)"

# --- Brickwise: /opt venv + systemd -------------------------------------------------
echo "==> [1/5] Brickwise — venv at /opt/brickwise-venv"
if [[ -x /opt/brickwise-venv/bin/brickwise ]]; then
  echo "    upgrading editable install from ${BRICKWISE}"
  /opt/brickwise-venv/bin/pip install -U pip wheel
  /opt/brickwise-venv/bin/pip install -e "${BRICKWISE}[serve]"
else
  bash "${BRICKWISE}/deploy/setup-venv.sh" "${BRICKWISE}"
fi

install -m 0644 "${BRICKWISE}/deploy/brickwise-dashboard.service" /etc/systemd/system/brickwise-dashboard.service
echo "    installed /etc/systemd/system/brickwise-dashboard.service"

# --- Splippers Archive: venv, UI build, systemd ------------------------------------
echo "==> [2/5] Splippers Archive — venv, UI, systemd unit"
API_DIR="${SPLIPPERS}/splippers-api"
UI_DIR="${SPLIPPERS}/splippers-ui"

run_as_user() {
  local cmd="$1"
  if [[ "${RUN_USER}" == root ]]; then
    bash -c "${cmd}"
  else
    sudo -u "${RUN_USER}" -H bash -c "${cmd}"
  fi
}

if [[ ! -x "${API_DIR}/.venv/bin/python" ]]; then
  echo "    creating venv under splippers-api/.venv"
  run_as_user "set -euo pipefail; cd \"${API_DIR}\"; python3 -m venv .venv; .venv/bin/pip install -U pip wheel; .venv/bin/pip install -r requirements.txt"
else
  echo "    refreshing venv deps"
  run_as_user "set -euo pipefail; cd \"${API_DIR}\"; .venv/bin/pip install -U pip wheel; .venv/bin/pip install -r requirements.txt"
fi

if [[ -f "${UI_DIR}/dist/index.html" ]] && [[ "${REBUILD_UI:-0}" != "1" ]]; then
  echo "    splippers-ui/dist present — skip npm build (set REBUILD_UI=1 to force)"
else
  echo "    building splippers-ui"
  run_as_user "set -euo pipefail; cd \"${UI_DIR}\"; npm install; npm run build"
fi

SPLIPPERS_USER="${RUN_USER}" bash "${SPLIPPERS}/scripts/install-splippers-service.sh"

# --- massdeb8 / SIC: venv, UI build, systemd ----------------------------------------
echo "==> [3/5] SIC (massdeb8) — venv, UI, systemd unit"
if [[ ! -x "${MASSDEB8}/.venv/bin/uvicorn" ]]; then
  echo "    creating venv at massdeb8/.venv"
  run_as_user "set -euo pipefail; cd \"${MASSDEB8}\"; python3 -m venv .venv; .venv/bin/pip install -U pip wheel; .venv/bin/pip install -r requirements.txt"
else
  echo "    refreshing venv deps"
  run_as_user "set -euo pipefail; cd \"${MASSDEB8}\"; .venv/bin/pip install -U pip wheel; .venv/bin/pip install -r requirements.txt"
fi

if [[ -f "${MASSDEB8}/ui/dist/index.html" ]] && [[ "${REBUILD_UI:-0}" != "1" ]]; then
  echo "    ui/dist present — skip npm build (set REBUILD_UI=1 to force)"
else
  echo "    building massdeb8 ui"
  run_as_user "set -euo pipefail; cd \"${MASSDEB8}/ui\"; npm install; npm run build"
fi

SIC_UNIT=/etc/systemd/system/sic-arena.service
UV="${MASSDEB8}/.venv/bin/uvicorn"
cat >"${SIC_UNIT}" <<EOF
[Unit]
Description=SIC — Symposium of Infinite Contention (massdeb8 arena)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${MASSDEB8}
Environment=PYTHONUNBUFFERED=1
ExecStart=${UV} arena.app:app --host 0.0.0.0 --port ${MASSDEB8_PORT}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "${SIC_UNIT}"
echo "    wrote ${SIC_UNIT}"

# --- Enable services ---------------------------------------------------------------
echo "==> [4/5] systemd daemon-reload + enable --now"
systemctl daemon-reload
systemctl enable --now brickwise-dashboard splippers-archive sic-arena
echo "    brickwise-dashboard splippers-archive sic-arena"

# --- NerveCentre portal (nginx) ----------------------------------------------------
if [[ "${SKIP_PORTAL}" == "1" ]]; then
  echo "==> [5/5] SKIP_PORTAL=1 — not running deploy/portal/install-portal.sh"
else
  echo "==> [5/5] NerveCentre portal (nginx port 80)"
  if ! command -v nginx >/dev/null 2>&1; then
    echo "    nginx not installed — skipping portal (install nginx and run: sudo bash ${NERVECENTRE}/deploy/portal/install-portal.sh)"
  else
    bash "${NERVECENTRE}/deploy/portal/install-portal.sh"
  fi
fi

echo
echo "Done. Services:"
echo "  Brickwise           http://127.0.0.1:8756/   (also /brickwise/ via portal)"
echo "  Splippers Archive   http://127.0.0.1:${SPLIPPERS_PORT:-8000}/"
echo "  SIC / massdeb8      http://127.0.0.1:${MASSDEB8_PORT}/"
if [[ "${SKIP_PORTAL}" != "1" ]] && command -v nginx >/dev/null 2>&1; then
  echo "  NerveCentre portal  http://127.0.0.1/"
fi
