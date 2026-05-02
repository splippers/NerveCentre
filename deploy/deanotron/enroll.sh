#!/usr/bin/env bash
# Enroll Deanotron into the Splippers stack: systemd Expo web (deanotron-web) on DEANOTRON_PORT (default 8791).
# Expects a Deanotron clone beside NerveCentre (e.g. Projects/Deanotron next to Projects/NerveCentre).
#
# Usage from NerveCentre root:
#   sudo ./deploy/deanotron/enroll.sh
#   sudo DEANOTRON_SRC=/opt/Deanotron ./deploy/deanotron/enroll.sh
#
# Environment:
#   DEANOTRON_SRC     Path to Deanotron repo (default: sibling ../Deanotron of this NerveCentre checkout)
#   DEANOTRON_USER    Service user (default: SUDO_USER, or root when appropriate)
#   DEANOTRON_PORT    Listen port (default: 8791)
#   DEANOTRON_NODE    Optional path to node binary (Deanotron install-deanotron.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NERVECENTRE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEANOTRON_SRC="${DEANOTRON_SRC:-$(dirname "$NERVECENTRE")/Deanotron}"

die() {
  echo "enroll.sh: $*" >&2
  exit 1
}

INSTALLER="${DEANOTRON_SRC}/deploy/install-deanotron.sh"
[[ -d "${DEANOTRON_SRC}" ]] || die "No Deanotron tree at ${DEANOTRON_SRC} — clone it or set DEANOTRON_SRC."
[[ -f "${INSTALLER}" ]] || die "Missing ${INSTALLER} (expected Deanotron repo with deploy/install-deanotron.sh)."

echo "==> NerveCentre enroll: Deanotron"
echo "    NerveCentre:  ${NERVECENTRE}"
echo "    Deanotron src: ${DEANOTRON_SRC}"
echo "    Port:          ${DEANOTRON_PORT:-8791}"

export DEANOTRON_SRC
export DEANOTRON_PORT="${DEANOTRON_PORT:-8791}"
export DEANOTRON_USER="${DEANOTRON_USER:-${SUDO_USER:-root}}"

if [[ "${EUID:-0}" -eq 0 ]]; then
  exec bash "${INSTALLER}"
fi

if [[ -n "${DEANOTRON_NODE:-}" ]]; then
  exec sudo env \
    DEANOTRON_SRC="${DEANOTRON_SRC}" \
    DEANOTRON_PORT="${DEANOTRON_PORT}" \
    DEANOTRON_USER="${DEANOTRON_USER}" \
    DEANOTRON_NODE="${DEANOTRON_NODE}" \
    bash "${INSTALLER}"
fi

exec sudo env \
  DEANOTRON_SRC="${DEANOTRON_SRC}" \
  DEANOTRON_PORT="${DEANOTRON_PORT}" \
  DEANOTRON_USER="${DEANOTRON_USER}" \
  bash "${INSTALLER}"
