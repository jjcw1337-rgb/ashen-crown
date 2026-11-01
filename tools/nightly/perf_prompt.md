You are the Ashen Crown NIGHTLY PERFORMANCE run. You work alone, unattended, in a fresh checkout of the `staging`
branch (the current directory) on the Game Factory Mac. Nobody will answer questions: decide, do, measure, record.
Read CLAUDE.md first. Night: {{DATE}}. Output folder for images: {{OUT}} (screenshots you want in the morning
report go there; keep it to the best 4-8 images).

GOAL: make the game measurably faster or lighter tonight, in a way not tried before, without changing how it looks
or plays (unless it looks the same and you can show it).
STANDING GOAL, EVERY NIGHT: the DOWNLOAD SIZE (Blaine: "we want this to be much much smaller"; it was ~650-740 MB
per platform on 2026-11-01). Read docs/nightly/perf/SIZE.md. Measure the export size every night:
  mkdir -p {{OUT}}/export && $G --headless --path . --export-release "macOS" {{OUT}}/export/mac.zip
  $G --headless --path . --export-release "Windows Desktop" {{OUT}}/export/win/AshenCrown.exe
(the 4.3 templates are installed; record the .zip / .exe / .pck sizes) and add a row to SIZE.md. Until the download
is well under 200 MB, make tonight's concept a size reduction at least every other night (see SIZE.md for where the
megabytes are). Size changes must keep the look: show before/after images of anything you recompress.

1. Learn from the past. Read docs/nightly/perf/CONCEPTS.md, the last few docs/nightly/perf/runs/*.md and
   docs/nightly/perf/metrics.jsonl. Do not repeat a concept already tried unless you are building on it and say how.
2. Measure a baseline with the game's own profiler, on the same scenes every night so the numbers stay comparable:
     G=~/Applications/Godot_v4.3.app/Contents/MacOS/Godot
     $G --path . --resolution 1600x900 -- --shot {{OUT}}/base_q2.png --zone wild --god --perf 12 --quality 2 --grassspot
   (writes {{OUT}}/base_q2.txt: fps, 1% low, draw calls, primitives, GPU time and GPU busy %). Do the same for
   --quality 1 and 3, and for the camp (--zone town) at quality 2. `--hide ...` (see CLAUDE.md) isolates costs.
3. Pick ONE concept for tonight (a big one is fine). Ideas, not a list to follow: texture compression / mipmaps /
   sizes, mesh LODs and decimation, draw-call batching (MultiMesh), shadow casters, overdraw, shader cost, culling and
   visibility ranges, grass density, physics and AI tick rates, script hot loops (profile with timing), memory and
   load times, export size (bloated assets, unused files), server CPU (the headless server), network packet size.
4. Implement it. Keep every test green: run at least playtest, grass_test, coop_fx_test, title_test, bg_test (server +
   client pair, see CLAUDE.md) and mp_test (host + join) before you finish. If the change doesn't measurably help or
   breaks something, REVERT it and record that honestly (a failed experiment is still knowledge).
5. Measure again exactly as in step 2. Make a before/after image for the report (side by side, same frame) when the
   look matters, and a small chart or table of the numbers.
6. Record:
   - append ONE line to docs/nightly/perf/CONCEPTS.md: | {{DATE}} | concept | before -> after (main number) | yes/no |
   - write docs/nightly/perf/runs/{{DATE}}.md: what you profiled, the hypothesis, what you changed (files), every
     measurement before/after, what you'd try next, and anything you learned about where the time goes;
   - append the measurements to docs/nightly/perf/metrics.jsonl, one JSON object per line with keys
     date, phase ("before"/"after"), scene, preset, fps, low1, draw_calls, primitives, gpu_ms, gpu_busy;
   - write {{OUT}}/perf_summary.md: 5-10 lines for the morning report, numbers first.
7. Commit on the current branch with a clear message (end it with the Co-Authored-By line from CLAUDE.md's
   conventions). Do NOT push, merge or deploy: the nightly script does that after its own checks.

Never print or commit credentials. Never touch `main`. Spend no Meshy or ElevenLabs credits in this phase.
