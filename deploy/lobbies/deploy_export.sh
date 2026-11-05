#!/bin/sh
# Install a CI-exported Linux staging candidate. Does not publish clients or import assets.
# Usage: sh deploy/lobbies/deploy_export.sh <Linux-artifact-directory> [ssh-host]
set -eu
EXPORT=$(cd "$1" && pwd)
HOST=${2:-ashen-crown-staging}
ROOT=$(git rev-parse --show-toplevel)
REV=$(git rev-parse --short=7 HEAD)
[ "$(cat "$EXPORT/DEPLOYED_REV")" = "$REV" ] || { echo 'Export does not match checkout'; exit 1; }
[ -s "$EXPORT/AshenCrown.x86_64" ] || { echo 'Missing exported game'; exit 1; }
REMOTE=/opt/ashen-crown/staging/releases/lobby-$REV
ssh "$HOST" "sudo install -d -o ashen -g ashen '$REMOTE'"
COPYFILE_DISABLE=1 tar -C "$EXPORT" -cf - . | ssh "$HOST" "sudo tar -xf - -C '$REMOTE'"
COPYFILE_DISABLE=1 tar -C "$ROOT" -cf - deploy/lobbies | ssh "$HOST" "sudo tar -xf - -C '$REMOTE'"
ssh "$HOST" "sudo chmod +x '$REMOTE/AshenCrown.x86_64'; sudo chown -R ashen:ashen '$REMOTE'; sudo python3 '$REMOTE/deploy/lobbies/install_export.py' '$REMOTE'"
