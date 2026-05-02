#!/usr/bin/env bash
# Clone or update this repository at $NERVECENTRE_ROOT (host-agnostic).
#
# Examples:
#   NERVECENTRE_ROOT=/mnt/EDDIE-SANDIEGO/Projects/NerveCentre bash deploy/install-repo.sh
#   NERVECENTRE_ROOT=/mnt/SANDIEGO/Projects/NerveCentre bash deploy/install-repo.sh
#   NERVECENTRE_ROOT=/srv/splippers/NerveCentre bash deploy/install-repo.sh

set -euo pipefail

REPO_URL="${NERVECENTRE_REPO_URL:-https://github.com/splippers/NerveCentre.git}"
DEST="${NERVECENTRE_ROOT:-${HOME}/Projects/NerveCentre}"
PARENT="$(dirname "$DEST")"

die() {
  echo "$*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "git is required."

if [[ ! -d "$PARENT" ]]; then
  echo "Creating $PARENT ..."
  if mkdir -p "$PARENT" 2>/dev/null; then
    :
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo mkdir -p "$PARENT" || die "Could not create $PARENT."
    sudo chown "$(id -un):$(id -gn)" "$PARENT" 2>/dev/null || true
  else
    die "Cannot create $PARENT — set NERVECENTRE_ROOT to a writable path or create the parent directory."
  fi
fi

if [[ -d "$DEST/.git" ]]; then
  git -C "$DEST" pull --ff-only
  echo "Updated existing repo at $DEST"
elif [[ -e "$DEST" ]]; then
  die "$DEST exists but is not a git clone — move it aside or set NERVECENTRE_ROOT."
else
  git clone "$REPO_URL" "$DEST"
  echo "Cloned $REPO_URL → $DEST"
fi

echo "To enable the Splippers portal on port 80 (nginx): sudo bash \"$DEST/deploy/portal/install-portal.sh\""
