# Staging continuation — 2026-11-05

Blaine authorized continuing optimization and publishing to staging. This continuation builds on the
shared preparation implementation in PR #4 and integrates staging through d0e8ea9 (Godot4.4.1, Steam co-op, autosave and lobby changes). Publication and
final functional gate are pending; this is not a certified full-suite performance result.

## Runtime changes

- The single owned loader now handles bounded batches of up to eight resource roots. It still uses
  one worker, does no scene-tree work off-thread, coalesces owners, and discards cancelled results.
  `--content-batch-one` reproduces the former scheduling policy for comparisons. This removes a
  mandatory frame boundary between every tiny root; it does not guarantee eight times faster loading.
- Plague vial/vat debris uses scope-owned mesh/offset recipes. Each imported fragment source is
  instantiated once per residency lifetime instead of once per burst. All 14 vial and 24 vat pieces
  retain their original mesh identity and local offset. Actual flying debris remains unchanged.
- Boot preparation now holds the busy flag until the initial world load starts. Tests exposed a
  race where an awaited startup could still have a null world. Final cache shutdown also drops legacy
  pins and derived recipes; live consumers keep their own Resource references.
- Delayed Serpent, arc and elemental visuals use world-owned callbacks; independently removable
  casters are resolved from weak references. Travel/class changes must not invoke freed captures.
- The UI test now samples current visible bounds, sends motion/press in one frame, and explicitly
  fails leaks. Diagnostics proved its old failures clicked the bare map after a delayed waypoint
  trip closed the panel between events. A speculative input-handler change did not fix that and
  was reverted byte-for-byte; no waypoint gameplay change is included. The corrected full UI grid
  passes with zero leaks/input failures, exit0, 220 known dummy mesh errors and no warnings.
  This targeted rerun supersedes the initial gate UI diagnostic; runtime files match the gate start.

## Historical Godot4.3 evidence

The measurements below precede the engine upgrade. They are not a 4.4.1 baseline.

## Evidence collected before integration

- Final resource contracts: 23 ownership/batching/cancellation/shutdown checks, 1,775 declaration
  checks, all 278 actual combat roots, and 47 fragment/ownership checks. All clean, no failures.
  The catalog used 34 batches. `loads_started` counts requested roots, not physical disk reads;
  dependencies can become cached while earlier roots in the same batch are being loaded.
- Fragment extraction measured about 0.14–0.28 ms per call; cached lookup about 1–3 microseconds
  in the small repeated probe. Other tests ran on the shared Mac: these are mechanism diagnostics,
  not a whole-game FPS gain or an explanation of the much larger Plague burst cost.
- Twelve Python benchmark/log-classification tests and 49 lobby broker tests passed.
- One-root PvP run was quiet/focused/clean: 24.5 FPS, p99 262 ms, first-use max 932 ms,
  preparation 33,150 ms, reported VRAM 2,884 MB. The eight-root counterpart was interrupted by
  another Godot process and lost focus. Its 26,607 ms preparation is NOT an accepted paired speedup.
  Both had zero observed gameplay resource misses; the eight-root flood screenshot was inspected.
- The all-class replay initially reported zero failed assertions but contained two freed-capture
  errors at the Serpent→Wyvern transition. The stricter gate rejected it. After callback fixes, a
  two-class diagnostic had no such errors but failed a one-second status-display assertion while
  overlapping other tests. That fixture now cancels the previous dodge (which can reject snare), waits for physics-driven
  visuals and uses ten-second statuses. It tests appearance and explicit removal, not natural expiry.
  The final complete ten-class replay passes 386 assertions, including packet appearance/removal and the
  Serpent→Wyvern transition: zero script/parse/unexpected runtime errors, 2,851 known dummy mesh
  errors and no warnings. The earlier failed attempts remain in the evidence directory.
- Headless title/character tests reproduce an exit PagedAllocator error on both baseline009420c
  and the candidate. Explicit scene ownership and cache teardown did not remove it. Real
  Forward+ title and character runs exited cleanly. These older fixtures include printed diagnostics
  as well as assertions; screen_test separately asserts home behavior. Archer also failed headless shutdown despite explicit teardown, but passes all assertions with
  a clean Forward+ exit. An Archer baseline reproduction has not been run. The final desktop gate
  uses native rendering for title, character and Archer (default on macOS; GATE_UI_RENDERED override). The allocator signature has NOT been added to the error allowlist.
- The stamina fixture now measures simulation seconds: wall-clock stalls caused false drain-rate
  failures. The actual input-driven test checks 14/s in combat and 2.8/s fully calm; nine checks pass.
- A bootstrap experiment continuing execution after set_script caused native crashes and was
  reverted. Each game fixture now explicitly assigns current_scene after adding its main scene.
  Failed pilot logs are retained and are not counted as passes.

Full evidence: workspace/output/perf-staging/. Pipeline disk cache is disabled only in the local
isolated test override, not the shipped project. No cold-driver-cache claim.

## Six-process retry limit

The new local six-client retry reached one shared lobby but was deliberately stopped when swap growth
reduced free disk to about4.2GiB on this16GiB Mac. All six exits wereSIGTERM, so this is NOT a successful
match verification. Its broker/worker ports closed afterwards. The prior implementation's completed
six-client/36-assertion runs remain historical evidence, not a new pass for this continuation.

## Acceptance limits

The earlier implementation's FPS/first-use improvements came with load and VRAM regressions; see
[the original results](IMPLEMENTATION_RESULTS.md). Those limits remain open. No complete three-repeat,
all-scenario acceptance suite, roster-aware preparation, long soak or Windows/Linux GPU comparison
has been completed in this continuation. Initial staged adoption is not a claim that all budgets pass.

## Godot4.4.1 integration (verification in progress)

- Merged the latest staging work rather than publishing the earlier engine or replacing Steam/autosave changes.
  The active server export is e64d0a5; Net, ArenaMatch, MatchInstance and the broker have no diff against it.
  This continuation changes client preparation and shared visual construction, not the RPC contract.
- Steam Invite Friends and LAN Host can open an existing solo world without a zone transition. Both now await
  the shared all-class combat preparation before admitting friends. Repeated preparation reuses the same scope;
  returning to title releases it. A dedicated rendered contract checks readiness, retained character/world,
  reuse and release without actually opening a Steam lobby. Steam relay/invites require their separate test.
- Godot4.4.1 dummy rendering returns an empty MultiMesh transform buffer. Props' shadow twin now falls back
  to the existing source transforms when readback has no matching data; native rendering keeps its bulk copy.
  The first 4.4.1 gate exposed this error and was stopped; its log is retained, not counted as a pass.
- After updating only this worktree's ignored class/extension registrations, all content contracts passed:
  23 cache, 1775 declarations, 278 actual combat roots, 47 fragment checks. Twelve Python benchmark/log tests
  and 49 broker tests also passed. Initial stale local class-cache failure is retained. No shared import was run.
- Full functional gate, rendered host readiness and final staging export/publication remain pending.
