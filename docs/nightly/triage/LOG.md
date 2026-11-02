# Triage job: attempts and results

The short log every nightly triage run (05:00, `tools/nightly/triage_prompt.md`) reads first and adds to: what real
players hit (errors, crashes, slow places; docs/nightly/TELEMETRY.md) and what was done about it. One row per issue or
spot looked at, newest last. **Kind** error / crash / spot. **What** the issue (its fingerprint) or the place (zone and
x,z). **Result** fixed (how) / not reproduced / watch. **Hit** players and events. **Details** the run's write-up.
Rows with Kind `bench` are the runner's KPI benchmark of the night's result (a fix mustn't slow the game down).

## Lessons (rewritten by each run: at most 8 bullets, the most useful first)

- **Know the screen before blaming the scene.** The worst "slow spot" (the camp at 21 fps on an M5 Pro) was a Retina
  window drawing 4x the pixels; `res` used to be the UI's size in points. It's now `WxH@scale 3dS` (real pixels, the
  screen's scale, the 3D scale). Compare one spot across players and presets before touching the scene.
- **This Mac can't open a Retina-sized window** (the KPI tool's window is clamped to the 1080p screen): emulate the
  pixel cost with `--render-scale 2.0` (4x the pixels) and measure the fix at the scale the cap picks.
- **Engine errors with callable `''` or a C++ `at:` and no script line are mostly Godot 4.3's own** (BoneAttachment3D's
  skeleton_updated, the multiplayer path cache's tree_exited, the dummy renderer's `Parameter "m" is null`). Bisect them
  with a scratch scene of bare nodes before reading game code; most are harmless noise to keep out of the reports.
- **Check the telemetry itself.** Two of tonight's server issues were made up by the log reader catching lines
  half-written (an error without its `at:`). It now reads whole lines only; an odd `at:` is a hint to look at the reader.
- **The servers' journal (`ssh ashen-crown-staging 'sudo journalctl -u ashen-crown-bg ...'`) is the fuller story**:
  telemetry sends each issue once per session; the journal has every line and the joins/leaves around it (UTC; the
  tables are UTC too).
- **A timer lambda that captures a node errors when the node is gone, even behind `is_instance_valid`**: use
  `Fx.later(node, t, fn)` (a weak reference). The servers replay every partner's effects on puppets, so effect code runs
  there too.
- **RPC checksum / argument-count errors are a client and a server on different builds** (deploys leave a server with
  players on its old release): the client already explains it; don't chase them as code bugs.
- **In zsh, `set -- $a` doesn't split words**: loop over measurements with a function and explicit arguments (a
  mis-split `--quality` silently ran Ultra and looked like a 6x regression).

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
