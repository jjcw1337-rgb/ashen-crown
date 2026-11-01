#!/bin/sh
# CI: uploads the exported builds to itch.io with butler (itch's official uploader). The itch desktop app then
# installs and auto-updates them.
#   sh tools/ci/itch_upload.sh <user/game> <channel suffix> <version>
# Needs BUTLER_API_KEY (an itch.io API key) in the environment. Content: build/win, build/mac, build/linux, pushed to
# the channels windows-<suffix>, mac-<suffix>, linux-<suffix> (itch tags the platform from the channel name).
# ITCH_DRY_RUN=1 prints the commands without uploading. Never prints the key.
set -eu
TARGET=$1; SUFFIX=$2; VERSION=$3
echo "$TARGET" | grep -Eq '^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$' || { echo "target must be user/game"; exit 1; }
echo "$SUFFIX" | grep -Eq '^[a-z0-9-]+$' || { echo "bad channel suffix"; exit 1; }
[ -n "${BUTLER_API_KEY:-}" ] || { echo "BUTLER_API_KEY missing"; exit 1; }
for d in win mac linux; do [ -n "$(ls build/$d 2>/dev/null)" ] || { echo "build/$d is empty"; exit 1; }; done
# launch manifests (.itch.toml): which file the itch app starts on each platform, plus Windows' safe mode
cat > build/win/.itch.toml <<'TOML'
[[actions]]
name = "play"
path = "AshenCrown.exe"

[[actions]]
name = "Safe Mode (OpenGL)"
path = "AshenCrown.exe"
args = ["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"]
TOML
APP=$(cd build/mac && ls -d *.app | head -1)
printf '[[actions]]\nname = "play"\npath = "%s"\n' "$APP" > build/mac/.itch.toml
printf '[[actions]]\nname = "play"\npath = "AshenCrown.x86_64"\n' > build/linux/.itch.toml
B=build/butler/butler
if [ "${ITCH_DRY_RUN:-0}" = 1 ]; then
  B="echo butler"
else
  mkdir -p build/butler
  curl -fsSL -o build/butler/butler.zip https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default
  (cd build/butler && unzip -q -o butler.zip && chmod +x butler)
  $B -V
fi
$B push build/win "$TARGET:windows-$SUFFIX" --userversion "$VERSION"
$B push build/mac "$TARGET:mac-$SUFFIX" --userversion "$VERSION"
$B push build/linux "$TARGET:linux-$SUFFIX" --userversion "$VERSION"
[ "${ITCH_DRY_RUN:-0}" = 1 ] || $B status "$TARGET"
