#!/bin/bash
# Installs (or updates) the nightly lab on the Game Factory Mac: the runner copy of run.sh and the launchd job.
#   bash tools/nightly/install.sh            (from any checkout that has tools/nightly)
#   bash tools/nightly/install.sh --smoke    (also runs a smoke test now under launchd: tiny prompts,
#                                             test-nightly-smoke branch, no deploy, no Discord)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
RUNNER=/Users/blaine/dev/ashen-crown-nightly-runner
AGENTS=/Users/blaine/Library/LaunchAgents
mkdir -p "$RUNNER" "$AGENTS" /Users/blaine/Library/Logs/ashen-nightly
install -m 755 "$HERE/run.sh" "$RUNNER/run.sh"
install -m 644 "$HERE/com.gamefactory.ashen-nightly.plist" "$AGENTS/com.gamefactory.ashen-nightly.plist"
plutil -lint "$AGENTS/com.gamefactory.ashen-nightly.plist"
launchctl bootout gui/$(id -u)/com.gamefactory.ashen-nightly 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$AGENTS/com.gamefactory.ashen-nightly.plist"
launchctl print gui/$(id -u)/com.gamefactory.ashen-nightly | grep -E 'state|path|Hour|Minute' | head -6
if [ "${1:-}" = --smoke ]; then
  S=$AGENTS/com.gamefactory.ashen-nightly-smoke.plist
  sed -e 's|com.gamefactory.ashen-nightly<|com.gamefactory.ashen-nightly-smoke<|' \
      -e 's|<key>StartCalendarInterval</key>|<key>RunAtLoad</key><true/><key>EnvironmentVariables</key><dict><key>NIGHTLY_SMOKE</key><string>1</string></dict><key>_unused</key>|' \
      "$AGENTS/com.gamefactory.ashen-nightly.plist" > "$S"
  plutil -lint "$S"
  launchctl bootout gui/$(id -u)/com.gamefactory.ashen-nightly-smoke 2>/dev/null || true
  launchctl bootstrap gui/$(id -u) "$S"
  echo "smoke run started under launchd; log: ~/Library/Logs/ashen-nightly/$(date +%Y-%m-%d)-smoke.log"
fi
