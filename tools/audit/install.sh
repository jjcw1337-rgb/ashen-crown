#!/bin/bash
# Installs the Codex standards audit (tools/audit/audit.sh) as a launchd job on the Game Factory Mac: after the
# night's mode job (23:30) and once in the afternoon (16:20); Blaine cut it from six runs a day to two, 2026-11-02.
# Re-run to update.
#   bash tools/audit/install.sh
set -eu
# Blaine turned the audit off on 2026-11-03 ("i dont think they are helping"): the job is unloaded and its plist
# moved to ~/Library/LaunchAgents/disabled. Pass --force to install it again.
if [ "${1:-}" != "--force" ]; then echo "audit is off (Blaine, 2026-11-03); pass --force to reinstall"; exit 0; fi
HERE=$(cd "$(dirname "$0")" && pwd)
RUNNER=/Users/blaine/dev/ashen-crown-nightly-runner
P=/Users/blaine/Library/LaunchAgents/com.gamefactory.ashen-audit.plist
U=gui/$(id -u)
mkdir -p "$RUNNER" /Users/blaine/Library/Logs/ashen-nightly
install -m 755 "$HERE/audit.sh" "$RUNNER/audit.sh"
install -m 644 "$HERE/fetch_requests.py" "$RUNNER/fetch_requests.py"
install -m 644 "$HERE/../nightly/post_discord.py" "$RUNNER/post_discord.py"
times=""
for t in 23:30 16:20; do
  times="$times<dict><key>Hour</key><integer>${t%%:*}</integer><key>Minute</key><integer>$((10#${t##*:}))</integer></dict>"
done
cat > "$P" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- The Codex standards audit (tools/audit/audit.sh), made by tools/audit/install.sh: 23:30 (after the mode job)
     and 16:20. Mac local time. -->
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
echo "audit: 23:30 16:20"
