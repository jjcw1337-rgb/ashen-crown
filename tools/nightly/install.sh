#!/bin/bash
# Installs (or updates) the nightly lab on the Game Factory Mac: the runner copy of run.sh and one launchd job per
# nightly job (from nightly.plist.in): perf at 00:30, triage at 05:00. (The 20:00 game-mode job was removed by Blaine,
# 2026-11-03; run.sh mode still works by hand.)
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
# (the single job of before 2026-11-01, and the game-mode job, removed 2026-11-03)
for old in com.gamefactory.ashen-nightly com.gamefactory.ashen-nightly-mode; do
  launchctl bootout $U/$old 2>/dev/null || true
  rm -f "$AGENTS/$old.plist"
done
for spec in perf:0:30 triage:5:0; do
  job=${spec%%:*}; t=${spec#*:}; h=${t%%:*}; m=${t##*:}
  P=$AGENTS/com.gamefactory.ashen-nightly-$job.plist
  sed -e "s|@JOB@|$job|g" -e "s|@HOUR@|$h|g" -e "s|@MINUTE@|$m|g" "$HERE/nightly.plist.in" > "$P"
  plutil -lint "$P"
  launchctl bootout $U/com.gamefactory.ashen-nightly-$job 2>/dev/null || true
  launchctl bootstrap $U "$P"
  echo "$job: $(launchctl print $U/com.gamefactory.ashen-nightly-$job | grep -cE 'state') job loaded, $h:$m"
done
# the telemetry watcher (watch.py): alerts and hotfix runs, every 5 minutes
install -m 644 "$HERE/watch.py" "$RUNNER/watch.py"
install -m 644 "$HERE/post_discord.py" "$RUNNER/post_discord.py"     # (run.sh's notes, whatever the checkout holds)
W=$AGENTS/com.gamefactory.ashen-watch.plist
cat > "$W" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- The telemetry watcher (tools/nightly/watch.py, docs/nightly/TELEMETRY.md): every 5 minutes. Made by install.sh. -->
<plist version="1.0">
<dict>
  <key>Label</key><string>com.gamefactory.ashen-watch</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/python3</string><string>-I</string><string>$RUNNER/watch.py</string></array>
  <key>StartInterval</key><integer>300</integer>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/Users/blaine/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>StandardOutPath</key><string>/Users/blaine/Library/Logs/ashen-nightly/watch.log</string>
  <key>StandardErrorPath</key><string>/Users/blaine/Library/Logs/ashen-nightly/watch.log</string>
</dict>
</plist>
PLIST
plutil -lint "$W"
launchctl bootout $U/com.gamefactory.ashen-watch 2>/dev/null || true
launchctl bootstrap $U "$W"
echo "watch: every 5 min"
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
