#!/bin/bash
# Installs (or updates) the nightly lab on the Game Factory Mac: the runner copy of run.sh and one launchd job per
# nightly job (from nightly.plist.in): mode at 20:00, perf at 00:30, triage at 05:00.
#   bash tools/nightly/install.sh            (from any checkout that has tools/nightly)
#   bash tools/nightly/install.sh --smoke    (also runs a smoke test of the perf job now under launchd: tiny prompt,
#                                             test-nightly-smoke branch, no benchmark, no deploy, no Discord)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
RUNNER=/Users/blaine/dev/ashen-crown-nightly-runner
AGENTS=/Users/blaine/Library/LaunchAgents
U=gui/$(id -u)
mkdir -p "$RUNNER" "$AGENTS" /Users/blaine/Library/Logs/ashen-nightly
install -m 755 "$HERE/run.sh" "$RUNNER/run.sh"
# (the single job of before 2026-11-01)
launchctl bootout $U/com.gamefactory.ashen-nightly 2>/dev/null || true
rm -f "$AGENTS/com.gamefactory.ashen-nightly.plist"
for spec in mode:20:0 perf:0:30 triage:5:0; do
  job=${spec%%:*}; t=${spec#*:}; h=${t%%:*}; m=${t##*:}
  P=$AGENTS/com.gamefactory.ashen-nightly-$job.plist
  sed -e "s|@JOB@|$job|g" -e "s|@HOUR@|$h|g" -e "s|@MINUTE@|$m|g" "$HERE/nightly.plist.in" > "$P"
  plutil -lint "$P"
  launchctl bootout $U/com.gamefactory.ashen-nightly-$job 2>/dev/null || true
  launchctl bootstrap $U "$P"
  echo "$job: $(launchctl print $U/com.gamefactory.ashen-nightly-$job | grep -cE 'state') job loaded, $h:$m"
done
if [ "${1:-}" = --smoke ]; then
  S=$AGENTS/com.gamefactory.ashen-nightly-smoke.plist
  sed -e 's|com.gamefactory.ashen-nightly-perf<|com.gamefactory.ashen-nightly-smoke<|' \
      -e 's|<key>StartCalendarInterval</key>|<key>RunAtLoad</key><true/><key>EnvironmentVariables</key><dict><key>NIGHTLY_SMOKE</key><string>1</string></dict><key>_unused</key>|' \
      "$AGENTS/com.gamefactory.ashen-nightly-perf.plist" > "$S"
  plutil -lint "$S"
  launchctl bootout $U/com.gamefactory.ashen-nightly-smoke 2>/dev/null || true
  launchctl bootstrap $U "$S"
  echo "smoke run started under launchd; log: ~/Library/Logs/ashen-nightly/$(date +%Y-%m-%d)-smoke-perf.log"
fi
