#!/usr/bin/env bash
# Installs Blender 4.5 LTS (Linux x64) to /opt and links it as `blender`, verifying the
# official checksum. For Linux machines and Claude's cloud workspace (which resets, so run
# this again in a new session). Windows/Mac: install from https://www.blender.org/download/
# (pick 4.5 LTS so everyone uses the same version).
#
#   bash tools/blender/setup_blender.sh            # install (needs sudo outside the workspace)
#   blender -b --python tools/blender/<script>.py   # run a script headless
set -euo pipefail
VER="${BLENDER_VERSION:-4.5.15}"
SERIES="${VER%.*}"
DEST="${BLENDER_DIR:-/opt}"
NAME="blender-${VER}-linux-x64"
if command -v blender >/dev/null && blender --version 2>/dev/null | grep -q "Blender ${VER}"; then
	echo "Blender ${VER} already installed"; exit 0
fi
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
URL="https://download.blender.org/release/Blender${SERIES}"
echo "Downloading ${NAME} ..."
curl -fsSL -o "$TMP/${NAME}.tar.xz" "${URL}/${NAME}.tar.xz"
curl -fsSL -o "$TMP/sums" "${URL}/blender-${VER}.sha256"
(cd "$TMP" && grep " ${NAME}.tar.xz\$" sums | sha256sum -c -)
$SUDO mkdir -p "$DEST"
$SUDO tar -xf "$TMP/${NAME}.tar.xz" -C "$DEST"
$SUDO ln -sf "$DEST/${NAME}/blender" /usr/local/bin/blender
blender --version | head -1
