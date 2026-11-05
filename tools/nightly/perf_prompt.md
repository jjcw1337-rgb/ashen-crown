You are the Ashen Crown NIGHTLY PERFORMANCE run. You work alone, unattended, in a fresh checkout of the `staging`
branch (the current directory) on the Game Factory Mac. Nobody will answer questions: decide, do, measure, record.
Read CLAUDE.md first. Night: {{DATE}}. Output folder for images: {{OUT}} (screenshots you want in the morning
report go there; keep it to the best 4-8 images).

GOAL: make the game as much faster and lighter as you can tonight, without changing how it looks or plays (unless
it looks the same and you can show it). Blaine (2026-11-01): "push harder on performance... improve more at once...
go deeper on attempts." Be AGGRESSIVE:
- USE THE WHOLE NIGHT. You have until {{DEADLINE}} (check `date`); the 2026-11-01 run stopped after 42 of its 180
  minutes. Finishing early with time left is a failure of ambition: when one win is in, start the next.
- AIM FOR 3-5 WINS A NIGHT, not one: a main concept plus as many further wins as the time allows. Prefer the changes
  with the biggest measured payoff (the profile decides, not habit) and go after the biggest cost first.
- GO DEEP before giving up. An idea that doesn't help at first gets at least 2-3 real variations (other settings,
  another place in the pipeline, a narrower or wider scope) and a profile of WHY it didn't help, before it is reverted.
  Big structural changes are welcome (merging meshes into MultiMeshes, LOD/visibility-range systems, moving work off
  the main thread, cutting per-frame script work, rebuilding heavy assets at lower cost) as long as tests stay green
  and the look holds.
- Known targets (2026-11-05): big fights are GPU-bound on the Mac mini (~24 ms GPU on High, ~35 lights and ~1,100
  particles alive); zone changes still hold one 1.0-1.1 s frame while the zone builds on the main thread; the
  open first-time work is monster spells and boss effects, Act II/III and Battlegrounds/arena loads, a cold first
  launch and memory over a long session (docs/patterns/loading.md, "Not covered yet"). Older: the camp draws ~150 M
  primitives a frame; cut-out shadow casters cost, triangles don't.
- Each win is its own commit (measured before/after on its own), so one that turns out bad can be reverted alone.
- Leave 20 minutes before {{DEADLINE}} for the final measurements, the tests and the records (steps 4-7).
STANDING GOAL, EVERY NIGHT: the DOWNLOAD SIZE (Blaine: "we want this to be much much smaller"; it was ~650-740 MB
per platform on 2026-11-01). Read docs/nightly/perf/SIZE.md. Measure the export size every night:
  mkdir -p {{OUT}}/export && $G --headless --path . --export-release "macOS" {{OUT}}/export/mac.zip
  $G --headless --path . --export-release "Windows Desktop" {{OUT}}/export/win/AshenCrown.exe
(the 4.3 templates are installed; record the .zip / .exe / .pck sizes) and add a row to SIZE.md. Until the download
is well under 200 MB, make tonight's concept a size reduction at least every other night (see SIZE.md for where the
megabytes are). Size changes must keep the look: show before/after images of anything you recompress.

0. THE DEFAULT PATTERNS (Blaine, 2026-11-05: "audit our stuff to improve it every time ... make sure we're doing
   checks"). Read AGENTS.md and every file in docs/patterns/ (loading, servers, multiplayer, effects, measuring, code
   organization). They are the rules the game follows and the budgets it must meet. Every night, before picking your
   concepts, run the PATTERN AUDIT and put its result first in your run write-up and summary:
   a. Code since the last perf night (`git log --since=<last perf row's date> -p -- scripts`): any new bare `load(` in
      code that runs during play (not boot or a zone build), any `Shader.new()` outside a static cache, any server
      path that reads pixels or mesh surfaces, any new mid-zone spawn kind not in `MonsterWarm.kinds`, any skill whose
      effects changed without `SkillWarmData` re-recorded. Fix what you find (each its own commit) or log it.
   b. The checks, against docs/patterns/measuring.md's budgets (3 runs each where it says so, median and spread):
      - first times: `$G --path . -s tools/_late.gd -- res://tools/app_hitch_audit.gd` (no first-occurrence frame over
        50 ms on High);
      - a big fight: `tools/stress_fight.gd -- plague demon,archer 25 18` (p99 at or under 33 ms, worst at or under 80);
      - zone loads: the KPI scenarios' load_ms (3 s warm, 5 s cold) and the longest frame during a load (250 ms);
      - the server: a stripped "Linux Server" export (`--export-debug "Linux Server"`) run headless locally with
        `tools/load_bot.gd` players (6 fighting in a Battlegrounds world): its RSS and CPU against the costs in
        `deploy/lobbies/service.py` `COST`; a regression is a finding.
      Any budget missed is a candidate concept for tonight; one that got worse since the last night goes first.
   c. When you change a pattern (a new loader, a new warm-up, a new budget), update its docs/patterns file in the same
      commit: the next run reads it.
1. Learn from the past. Read docs/nightly/perf/LOG.md FIRST: its Lessons and every row (yours and the runner's
   `bench` rows, the scoreboard). Open the linked run write-ups (docs/nightly/perf/runs/*.md) of anything you build
   on, and docs/nightly/perf/metrics.jsonl for the trend. Don't repeat an attempt marked "no" unless you can say what
   is different this time; follow up the "Next" ideas of the rows that worked.
   NOTE: before and after your session the nightly script benchmarks the game itself (tools/nightly/bench.sh: the moor
   at Medium/High/Ultra and the camp at High) and adds that `bench` row to the log. If the game is slower than when you
   started, your work does NOT ship. Measure honestly; it will be checked.
2. Measure with the official KPIs (docs/nightly/KPIS.md: the scenarios camp, moor, fight, boss, arena, crypt, server,
   and the metrics fps_avg, fps_low1, frame_ms_p99, hitches_per_min, load_ms, gpu_ms, draw_calls, primitives,
   vram_mb ...). The runner's own "before" run of tonight is in {{OUT}}/bench/before.json; all past nights are in the
   KPI store: `sh tools/kpi_query.sh latest` or any SQL (`sh tools/kpi_query.sh "SELECT ..."`), or the `grafana` MCP
   if your session has it. Run a scenario yourself to iterate (each ~30-40 s):
     G=~/Applications/Godot_v4.3.app/Contents/MacOS/Godot
     $G --path . --resolution 1600x900 -- --kpi fight {{OUT}}/try_fight.json --quality 2
   (`--secs N` for a shorter run; `--hide ...` in CLAUDE.md isolates costs; the old `--shot x.png --perf 12` hook
   still works). Pick tonight's targets from the KPIs furthest from their targets in KPIS.md.
3. Rank the costs the profile shows and pick tonight's concepts, biggest payoff first (one main concept, then more
   as time allows; see GOAL). Ideas, not a list to follow: texture compression / mipmaps /
   sizes, mesh LODs and decimation, draw-call batching (MultiMesh), shadow casters, overdraw, shader cost, culling and
   visibility ranges, grass density, physics and AI tick rates, script hot loops (profile with timing), memory and
   load times, export size (bloated assets, unused files), server CPU (the headless server), network packet size.
4. Implement them one at a time, measuring each (step 5) and committing each that helps. Keep every test green: run at least playtest, grass_test, coop_fx_test, title_test, bg_test (server +
   client pair, see CLAUDE.md) and mp_test (host + join) before you finish. If the change doesn't measurably help or
   breaks something, REVERT it and record that honestly (a failed experiment is still knowledge).
5. Measure again exactly as in step 2. Make a before/after image for the report (side by side, same frame) when the
   look matters, and a small chart or table of the numbers.
6. Record (keep it short where it's short, detailed where it's detailed):
   - docs/nightly/perf/LOG.md: one row per attempt, kept or reverted, in the table:
     | {{DATE}} | big/small/size | Focus (one line: what you tried) | Result (the numbers) | yes/no/partly | Next | [runs/{{DATE}}.md](runs/{{DATE}}.md) |
     and REWRITE its Lessons list (at most 8 bullets, most useful first: what works, what doesn't, where the time
     goes), keeping what's still true, dropping what tonight disproved;
   - docs/nightly/perf/runs/{{DATE}}.md (the detail the rows link to): what you profiled, each hypothesis, what you
     changed (files), every measurement before/after, why the failures failed, what you'd try next;
   - append the measurements to docs/nightly/perf/metrics.jsonl, one JSON object per line with keys
     date, phase ("before"/"after"), scene, preset, fps, low1, draw_calls, primitives, gpu_ms, gpu_busy;
   - write {{OUT}}/perf_summary.md: 5-12 lines for the morning report: first the pattern audit (what it found, what
     you fixed) and each budget's number against its target (met / missed), then the night's overall before -> after,
     then each win (and each revert) in a line.
7. Commit on the current branch (a commit per win, plus one for the records) with a clear message (end it with the Co-Authored-By line from CLAUDE.md's
   conventions). Do NOT push, merge or deploy: the nightly script does that after its own checks.

Never print or commit credentials. Never touch `main`. Spend no Meshy or ElevenLabs credits in this phase.
Don't lower texture size or quality (the importer's size cap, lossy quality, resizing): jj wants Ultra at full
quality, and the import is the same for every preset (2026-11-03).
