# Shared performance coverage — 2026-11-05

The loading migration is implemented locally, but **release and performance acceptance are not complete**.
Current source includes published staging `3d4c661` (the forest/run/survivor overhaul) and Claude's documentation
through `133e3d2`. The shared guidance remains [loading](../patterns/loading.md), [effects](../patterns/effects.md)
and [measuring](../patterns/measuring.md). This is the current status page; older result pages preserve their
original revisions and failed attempts.

| Area | Implemented and verified | Remaining acceptance |
|---|---|---|
| Asset preparation | Shared catalog, bounded worker, owner scopes, cancellation and release. Current Godot 4.4.1 native checks: cache 23, declarations 1,931, actual combat roots 278, derived recipes 47; clean logs. | Declared roots are not proof of every dynamic path. Forest lantern-post/cookfire/weapon-rack models and environment fire textures are now declared; shared camp-model cache routing migrated. Actual BG/Arena builder contract: 7 checks, zero undeclared cache requests or runtime warnings/errors. |
| World construction | Terrain rows, grass jobs, forest/fern checkpoints and sea-chart CPU rows use the shared scheduler. Terrain 27 native assertions passed. Current BG and Arena scheduled/synchronous terrain, grass, spawn, obstacle and interaction hashes match. | BG still recorded a 466.7 ms builder slice and 42 ms job step in a headless diagnostic. Mesh upload, masks/collision, material walks and minimap GPU readback are not all incremental. Town hashes match but its headless run has a PagedAllocator shutdown error; native town/coast checks pending. |
| Actual Arena | Rendered client + headless client + local worker: 34 assertions passed, two rounds, survivor skills/gear and byte-identical saves retained, content scopes ready and released at teardown. Screenshot inspected; no runtime errors. | Existing layout/Metal warnings remain. Another agent's render overlapped the tail: functional evidence only, no accepted timings. Full gate reruns this fixture. Larger team configurations/Steam transport need separate checks. |
| Actual Battlegrounds | Forest construction parity passed. Arena fixture also verified real BG lobby class selection and Ready invalidation. New forest monsters resolve through the existing enemy/model registry. | Current extraction/death/loot/survivor/reset tests: 44 checks passed; server-mediated two-player PvP/spectating: 24 passed. Rendered BG screenshot inspected. Full gate repeats these after final dependency additions. Whole-run, late-join and peak-capacity claims require their own completed evidence. |
| Effects and lifetimes | Current material lifecycle 73 clean assertions; prior 4.4 all-class replay 387 clean assertions. World-owned callbacks and surface-override retirement preserve cached meshes. | Current full replay, long-session residency, delayed variants and performance under six-actor spell floods. Online preparation still covers all classes rather than a changing roster. |
| Sandbox | Solo and hosted practice, class/level/gear, bots locally, FFA/respawns online; broker/HTTP checks passed previously. | Current solo/entry/hosted runtime acceptance and matching backend/client rollout. Do not describe Sandbox as live based on source alone. |
| Release | Fresh origin fetch confirms 3d4c661. Current native component contracts pass. | Full functional gate, repeatable performance acceptance, matching exports/backend/client staging publication, remote verification. No staging push or deployment in this closure continuation. |

Raw closure evidence is under `workspace/output/perf-closure/`; prior evidence is linked from
[implementation results](IMPLEMENTATION_RESULTS.md) and [staging results](STAGING_RESULTS.md).
The first Arena attempt failed because the headless client’s 30-second round wait expired while the rendered client
prepared. It remains a failed run. The passing fixture keeps native rendering enabled throughout and allows
120 seconds for both clients to become ready. That timeout is a correctness limit, not an acceptable loading target.

## Audit against the original request

The original request, preserved in [AUDIT.md](AUDIT.md) and [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md), calls for shared
asset readiness/lifetimes, scheduled construction, contextual visual preparation, honest measurement and
repeatable content adoption. This branch implements those shared paths and preserves the current gameplay/art.
It does not certify all content or solve sustained GPU cost merely by caching. The original attachment was not
available during this closure review; the preserved audit/design were used instead.

A fresh staging-baseline Arena spell-flood pilot was focused and quiet, but had layout/Metal warnings and large
first-use stalls. The candidate comparison was stopped when another Godot appeared. There is no accepted paired
result. Earlier 4.3 gains also increased loading and memory and were rejected. Neither result certifies this release.

## How future code stays on the path

- **During implementation:** existing `Game.load_zone`, `World` jobs and declared content families carry new content
  through preparation. New dynamic families, visual events or bespoke builders still need explicit integration.
- **Before release:** CI checks declarations, root loading, cache/material lifetimes and known construction bypasses.
  The full gate adds real BG/PvP and isolated two-client Arena/Sandbox flows. The new world-content fixture exercises
  actual builders for undeclared `ResCache` requests; it does not detect every arbitrary raw `load()`.
- **After release:** the installed 22:30 local launchd audit uses three repeated exported-build profiles, including
  six-actor Arena/forest floods, with focus, clean-log, miss, stall, load and memory checks. It reports regressions;
  it does not rewrite new code. A second cron job is unnecessary. Its first complete workload still awaits rollout
  and an exclusive test window. Six rendered actors do not certify six network clients.

Keep functional correctness, measured performance and publication status separate. A green component test,
installed schedule or successful export cannot stand in for the other two.
