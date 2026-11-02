#!/bin/bash
# Installs the Codex standards audit (tools/audit/audit.sh) as a launchd job on the Game Factory Mac: around each
# nightly job (before mode, after mode, after perf, after triage) and twice in the day. Re-run to update.
#   bash tools/audit/install.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
RUNNER=/Users/blaine/dev/ashen-crown-nightly-runner
P=/Users/blaine/Library/LaunchAgents/com.gamefactory.ashen-audit.plist
U=gui/$(id -u)
mkdir -p "$RUNNER" /Users/blaine/Library/Logs/ashen-nightly
install -m 755 "$HERE/audit.sh" "$RUNNER/audit.sh"
install -m 644 "$HERE/fetch_requests.py" "$RUNNER/fetch_requests.py"
install -m 644 "$HERE/../nightly/post_discord.py" "$RUNNER/post_discord.py"
times=""
for t in 19:40 23:30 2:30 7:30 12:50 16:20; do
  times="$times<dict><key>Hour</key><integer>${t%%:*}</integer><key>Minute</key><integer>$((10#${t##*:}))</integer></dict>"
done
cat > "$P" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- The Codex standards audit (tools/audit/audit.sh), made by tools/audit/install.sh: 19:40 (before the mode job),
     23:30 (after it), 2:30 (after perf), 7:30 (after triage), 12:50 and 16:20. Mac local time. -->
<plist version="1.0">
<dict>
  <key>Label</key><string>com.gamefactory.ashen-audit</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$RUNNER/audit.sh</string></array>
  <key>StartCalendarInterval</key><array>$times</array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/Users/blaine/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>StandardOutPath</key><string>/Users/blaine/Library/Logs/ashen-nightly/audit.log</string>
  <key>StandardErrorPath</key><string>/Users/blaine/Library/Logs/ashen-nightly/audit.log</string>
</dict>
</plist>
PLIST
plutil -lint "$P"
launchctl bootout $U/com.gamefactory.ashen-audit 2>/dev/null || true
launchctl bootstrap $U "$P"
echo "audit: 19:40 23:30 2:30 7:30 12:50 16:20"
