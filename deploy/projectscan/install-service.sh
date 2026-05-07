#!/usr/bin/env bash
# Install systemd service for the moneymakers project prioritiser (projectscan.py serve).
#
# Expects sibling layout: Projects/moneymakers next to Projects/NerveCentre by default.
#
# Usage from NerveCentre repo root:
#   sudo bash deploy/projectscan/install-service.sh
#
# Environment:
#   PROJECTSCAN_HOME        Path to moneymakers repo (default: ../moneymakers from NerveCentre)
#   MONEYMAKERS             Same as PROJECTSCAN_HOME when called from install-all-splippers.sh
#   PROJECTSCAN_PORT        Listen port (default 8765; nginx /projects/ should match)
#   PROJECTSCAN_PUBLIC_ORIGIN Optional — e.g. http://192.168.1.2 — full URL prefix for Drive setup guide link in dashboard
#   PROJECTSCAN_ROOT        Optional — written to /etc/default/projectscan when set at install
#   PROJECTSCAN_INDEX_DIR   Optional — written to /etc/default/projectscan when set at install
#   RUN_USER                Service user (default: SUDO_USER, logname, or root)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NERVECENTRE="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECTS="$(dirname "$NERVECENTRE")"

MM="${PROJECTSCAN_HOME:-${MONEYMAKERS:-${PROJECTS}/moneymakers}}"
PROJECTSCAN_PORT="${PROJECTSCAN_PORT:-8765}"

RUN_USER="${RUN_USER:-${SUDO_USER:-}}"
if [[ -z "${RUN_USER}" ]] || [[ "${RUN_USER}" == root ]]; then
  RUN_USER="$(logname 2>/dev/null || true)"
fi
if [[ -z "${RUN_USER}" ]]; then
  RUN_USER="root"
fi

die() {
  echo "install-service.sh: $*" >&2
  exit 1
}

PY="$(command -v python3 || true)"
[[ -x "${PY}" ]] || die "python3 not found in PATH."

[[ -f "${MM}/projectscan.py" ]] || die "Missing ${MM}/projectscan.py"

[[ "${EUID:-0}" -eq 0 ]] || die "Run as root: sudo bash $0"

getent passwd "${RUN_USER}" >/dev/null || die "Linux user '${RUN_USER}' does not exist (set RUN_USER=...)."

DEFAULT_ENV=/etc/default/projectscan
SERVICE=/etc/systemd/system/projectscan-dashboard.service

umask 022
{
  echo "# Managed by ${NERVECENTRE}/deploy/projectscan/install-service.sh"
  echo "# After edits: sudo systemctl restart projectscan-dashboard.service"
  echo "PROJECTSCAN_PORT=${PROJECTSCAN_PORT}"
  [[ -n "${PROJECTSCAN_PUBLIC_ORIGIN:-}" ]] && printf 'PROJECTSCAN_PUBLIC_ORIGIN=%s\n' "${PROJECTSCAN_PUBLIC_ORIGIN}"
  [[ -n "${PROJECTSCAN_ROOT:-}" ]] && printf 'PROJECTSCAN_ROOT=%s\n' "${PROJECTSCAN_ROOT}"
  [[ -n "${PROJECTSCAN_INDEX_DIR:-}" ]] && printf 'PROJECTSCAN_INDEX_DIR=%s\n' "${PROJECTSCAN_INDEX_DIR}"
} >"${DEFAULT_ENV}"
chmod 0644 "${DEFAULT_ENV}"

cat >"${SERVICE}" <<EOF
[Unit]
Description=Project prioritiser — moneymakers projectscan.py (dashboard for nginx /projects/)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${MM}
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=/etc/default/projectscan
ExecStart=${PY} ${MM}/projectscan.py serve --host 127.0.0.1 --port \$PROJECTSCAN_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "${SERVICE}"

systemctl daemon-reload
systemctl enable projectscan-dashboard.service
systemctl restart projectscan-dashboard.service

echo "==> projectscan-dashboard.service installed and enabled"
echo "    Unit file: ${SERVICE}"
echo "    Environment: ${DEFAULT_ENV}"
echo "    WorkingDirectory: ${MM}"
echo "    Run as: ${RUN_USER}"
echo ""
systemctl --no-pager --full status projectscan-dashboard.service || true
