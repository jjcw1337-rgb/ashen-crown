#!/bin/bash
# The Codex standards audit (Blaine, 2026-11-01): a read-only Codex run (ChatGPT's CLI, signed in on this Mac) that
# checks what the admins asked for on Discord and what was built since the last audit, against the project's
# standards (tools/audit/audit_prompt.md), and posts its findings to the Game Factory channel. It never edits,
# builds or runs the game. Scheduled by tools/audit/install.sh at 23:30 and 16:20.
#   bash tools/audit/audit.sh [--dry]      (--dry: print the report instead of posting it)
set -u
CODEX=/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex
SRC=/Users/blaine/dev/ashen-crown-staging            # the repository (its objects; the audit reads its own worktree)
WT=/Users/blaine/dev/ashen-crown-audit
STATE="/Users/blaine/Library/Application Support/ashen-audit"
RUNNER=/Users/blaine/dev/ashen-crown-nightly-runner
LOGS=/Users/blaine/Library/Logs/ashen-nightly
NIGHTLY="/Users/blaine/Library/Application Support/ashen-nightly"
mkdir -p "$STATE" "$LOGS"
STAMP=$(date +%Y-%m-%d-%H%M)
OUT="$STATE/$STAMP"
mkdir -p "$OUT"
exec >> "$LOGS/audit.log" 2>&1
echo "== audit $STAMP"
post() { [ "${DRY:-0}" = 1 ] && { cat "$1"; return; }; /usr/bin/python3 -I "$RUNNER/post_discord.py" --file "$1" "$2"; }
[ "${1:-}" = --dry ] && DRY=1
# a clean, detached worktree at origin/staging (nobody works in it; the session's and the nightly's checkouts are left alone)
git -C "$SRC" fetch -q origin || echo "fetch failed"
if [ ! -d "$WT/.git" ] && [ ! -f "$WT/.git" ]; then
  git -C "$SRC" worktree add -q --detach "$WT" origin/staging || { echo "no worktree"; exit 1; }
fi
git -C "$WT" checkout -q --detach --force origin/staging
HEAD_SHA=$(git -C "$WT" rev-parse HEAD)
LAST=$(cat "$STATE/last_sha" 2>/dev/null || git -C "$WT" rev-parse HEAD~15)
LAST_T=$(cat "$STATE/last_time" 2>/dev/null || echo $(( $(date +%s) - 86400 )))
HOURS=$(( ( $(date +%s) - LAST_T ) / 3600 + 1 ))
/usr/bin/python3 -I "$RUNNER/fetch_requests.py" "$HOURS" > "$OUT/requests.txt" 2> "$OUT/requests.err" || echo "(couldn't read Discord)" > "$OUT/requests.txt"
{
  cat "$WT/tools/audit/audit_prompt.md"
  echo
  echo "## Context for this audit ($(date '+%Y-%m-%d %H:%M %Z'))"
  echo "- Worktree (read this, not other checkouts): $WT at origin/staging $HEAD_SHA"
  echo "- Commits to review: \`git -C $WT log --stat $LAST..$HEAD_SHA\` ($(git -C "$WT" rev-list --count "$LAST..$HEAD_SHA" 2>/dev/null || echo '?') commits; also \`git -C $SRC log origin/main -5\` for main)"
  echo "- Admin requests from Discord, the last $HOURS hours: $OUT/requests.txt"
  echo "- Nightly job status files: $NIGHTLY/status-*.json; their logs: $LOGS/*.log (look at the tails of the newest)"
  echo "- Nightly schedule: mode 20:00, perf 00:30, triage 05:00 (Mac local time), plus hotfix runs from the telemetry watcher."
} > "$OUT/prompt.md"
"$CODEX" exec -s read-only --skip-git-repo-check --ephemeral -C "$WT" --add-dir "$STATE" \
  -o "$OUT/report.md" - < "$OUT/prompt.md" > "$OUT/codex.log" 2>&1
rc=$?
if [ $rc -ne 0 ] || [ ! -s "$OUT/report.md" ]; then
  echo "codex failed ($rc)"; tail -5 "$OUT/codex.log"
  echo "The Codex audit couldn't run at $(date '+%H:%M') (exit $rc). Log: ~/Library/Application Support/ashen-audit/$STAMP/codex.log" > "$OUT/fail.md"
  post "$OUT/fail.md" "🔎 **Codex audit**"
  exit 1
fi
post "$OUT/report.md" "🔎 **Codex standards audit** · $(date '+%a %H:%M') · staging \`${HEAD_SHA:0:7}\` (read only)"
[ "${DRY:-0}" = 1 ] || { echo "$HEAD_SHA" > "$STATE/last_sha"; date +%s > "$STATE/last_time"; }
echo "done"
