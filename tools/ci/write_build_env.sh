#!/bin/sh
# CI: points this checkout's build at an environment before exporting, by rewriting scripts/build_env.gd's constants.
#   sh tools/ci/write_build_env.sh <env> <bg_server host:port> <nakama https url> <nakama server key>
# Values are checked against strict patterns (no quotes or spaces can get into the GDScript). Prints no key.
set -eu
ENV_NAME=$1; BG=$2; URL=$3; KEY=$4
F=scripts/build_env.gd
REV=$(echo "${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo ci)}" | cut -c1-7 | tr -cd 'A-Za-z0-9')
echo "$ENV_NAME" | grep -Eq '^(staging|production)$' || { echo "env must be staging or production"; exit 1; }
echo "$BG" | grep -Eq '^[A-Za-z0-9.-]+:[0-9]{2,5}$' || { echo "bad bg_server"; exit 1; }
echo "$URL" | grep -Eq '^https://[A-Za-z0-9.-]+(:[0-9]{2,5})?$' || { echo "nakama url must be https://host[:port]"; exit 1; }
echo "$KEY" | grep -Eq '^[A-Za-z0-9_-]{8,128}$' || { echo "bad nakama key"; exit 1; }
sed -i.bak \
  -e "s|^const ENV := \"[^\"]*\"|const ENV := \"$ENV_NAME\"|" \
  -e "s|^const BG_SERVER := \"[^\"]*\"|const BG_SERVER := \"$BG\"|" \
  -e "s|^const NAKAMA_URL := \"[^\"]*\"|const NAKAMA_URL := \"$URL\"|" \
  -e "s|^const NAKAMA_KEY := \"[^\"]*\"|const NAKAMA_KEY := \"$KEY\"|" \
  -e "s|^const CLOUD := \"[^\"]*\"|const CLOUD := \"1\"|" \
  -e "s|^const REV := \"[^\"]*\"|const REV := \"$REV\"|" $F
rm -f $F.bak
grep -q "const ENV := \"$ENV_NAME\"" $F && grep -q 'const CLOUD := "1"' $F || { echo "build_env.gd was not rewritten"; exit 1; }
# a staging build is its own app: its own name and window title, its own save folder (Godot's user dir follows the
# project name: app_userdata/Ashen Crown Staging) and its own macOS bundle id, so it never touches the live game's saves
if [ "$ENV_NAME" = staging ]; then
  sed -i.bak -e 's|^config/name="Ashen Crown"$|config/name="Ashen Crown Staging"|' project.godot
  sed -i.bak -e 's|^application/bundle_identifier="io.github.jjcw1337rgb.ashencrown"$|application/bundle_identifier="io.github.jjcw1337rgb.ashencrown.staging"|' export_presets.cfg
  rm -f project.godot.bak export_presets.cfg.bak
  grep -q '^config/name="Ashen Crown Staging"$' project.godot || { echo "project name not changed"; exit 1; }
  grep -q 'ashencrown.staging"$' export_presets.cfg || { echo "bundle id not changed"; exit 1; }
fi
echo "build env: $ENV_NAME, game server $BG, Nakama $URL"
