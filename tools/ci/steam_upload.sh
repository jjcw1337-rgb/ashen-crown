#!/bin/sh
# CI: uploads the exported builds to Steam and sets them live on a (password-protected) beta branch.
#   sh tools/ci/steam_upload.sh <branch> <description>
# Needs, from the environment: STEAM_APP_ID, STEAM_DEPOT_WINDOWS, STEAM_DEPOT_MAC, STEAM_DEPOT_LINUX (numbers from
# Steamworks), STEAM_USERNAME (a Steamworks build account) and STEAM_CONFIG_VDF (base64 of that account's
# config/config.vdf after one Steam Guard login, so CI isn't asked for a code). Content: build/win, build/mac,
# build/linux. STEAM_DRY_RUN=1 writes and prints the build scripts without uploading. Never prints a credential.
set -eu
BRANCH=$1; DESC=$2
for v in STEAM_APP_ID STEAM_DEPOT_WINDOWS STEAM_DEPOT_MAC STEAM_DEPOT_LINUX; do
  eval "x=\${$v:-}"; echo "$x" | grep -Eq '^[0-9]+$' || { echo "$v is missing or not a number"; exit 1; }
done
[ -n "${STEAM_USERNAME:-}" ] && [ -n "${STEAM_CONFIG_VDF:-}" ] || { echo "STEAM_USERNAME / STEAM_CONFIG_VDF missing"; exit 1; }
[ "$BRANCH" != "default" ] || { echo "refusing to set the default (public) branch live from CI"; exit 1; }
ROOT=$(pwd)
SC=$ROOT/build/steamcmd
mkdir -p $SC $ROOT/build/steam
depot() {  # id, content dir
  cat > $ROOT/build/steam/depot_$1.vdf <<VDF
"DepotBuild"
{
  "DepotID" "$1"
  "ContentRoot" "$2"
  "FileMapping" { "LocalPath" "*" "DepotPath" "." "Recursive" "1" }
}
VDF
}
depot $STEAM_DEPOT_WINDOWS $ROOT/build/win
depot $STEAM_DEPOT_MAC $ROOT/build/mac
depot $STEAM_DEPOT_LINUX $ROOT/build/linux
cat > $ROOT/build/steam/app_build.vdf <<VDF
"AppBuild"
{
  "AppID" "$STEAM_APP_ID"
  "Desc" "$DESC"
  "SetLive" "$BRANCH"
  "ContentRoot" "$ROOT/build"
  "BuildOutput" "$ROOT/build/steam/output"
  "Depots"
  {
    "$STEAM_DEPOT_WINDOWS" "$ROOT/build/steam/depot_$STEAM_DEPOT_WINDOWS.vdf"
    "$STEAM_DEPOT_MAC" "$ROOT/build/steam/depot_$STEAM_DEPOT_MAC.vdf"
    "$STEAM_DEPOT_LINUX" "$ROOT/build/steam/depot_$STEAM_DEPOT_LINUX.vdf"
  }
}
VDF
if [ "${STEAM_DRY_RUN:-0}" = 1 ]; then
  cat $ROOT/build/steam/app_build.vdf $ROOT/build/steam/depot_*.vdf
  echo "dry run: nothing uploaded"
  exit 0
fi
curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C $SC
mkdir -p $SC/config
echo "$STEAM_CONFIG_VDF" | base64 -d > $SC/config/config.vdf
chmod 600 $SC/config/config.vdf
$SC/steamcmd.sh +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 +login "$STEAM_USERNAME" \
  +run_app_build $ROOT/build/steam/app_build.vdf +quit
echo "uploaded to Steam app $STEAM_APP_ID, live on branch $BRANCH"
