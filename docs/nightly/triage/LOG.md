# Triage job: attempts and results

The short log every nightly triage run (05:00, `tools/nightly/triage_prompt.md`) reads first and adds to: what real
players hit (errors, crashes, slow places; docs/nightly/TELEMETRY.md) and what was done about it. One row per issue or
spot looked at, newest last. **Kind** error / crash / spot. **What** the issue (its fingerprint) or the place (zone and
x,z). **Result** fixed (how) / not reproduced / watch. **Hit** players and events. **Details** the run's write-up.
Rows with Kind `bench` are the runner's KPI benchmark of the night's result (a fix mustn't slow the game down).

## Lessons (rewritten by each run: at most 8 bullets, the most useful first)

- **A timer lambda must not hold a node strongly.** The commonest player error so far (11-02 servers, 11-04 clients):
  `Lambda capture at index 0 was freed` = a `create_timer(...).timeout.connect(func` or `Fx.later` lambda captured a
  node that freed itself (one-shot particles do, `InfernalFx.particles`) or that something else freed first (the
  gates rising, a zone change). `Fx.later` guards only the node it's given; capture `weakref(x)` for anything else.
  Tween callbacks on the captured node's own tween are safe. Effects every game plays at once (a stash opening)
  show as several players hit within seconds: look for the shared event in the server's journal.
- **Reproduce on the player's renderer, not only headless.** An engine error a headless repro never shows may live
  behind a Forward+/High switch (heat haze, SSAO, shadows): the braziers' `!is_inside_tree()` (11-03-1912) logged
  8 times on every windowed camp load and never headless. `printerr` through `Game.load_zone` finds the step; the
  count per load names the culprit. A `.global_position` on a node built before it's added is this bug.
- **Read the crumbs for the order of events, and the journal for what the server did.** `raid` -> `enter town` 8 s
  later with no `enter bg` = a join that never got an answer (11-04: staging was down); `raid` -> `enter bg` ->
  `enter town` 2 s later = turned away mid-load. After any `await` in net code check the link (`Net.still_joined`);
  behind a loading screen nothing may take input (`loading.visible` blocks it since 11-04).
- **Engine errors with a C++ `at:` and no script line**: read the engine source (raw.githubusercontent.com/
  godotengine/godot/4.3-stable/...) for the one path that logs it, then build a tiny probe of just that path (two
  ENet peers in one process, one not polled = a busy client: 11-04's `max channels: 0` was a graceful
  `disconnect_peer` emptying the channels while the peer stayed listed; `Net.drop_peer` disconnects now).
- **Know the screen before blaming the scene.** The worst "slow spot" so far (camp at 21 fps on an M5 Pro) was a
  Retina window drawing 4x the pixels; `res` is `WxH@scale 3dS`. Compare a spot across players and presets first;
  emulate Retina here with `--render-scale 2.0`.
- **Look at hitches, not only the average.** Averages are 97-120 fps now; what's left is stutter (1% lows of 16-36 in
  single minutes). `--kpi ... --trace` lists every frame; first-use shader compiles cost 100-700 ms cold and repeated
  runs hide them (clear `user://shader_cache`). Rare hitches need 5+ runs a variant.
- **A test that "fails" with `Nonexistent function ... in base 'GDScript'` every frame didn't compile**: its first
  error is `Identifier not found: Sfx`; run it through `tools/_late.gd -- res://tools/<test>.gd`. Read a test's first
  errors before its last. A test can read its own `user://logs/godot.log` from its start offset to fail on an engine
  error (`nightly_stash_fx_test`), but only run one Godot at a time then (they share the log).
- **The servers' journal is the fuller story** (`ssh ashen-crown-staging 'sudo journalctl -u ashen-crown-bg|coop
  --since -24h'`, UTC); `Parameter "m" is null` / `mesh_get_surface_count` are the dummy renderer's noise. RPC
  checksum errors are client and server on different builds during deploys.

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
| 2026-11-04 | error | client (regression of 11-02): `Lambda capture at index 0 was freed` (07a289503f7f9fa8), raid antechamber | fixed: a stash chest opening (`Battlegrounds.stash_fx`, played by every game) kept its self-freeing smoke in a 4 s lambda; the gates rising freed the fire and loop under theirs. Lambda removed, weak refs, Frost Nova's timer via `Fx.later`; `nightly_stash_fx_test` 4 -> 0 | 2 players, 3 events | if back: audit `create_timer` / `Fx.later` lambdas capturing other nodes | [runs/2026-11-04.md](runs/2026-11-04.md) |
| 2026-11-04 | error | client: `Trying to call an RPC via a multiplayer peer which is not connected` (5a186a1ced052d71), camp 0,5 | fixed: a raid join waiting 8 s for a server that was down (the 11-03 outage) left the camp behind the loading screen taking keys; the Plague Doctor's skills sent effects down the connecting link. No game input while `loading.visible`; `nightly_join_wait_test` 4 -> 0 | 1 player, 4 events | none expected | [runs/2026-11-04.md](runs/2026-11-04.md) |
| 2026-11-04 | error | servers: `Unable to send packet on channel 1, max channels: 0` (fd6796612eee4c16), 3rd night | fixed: graceful `disconnect_peer` on a turn-away empties the ENet peer's channels but keeps it listed until a busy client answers; every per-peer RPC meanwhile failed (27 lines a turn-away). `Net.drop_peer` disconnects now (peer_disconnected still fires); `nightly_drop_peer_test` 106 -> 0 | servers, 58 events / 24 h | none expected; `bg_admin_test` fails "back in, though joining has closed" with and without this (not a player report) | [runs/2026-11-04.md](runs/2026-11-04.md) |
| 2026-11-04 | error | `!is_inside_tree()` (016d8c012ecbed22), `skeleton_updated` (28b5fe25d00fd3d0), `tree_exited` (2bdc80640e965691) | watch: the first is fixed by the 11-03-1912 hotfix (reports from the build before it); the other two the same one Windows player, engine-side | 1 player, 24 / 6 / 2 events | check 016d8c is gone on a newer build | [runs/2026-11-04.md](runs/2026-11-04.md) |
| 2026-11-04 | spot | none qualified: every square 97-120 fps (Medium RTX 5070 Ti, Low M3 Max), 3 hitches a minute | nothing to fix | 2 players, 147 samples | stutter (single-minute 1% lows 16-36) stays the lead | [runs/2026-11-04.md](runs/2026-11-04.md) |
| 2026-11-04 | bench | Runner's KPI benchmark of the night's result (avg fps) | camp 43→45, moor Medium 88→88, moor 51→50, moor Ultra 16→16, fight 48→48, boss 85→84, arena 78→76, crypt 95→95; server tick p99 95→100 ms, camp 11M→10M tris, download 561→561 MB | shipped | | `docs/nightly/perf/metrics.jsonl` |
