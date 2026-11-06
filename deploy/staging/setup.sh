#!/bin/sh
# One-time (and safely re-runnable) setup of the STAGING server, run on the server as the sudo user:
#   ssh ashen-crown-staging 'sudo sh -s' < deploy/staging/setup.sh
# Installs Docker and Godot 4.3 (checksum-verified), makes the `ashen` service user and /opt/ashen-crown, and the
# secrets files (random, mode 600, kept if they already exist). It never prints a secret.
set -eu
BASE=/opt/ashen-crown
GODOT_URL=https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip
GODOT_SUMS=https://github.com/godotengine/godot/releases/download/4.4.1-stable/SHA512-SUMS.txt

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq docker.io docker-compose-v2 unzip curl ca-certificates fontconfig libfontconfig1 > /dev/null
systemctl enable --now docker > /dev/null

id ashen > /dev/null 2>&1 || useradd --system --create-home --home-dir /home/ashen --shell /usr/sbin/nologin ashen
mkdir -p $BASE/godot $BASE/staging/game $BASE/staging/backend/modules
chown -R ashen:ashen $BASE/staging/game

if [ ! -x $BASE/godot/godot ]; then
  tmp=$(mktemp -d)
  curl -fsSL -o $tmp/godot.zip $GODOT_URL
  curl -fsSL -o $tmp/sums.txt $GODOT_SUMS
  want=$(grep ' Godot_v4.4.1-stable_linux.x86_64.zip$' $tmp/sums.txt | cut -d' ' -f1)
  got=$(sha512sum $tmp/godot.zip | cut -d' ' -f1)
  [ -n "$want" ] && [ "$want" = "$got" ] || { echo "Godot checksum mismatch"; exit 1; }
  unzip -q -o $tmp/godot.zip -d $tmp
  install -m 755 $tmp/Godot_v4.4.1-stable_linux.x86_64 $BASE/godot/godot
  rm -rf $tmp
fi

rnd() { head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
ENVF=$BASE/staging/backend/nakama.env
if [ ! -f $ENVF ]; then
  umask 077
  {
    echo "POSTGRES_PASSWORD=$(rnd)"
    echo "NAKAMA_SERVER_KEY=$(rnd)"
    echo "NAKAMA_SESSION_KEY=$(rnd)"
    echo "NAKAMA_REFRESH_KEY=$(rnd)"
    echo "NAKAMA_HTTP_KEY=$(rnd)"
    echo "NAKAMA_CONSOLE_PASSWORD=$(rnd)"
  } > $ENVF
fi
chmod 600 $ENVF
BGENV=$BASE/staging/bg.env
umask 077
{
  echo "ASHEN_NAKAMA_URL=http://127.0.0.1:7350"
  echo "ASHEN_NAKAMA_HTTP_KEY=$(grep '^NAKAMA_HTTP_KEY=' $ENVF | cut -d= -f2)"
} > $BGENV
chown ashen:ashen $BGENV
chmod 600 $BGENV
echo "setup done"
