# Triage job: attempts and results

The short log every nightly triage run (05:00, `tools/nightly/triage_prompt.md`) reads first and adds to: what real
players hit (errors, crashes, slow places; docs/nightly/TELEMETRY.md) and what was done about it. One row per issue or
spot looked at, newest last. **Kind** error / crash / spot. **What** the issue (its fingerprint) or the place (zone and
x,z). **Result** fixed (how) / not reproduced / watch. **Hit** players and events. **Details** the run's write-up.
Rows with Kind `bench` are the runner's KPI benchmark of the night's result (a fix mustn't slow the game down).

## Lessons (rewritten by each run: at most 8 bullets, the most useful first)

- **Reproduce on the player's renderer, not only headless.** An engine error a headless repro never shows may live
  behind a Forward+/High switch (heat haze, SSAO, shadows: `haze_ok`, `is_forward()`, `DisplayServer` checks): the
  braziers' `!is_inside_tree()` (11-03-1912) logged 8 times on every windowed camp load and never headless. Run the
  same tool script windowed at their preset first; then `printerr` lines through `Game.load_zone` find the step, and
  the count per load (8 = 4 braziers x 2) names the culprit. A `.global_position` on a node built before it's added
  is this bug; build helpers place with `InfernalFx._place`.
- **Know the screen before blaming the scene.** The worst "slow spot" so far (the camp at 21 fps on an M5 Pro) was a
  Retina window drawing 4x the pixels; `res` is now `WxH@scale 3dS`. Compare one spot across players and presets
  first. This Mac's KPI window can't be Retina-sized: emulate with `--render-scale 2.0`. (Confirmed fixed 11-03.)
- **Look at hitches, not only the average.** The worst play now is stutter at fine averages (archer: 9-45 frames
  over 100 ms a minute). `--kpi ... --trace` lists every frame; line a hitch up with what ran the frame before.
  Rare hitches need 5+ runs a variant. The first use of a shader variant in a process costs 100-700 ms cold:
  repeated KPI runs warm `user://shader_cache` and hide it, so clear them to see what a player meets.
- **Read the crumbs for the order of events.** `raid` -> `enter bg` -> `enter town` 2 s later = a join turned away
  mid-load; after any `await` in net code, check the link is still the same one (`Net.still_joined`). Two `enter
  town` 10 s apart = the camp behind the title, then Continue (or Save and Exit to Title).
- **Engine errors with callable `''` or a C++ `at:` and no script line**: Godot 4.3 prints no GDScript stack for
  them (`-d` neither). Read the engine source for the one path that logs it (raw.githubusercontent.com/godotengine/
  godot/4.3-stable/...); in 4.3 `set_global_position` reads `get_global_transform` first. One player on every build
  with no repro = watch, not chase.
- **The servers' journal is the fuller story** (`ssh ashen-crown-staging 'sudo journalctl -u ashen-crown-bg|coop
  --since -24h'`, UTC); group it with `sed 's/[0-9]+/#/g' | sort | uniq -c`. `Parameter "m" is null` and the
  exit-leak lines are the dummy renderer's noise. Half-written log lines once made up issues: an odd `at:` = the reader.
- **A test that "fails" with `Nonexistent function 'rooted' in base 'GDScript'` every frame didn't compile**: its
  first error is `Identifier not found: Sfx` (a static reference to Hero compiled before the autoloads). Run it as
  `-s tools/_late.gd -- res://tools/<test>.gd [args]` (coop_fx_test, bg_test, mp_test needed it on 11-03). Read a
  test's first errors before its last.
- **Timer lambdas that capture a node error when it's gone** (use `Fx.later`); RPC checksum / argument-count errors
  are a client and a server on different builds during deploys (the client already explains it).

## Log

| Date | Kind | What | Result | Hit | Next | Details |
|---|---|---|---|---|---|---|
| 2026-11-02 | spot | Act I camp (town -20,0 / 0,0) on macOS, Apple M5 Pro: steady 21 fps on Medium (22 min), 29 on Low | fixed: a Retina window drew the 3D into 4x the pixels; Low/Medium cap the 3D pixels (FSR 1), telemetry reports real pixels. Retina emulated (`--render-scale 2.0`): Medium 48 -> 75 fps, Low 55 -> 90 | 1 player, 37+ samples | watch the next samples from that Mac: res `@2.0 3d0.5x`, 50+ fps on Medium | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | error | servers: `Parameter "m" is null` (df11922358aba5df, 4d1c0e086f2610df), 411 lines/6 h in the journal | fixed (telemetry): Godot 4.3's dummy renderer logs it whenever a mesh node is freed (harmless); the log reader read half-written lines, so it slipped the existing filter. Whole lines only now | servers, 6 events | none expected; an issue whose `at` looks cut = the reader | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | error | servers: `Lambda capture at index 0 was freed` (07a289503f7f9fa8) | fixed: timer lambdas capturing a node freed first (Wraith effects on puppets, effect_shadow); `Fx.later` holds a weak reference | servers, 6 events / 4 sessions | if back: audit the 25 `tween_callback(func` sites | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | error | RPC checksum / arg count (7f31c1c6466e34f3, 1f2fddf18e2a422d, 72d8710939ddd1b6) | watch: client and server on different builds during deploys; the client already says so (e0a68ee) | 2 players, 28 events | a server-side build handshake if it keeps happening | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | error | servers: `Unable to send packet on channel 1, max channels: 0` (fd6796612eee4c16) | watch: sends to a peer being disconnected when a raid join is turned away and retried; harmless | servers, 10 events | log the RPC around `disconnect_peer` to find the send | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | error | client: `disconnect a nonexistent connection ... skeleton_updated` (28b5fe25d00fd3d0) | not reproduced: engine-side (BoneAttachment3D), one Windows player, every build; a windowed camp run and the gate show none | 1 player, 144 events / 15 sessions | watch for a second player | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | error | client: `Signal 'tree_exited' is already connected` (2bdc80640e965691) | watch: engine-side (multiplayer path cache), one Windows player in co-op / raids; harmless | 1 player, 9 events | watch | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | bench | Runner's KPI benchmark of the night's result (avg fps) | camp 46→46, moor Medium 57→56, moor 37→37, moor Ultra 11→11, fight 34→34, boss 54→53, arena 111→100, crypt 96→96; server tick p99 107→113 ms, camp 15M→15M tris, download 429→429 MB | shipped | | `docs/nightly/perf/metrics.jsonl` |
| 2026-11-03 | error | client: `RPC 'sv_zone_ready' on yourself is not allowed` (b43c39456b33870a) | fixed: a raid join turned away while the crypt loaded; `_client_goto` (and the raid hello after its ticket) sent to the offline peer after the await. `Net.still_joined` checks the link first; `tools/net_drop_test.gd` reproduces it | 1 player, 1 event | none expected | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | error | client: `disconnect a nonexistent connection ... skeleton_updated` (28b5fe25d00fd3d0) | watch (2nd night): still one Windows player, every build, every session only start -> camp -> camp (3-26 a session); engine source read, 11 scratch cases, carousel and title: none here | 1 player, 150 events / 16 sessions | a second player, or log the attachment's path in a crumb | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | error | servers: `Unable to send packet on channel 1, max channels: 0` (fd6796612eee4c16) | watch: unchanged (a join turned away); 12 lines in 24 h | servers, 30 events | as before | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | error | co-op server (journal only): `StyleBoxTexture` into a `StyleBoxFlat` var, `UI._make_theme` | already fixed in code (532a507), one line on an older build, not seen since | server, 1 line | none | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | spot | archer hitching, Act I moor + fort (wild 6,-24 / 10,-73 / -9,-101; lair), Low, Windows and Mac: 9-45 hitches/min, 1% low 3-14 | watch: reproduced (`--kpi fight --class archer -q 0 --trace`: up to 6/min; knight and bow-only 0); every hitch is the frame after a Fire Arrow `finish`; scorch decal off / emission always set 0 of 4 runs vs 3 of 5, not conclusive, nothing changed | 2 players, 15 samples | lead: first-use shader compiles (a new particle variant costs 450-770 ms cold, in a scratch scene); try a warm-up of the class's effects behind the loading screen, measured with cleared caches | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | spot | last night's Retina camp watch | closed: that Mac reports `@2.0 3d0.53` and 94-118 fps on Low in the camp, Gauntlet and crypt | 1 player, 30+ samples | none | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | bench | Runner's KPI benchmark of the night's result (avg fps) | camp 46→45, moor Medium 89→88, moor 52→52, moor Ultra 15→16, fight 46→46, boss 82→84, arena 77→77, crypt 96→94; server tick p99 94→100 ms, camp 10M→10M tris, download 409→409 MB | shipped | | `docs/nightly/perf/metrics.jsonl` |
| 2026-11-03-1912 | hotfix-error | client: `Condition "!is_inside_tree()" is true` at `get_global_transform` (016d8c012ecbed22), camp, Forward+ High | fixed: the grand waypoint's 4 braziers (`BrazierCoals`) built their heat haze before being in the tree (own `global_position` + `InfernalFx.glow` setting one): 8 errors every camp load on Forward+ High/Ultra, never headless. `InfernalFx._place` (local while outside the tree); windowed boot 8 -> 0, haze unchanged | 1 player, 16 events / 1 session | none expected after the next staging build | [runs/2026-11-03-1912.md](runs/2026-11-03-1912.md) |
| 2026-11-03-1912 | note | Molten Fists' effect state (`DemonFistsFx.update`, `demon_fists_fx.gd:168`) touches nodes freed with the old zone after a zone change (seen in the debug repro, not by players: release builds skip the check) | not fixed (outside the hotfix's issue) | none | a normal night: `SkillFx.clear(hero)` where `load_zone` frees the world, as puppets do; coop_fx_test + demon_test | [runs/2026-11-03-1912.md](runs/2026-11-03-1912.md) |
