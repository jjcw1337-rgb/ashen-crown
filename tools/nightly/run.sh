#!/bin/bash
# The nightly lab (docs/nightly/README.md): three jobs, each its own launchd job, run, test gate, push and report:
#   bash tools/nightly/run.sh mode     20:00, the game-mode job (tools/nightly/mode_prompt.md, 3.5 h limit)
#   bash tools/nightly/run.sh perf     00:30, the performance job (tools/nightly/perf_prompt.md, 3 h limit)
#   bash tools/nightly/run.sh triage   05:00, the triage job: players' errors, crashes and slow spots
#                                      (tools/nightly/triage_prompt.md, 2 h limit)
# (NIGHTLY_SMOKE=1: tiny prompts, no benchmark, pushes to test-nightly-smoke, posts nothing). Each run:
#  1. a fresh copy of origin/staging in its own worktree (~/dev/ashen-crown-nightly), imported from scratch
#  2. the runner's own benchmark of it (tools/nightly/bench.sh: the KPI scenarios, docs/nightly/KPIS.md), into the
#     KPI store
#  3. the job: a headless Claude session with its prompt; it reads and adds to its log (docs/nightly/<perf|modes|
#     triage>/LOG.md: lessons, then one short row per attempt, linking the detailed write-up)
#  4. the benchmark again; tools/nightly/bench_compare.py adds the scoreboard row to the job's log and blocks the ship
#     if the game got slower (measured twice before it says so)
#  5. costs -> docs/nightly/costs.jsonl, the report -> docs/nightly/nights/<date>-<job>.md, committed
#  6. the gate (tools/nightly/gate.sh): green (and not slower) -> rebased onto the latest staging and pushed to
#     `staging` (never forced; itch and the staging build follow) and the staging server deployed; otherwise pushed to
#     test-nightly-<date>-<job> and the report says why
#  7. the report goes to Discord (tools/nightly/post_discord.py) once itch has the build (after the lock is released,
#     so the next job can start)
# Robustness: one job at a time (a lock; the next job waits for it), every step logged to
# ~/Library/Logs/ashen-nightly/<date>-<job>.log, a watchdog per phase, the Mac kept awake while it runs, a status file
# (~/Library/Application Support/ashen-nightly/status-<job>.json), and a failure in any step still gives a report.
set -u
export PATH="/Users/blaine/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME=/Users/blaine
SELF_DIR=$(cd "$(dirname "$0")" && pwd)     # (the runner's own folder: its post_discord.py for notes)
JOB=${1:-perf}
case $JOB in
  perf) PROMPT=tools/nightly/perf_prompt.md; LIMIT=10800; JOBLOG=docs/nightly/perf/LOG.md ;;
  mode) PROMPT=tools/nightly/mode_prompt.md; LIMIT=12600; JOBLOG=docs/nightly/modes/LOG.md ;;
  triage) PROMPT=tools/nightly/triage_prompt.md; LIMIT=7200; JOBLOG=docs/nightly/triage/LOG.md ;;
  # started by tools/nightly/watch.py on a serious alert: the triage job on that one issue ($STATE/hotfix_focus.json)
  hotfix) PROMPT=tools/nightly/triage_prompt.md; LIMIT=3600; JOBLOG=docs/nightly/triage/LOG.md ;;
  *) echo "unknown job $JOB"; exit 2 ;;
esac
DATE=$(date +%Y-%m-%d)
SMOKE=${NIGHTLY_SMOKE:-0}
[ "$SMOKE" = 1 ] && DATE="$DATE-smoke"
[ "$JOB" = hotfix ] && DATE="$DATE-$(date +%H%M)"      # (several a day)
MAIN=/Users/blaine/dev/ashen-crown
WT=/Users/blaine/dev/ashen-crown-nightly
STATE="/Users/blaine/Library/Application Support/ashen-nightly"
OUT="$STATE/$DATE-$JOB"
LOGDIR=/Users/blaine/Library/Logs/ashen-nightly
LOG=$LOGDIR/$DATE-$JOB.log
G=/Users/blaine/Applications/Godot_v4.3.app/Contents/MacOS/Godot
PY="/Users/blaine/Documents/Game Factory Audio/venv/bin/python"
MESHY_CAP=${NIGHTLY_MESHY_CAP:-150}
ELEVEN_CAP=${NIGHTLY_ELEVEN_CAP:-1500}
mkdir -p "$OUT" "$LOGDIR"
exec >> "$LOG" 2>&1
echo "=== nightly $DATE $JOB start $(date)"

# one job at a time: wait (up to 5 h) for one still running; take over a dead one's lock
LOCK=/tmp/ashen-nightly.lock
got=0
for i in $(seq 1 3600); do
  if mkdir "$LOCK" 2>/dev/null; then got=1; break; fi
  if ! kill -0 "$(cat $LOCK/pid 2>/dev/null)" 2>/dev/null; then
    sleep 2; kill -0 "$(cat $LOCK/pid 2>/dev/null)" 2>/dev/null || rm -rf "$LOCK"; continue     # (its pid may not be written yet)
  fi
  [ "$i" = 1 ] && echo "waiting for the $(cat $LOCK/job 2>/dev/null) job, still running"
  sleep 5
done
[ $got = 1 ] || { echo "gave up waiting"; exit 0; }
echo $$ > $LOCK/pid; echo "$JOB" > $LOCK/job
trap 'rm -rf "$LOCK"' EXIT
caffeinate -dimsu -w $$ &

STEP=start
status() {  # step, state, note
  STEP=$1
  printf '{"date":"%s","step":"%s","state":"%s","note":"%s","at":"%s"}\n' "$DATE" "$1" "$2" "$3" "$(date -u +%FT%TZ)" > "$STATE/status-$JOB.json"
  echo "--- [$1] $2 $3 ($(date +%T))"
}
FAILED=""
fail() { FAILED="$FAILED $1"; status "$1" failed "$2"; }
# a short note to Discord when a run can't give its report (it couldn't start, or something killed it)
note() { [ "$SMOKE" = 1 ] || python3 -I "$SELF_DIR/post_discord.py" --text "⚠️ The $JOB run $DATE $1 (log: ~/Library/Logs/ashen-nightly/$DATE-$JOB.log)" || true; }
trap 'status "$STEP" interrupted ""; note "was stopped (signal) during $STEP, so there is no report"; exit 1' TERM INT HUP

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
# (clean first: files an import left that are now committed would stop the checkout)
git reset -q --hard; git clean -qfdx
git checkout -q -f -B "nightly-$DATE-$JOB" origin/staging && git reset -q --hard origin/staging && git clean -qfdx
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/staging)" ]; then
  fail prepare "not on the latest staging"; note "couldn't start: its checkout isn't on the latest staging"; exit 1
fi
BASE=$(git rev-parse --short HEAD)
"$G" --headless --path . --import > "$OUT/import.log" 2>&1     # (from scratch, as CI does: ~1 min)
status prepare done "staging $BASE"

# `echo "why" > "$STATE/skip_<job>_once"`: skip the job for one night (e.g. while a person is rebuilding what it would
# build on); the report says it was skipped and why (the file's text)
SKIP=0
if [ -f "$STATE/skip_${JOB}_once" ]; then
  cp "$STATE/skip_${JOB}_once" "$OUT/${JOB}_skipped.txt"
  rm -f "$STATE/skip_${JOB}_once"; SKIP=1
fi

# a hotfix run's one issue (tools/nightly/watch.py); it measures the KPIs only for a slow spot
BENCH=1
if [ "$JOB" = hotfix ]; then
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["what"])' "$STATE/hotfix_focus.json" > "$OUT/focus.txt" 2>/dev/null || echo "(no focus found)" > "$OUT/focus.txt"
  grep -q "^slow spot" "$OUT/focus.txt" || BENCH=0
fi

# 2. the runner's benchmark of the starting point
if [ "$SMOKE" != 1 ] && [ $SKIP = 0 ] && [ $BENCH = 1 ]; then
  status bench running "before"; bash tools/nightly/bench.sh "$OUT/bench" before
  python3 -I tools/nightly/kpi_push.py "$OUT/bench/before.json" "$DATE" "$JOB" before "$BASE" || fail kpi "push to the KPI store"
  status bench done "before"
fi

# 3. the job
phase() {  # name, prompt file, seconds
  local name=$1 prompt=$2 lim=$3
  status "$name" running ""
  local p
  if [ "$SMOKE" = 1 ]; then
    p="Smoke test of the nightly pipeline, phase $name. Do not change any game code. Append one line '- smoke $DATE ($name)' to docs/nightly/smoke.md (create it), write $OUT/${name}_summary.md with one line saying the pipeline works, and commit it on the current branch. Don't push."
  else
    local dl; dl=$(date -v+$((lim / 60 - 15))M +%H:%M)     # (the prompt's own deadline: 15 min before the watchdog)
    p=$(sed -e "s|{{DATE}}|$DATE|g" -e "s|{{OUT}}|$OUT|g" -e "s|{{DEADLINE}}|$dl|g" -e "s|{{MESHY_CAP}}|$MESHY_CAP|g" -e "s|{{ELEVEN_CAP}}|$ELEVEN_CAP|g" "$prompt")
  fi
  run_limited "$lim" claude -p "$p" --output-format json --permission-mode bypassPermissions --model claude-opus-5-5 \
    > "$OUT/${name}_result.json" 2> "$OUT/${name}_stderr.log"
  local rc=$?
  if [ $rc -ne 0 ]; then fail "$name" "exit $rc"; else status "$name" done ""; fi
  git add -A docs/nightly 2>/dev/null; git diff --cached --quiet || git commit -q -m "Nightly $DATE: $name notes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
}
if [ $SKIP = 1 ]; then
  status "$JOB" skipped "skip_${JOB}_once"
else
  phase "$JOB" "$PROMPT" "$LIMIT"
fi

# 4. the benchmark again: the scoreboard row in the job's log, and no shipping a slower game
SLOWER=0
if [ "$SMOKE" != 1 ] && [ $SKIP = 0 ] && [ $BENCH = 1 ]; then
  status bench running "after"
  git clean -qfdX; "$G" --headless --path . --import > "$OUT/import_after.log" 2>&1     # (fresh, so new import settings count)
  bash tools/nightly/bench.sh "$OUT/bench" after
  # (a single blocked verdict could be noise: measure the result once more and keep its better runs)
  if ! python3 -I tools/nightly/bench_compare.py "$OUT/bench/before.json" "$OUT/bench/after.json" "$DATE" "$JOB" /dev/null --check > /dev/null; then
    bash tools/nightly/bench.sh "$OUT/bench" after2
    python3 -I tools/nightly/bench_compare.py "$OUT/bench/after.json" "$OUT/bench/after2.json" --merge "$OUT/bench/after.json"
  fi
  python3 -I tools/nightly/kpi_push.py "$OUT/bench/after.json" "$DATE" "$JOB" after "$(git rev-parse --short HEAD)" || fail kpi "push to the KPI store"
  if python3 -I tools/nightly/bench_compare.py "$OUT/bench/before.json" "$OUT/bench/after.json" "$DATE" "$JOB" "$JOBLOG" > "$OUT/bench.md"; then
    status bench done "after: ok"
  else
    SLOWER=1; fail bench "slower than before, or the benchmark failed (see bench.md)"
  fi
fi

# 5. costs and the report
status report running ""
"$PY" -I tools/nightly/report.py "$JOB" "$DATE" "$OUT" "$BASE" "${FAILED:-none}" || fail report "report.py"
git add -A docs/nightly; git diff --cached --quiet || git commit -q -m "Nightly $DATE: $JOB report and costs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
status report done ""

# 6. the gate, then staging (or a test branch)
status gate running ""
TARGET=staging
[ "$SMOKE" = 1 ] && TARGET=test-nightly-smoke
if bash tools/nightly/gate.sh "$OUT" > "$OUT/gate.log" 2>&1; then
  status gate done "green"
else
  fail gate "tests failed (see gate.log)"
  TARGET="test-nightly-$DATE-$JOB"
fi
[ "$SLOWER" = 1 ] && TARGET="test-nightly-$DATE-$JOB"
git fetch -q origin
if [ "$TARGET" = staging ]; then
  if git rebase -q origin/staging; then
    git push -q origin HEAD:staging || { fail push "push to staging rejected"; TARGET="test-nightly-$DATE-$JOB"; git push -q origin HEAD:"$TARGET"; }
  else
    git rebase --abort; fail push "rebase onto staging conflicted"; TARGET="test-nightly-$DATE-$JOB"; git push -q origin HEAD:"$TARGET"
  fi
else
  git push -q -f origin HEAD:"$TARGET"   # (a test-nightly branch belongs to this run alone)
fi
echo "$TARGET" > "$OUT/target.txt"
status push done "$TARGET $(git rev-parse --short HEAD)"

if [ "$TARGET" = staging ]; then
  status deploy running ""
  sh deploy/staging/deploy.sh > "$OUT/deploy.log" 2>&1 && status deploy done "" || fail deploy "deploy.sh (see deploy.log)"
fi
# the next job may start now; this one only waits for itch and posts
rm -rf "$LOCK"; trap - EXIT

# 7. Discord, once the staging build has reached itch (up to 45 min), so the report's link has the new build
if [ "$TARGET" = staging ]; then
  sleep 30
  RUN=$(gh run list -R jjcw1337-rgb/ashen-crown --branch staging --limit 1 --json databaseId -q '.[0].databaseId')
  [ -n "$RUN" ] && run_limited 2700 gh run watch "$RUN" -R jjcw1337-rgb/ashen-crown --exit-status > /dev/null 2>&1 \
    && echo "itch-ok" > "$OUT/itch.txt" || echo "itch-pending" > "$OUT/itch.txt"
fi
if [ "$SMOKE" != 1 ]; then
  "$PY" -I tools/nightly/post_discord.py "$OUT" "docs/nightly/nights/$DATE-$JOB.md" "$FAILED" && status discord done "" || fail discord "post"
fi
status finished "$([ -z "$FAILED" ] && echo ok || echo partial)" "${FAILED:-}"
echo "=== nightly $DATE $JOB end $(date)"
