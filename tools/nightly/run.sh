#!/bin/bash
# The nightly lab (docs/nightly/README.md). launchd starts it at 03:00 (tools/nightly/com.gamefactory.ashen-nightly.plist);
# by hand: `bash tools/nightly/run.sh` (NIGHTLY_SMOKE=1: tiny prompts, pushes to test-nightly-smoke, posts nothing).
#  1. a fresh copy of origin/staging in its own worktree (~/dev/ashen-crown-nightly), imported
#  2. phase "perf": a headless Claude session with tools/nightly/perf_prompt.md (3 h limit)
#  3. phase "mode": a headless Claude session with tools/nightly/mode_prompt.md (3.5 h limit)
#  4. costs (Claude per phase from its own report, Meshy/ElevenLabs as each phase recorded) -> docs/nightly/costs.jsonl,
#     the morning report -> docs/nightly/nights/<date>.md, committed
#  5. the gate (tools/nightly/gate.sh: the test suite incl. the server+client and host+join pairs): green -> rebased
#     onto the latest staging and pushed to `staging` (never forced; itch and the staging build follow) and the staging
#     server deployed; red -> pushed to test-nightly-<date> instead and the report says why
#  6. the report goes to the Discord channel (tools/nightly/post_discord.py), with the images, once itch has the build
# Robustness: one run at a time (lock), every step logged to ~/Library/Logs/ashen-nightly/<date>.log, a watchdog per
# phase, the Mac kept awake while it runs, a status file (~/Library/Application Support/ashen-nightly/status.json),
# and a failure in any step still produces a report saying what failed.
set -u
export PATH="/Users/blaine/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME=/Users/blaine
DATE=$(date +%Y-%m-%d)
SMOKE=${NIGHTLY_SMOKE:-0}
[ "$SMOKE" = 1 ] && DATE="$DATE-smoke"
MAIN=/Users/blaine/dev/ashen-crown
WT=/Users/blaine/dev/ashen-crown-nightly
STATE="/Users/blaine/Library/Application Support/ashen-nightly"
OUT="$STATE/$DATE"
LOGDIR=/Users/blaine/Library/Logs/ashen-nightly
LOG=$LOGDIR/$DATE.log
G=/Users/blaine/Applications/Godot_v4.3.app/Contents/MacOS/Godot
PY="/Users/blaine/Documents/Game Factory Audio/venv/bin/python"
MESHY_CAP=${NIGHTLY_MESHY_CAP:-150}
ELEVEN_CAP=${NIGHTLY_ELEVEN_CAP:-1500}
mkdir -p "$OUT" "$LOGDIR"
exec >> "$LOG" 2>&1
echo "=== nightly $DATE start $(date)"

LOCK=/tmp/ashen-nightly.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  if kill -0 "$(cat $LOCK/pid 2>/dev/null)" 2>/dev/null; then echo "another run is going, exiting"; exit 0; fi
  rm -rf "$LOCK"; mkdir "$LOCK"
fi
echo $$ > $LOCK/pid
trap 'rm -rf "$LOCK"' EXIT
caffeinate -dimsu -w $$ &

status() {  # step, state, note
  printf '{"date":"%s","step":"%s","state":"%s","note":"%s","at":"%s"}\n' "$DATE" "$1" "$2" "$3" "$(date -u +%FT%TZ)" > "$STATE/status.json"
  echo "--- [$1] $2 $3 ($(date +%T))"
}
FAILED=""
fail() { FAILED="$FAILED $1"; status "$1" failed "$2"; }

# run_limited <seconds> <cmd...>: runs it, kills it after the limit
run_limited() {
  local lim=$1; shift
  "$@" & local p=$!
  ( sleep "$lim"; kill -TERM $p 2>/dev/null; sleep 30; kill -KILL $p 2>/dev/null ) & local w=$!
  wait $p; local rc=$?
  kill $w 2>/dev/null
  return $rc
}

# 1. fresh staging
status prepare running ""
git -C "$MAIN" fetch -q origin || { fail prepare "git fetch"; }
if [ ! -d "$WT/.git" ] && [ ! -f "$WT/.git" ]; then
  git -C "$MAIN" worktree add -f "$WT" origin/staging || fail prepare "worktree"
fi
cd "$WT" || exit 1
git fetch -q origin
git checkout -q -B "nightly-$DATE" origin/staging && git reset -q --hard origin/staging && git clean -qfd
BASE=$(git rev-parse --short HEAD)
"$G" --headless --path . --import > "$OUT/import.log" 2>&1
status prepare done "staging $BASE"

# 2-3. the two Claude phases
phase() {  # name, prompt file, seconds
  local name=$1 prompt=$2 lim=$3
  status "$name" running ""
  local p
  if [ "$SMOKE" = 1 ]; then
    p="Smoke test of the nightly pipeline, phase $name. Do not change any game code. Append one line '- smoke $DATE ($name)' to docs/nightly/smoke.md (create it), write $OUT/${name}_summary.md with one line saying the pipeline works, and commit it on the current branch. Don't push."
  else
    p=$(sed -e "s|{{DATE}}|$DATE|g" -e "s|{{OUT}}|$OUT|g" -e "s|{{MESHY_CAP}}|$MESHY_CAP|g" -e "s|{{ELEVEN_CAP}}|$ELEVEN_CAP|g" "$prompt")
  fi
  run_limited "$lim" claude -p "$p" --output-format json --permission-mode bypassPermissions --model claude-opus-5-5 \
    > "$OUT/${name}_result.json" 2> "$OUT/${name}_stderr.log"
  local rc=$?
  if [ $rc -ne 0 ]; then fail "$name" "exit $rc"; else status "$name" done ""; fi
  git add -A docs/nightly 2>/dev/null; git diff --cached --quiet || git commit -q -m "Nightly $DATE: $name notes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
}
phase perf tools/nightly/perf_prompt.md 10800
# `echo "why" > "$STATE/skip_mode_once"`: skip the new-mode phase for one night (e.g. while a person is rebuilding the
# mode); the report says it was skipped and why (the file's text)
if [ -f "$STATE/skip_mode_once" ]; then
  cp "$STATE/skip_mode_once" "$OUT/mode_skipped.txt"
  rm -f "$STATE/skip_mode_once"; status mode skipped "skip_mode_once"
else
  phase mode tools/nightly/mode_prompt.md 12600
fi

# 4. costs and the report
status report running ""
"$PY" -I tools/nightly/report.py "$DATE" "$OUT" "$BASE" "${FAILED:-none}" || fail report "report.py"
git add -A docs/nightly; git diff --cached --quiet || git commit -q -m "Nightly $DATE: report and costs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
status report done ""

# 5. the gate, then staging (or a test branch)
status gate running ""
TARGET=staging
[ "$SMOKE" = 1 ] && TARGET=test-nightly-smoke
if bash tools/nightly/gate.sh "$OUT" > "$OUT/gate.log" 2>&1; then
  status gate done "green"
else
  fail gate "tests failed (see gate.log)"
  TARGET="test-nightly-$DATE"
fi
git fetch -q origin
if [ "$TARGET" = staging ]; then
  if git rebase -q origin/staging; then
    git push -q origin HEAD:staging || { fail push "push to staging rejected"; TARGET="test-nightly-$DATE"; git push -q origin HEAD:"$TARGET"; }
  else
    git rebase --abort; fail push "rebase onto staging conflicted"; TARGET="test-nightly-$DATE"; git push -q origin HEAD:"$TARGET"
  fi
else
  git push -q -f origin HEAD:"$TARGET"   # (a test-nightly branch belongs to this run alone)
fi
echo "$TARGET" > "$OUT/target.txt"
status push done "$TARGET $(git rev-parse --short HEAD)"

if [ "$TARGET" = staging ]; then
  status deploy running ""
  sh deploy/staging/deploy.sh > "$OUT/deploy.log" 2>&1 && status deploy done "" || fail deploy "deploy.sh (see deploy.log)"
  # wait for the staging build to reach itch (up to 45 min), so the report's link has the new build
  sleep 30
  RUN=$(gh run list -R jjcw1337-rgb/ashen-crown --branch staging --limit 1 --json databaseId -q '.[0].databaseId')
  [ -n "$RUN" ] && run_limited 2700 gh run watch "$RUN" -R jjcw1337-rgb/ashen-crown --exit-status > /dev/null 2>&1 \
    && echo "itch-ok" > "$OUT/itch.txt" || echo "itch-pending" > "$OUT/itch.txt"
fi

# 6. Discord
if [ "$SMOKE" != 1 ]; then
  "$PY" -I tools/nightly/post_discord.py "$OUT" "docs/nightly/nights/$DATE.md" && status discord done "" || fail discord "post"
fi
status finished "$([ -z "$FAILED" ] && echo ok || echo partial)" "${FAILED:-}"
echo "=== nightly $DATE end $(date)"
