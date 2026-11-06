# Shared performance coverage — 2026-11-06

The loading migration is implemented locally, but **release and performance acceptance are not complete**.
Current source includes published staging `3d4c661` and Claude's committed gameplay through `9ea4830`
(run talents, gems, consumables and twelve new run-only skills). The shared guidance remains [loading](../patterns/loading.md), [effects](../patterns/effects.md)
and [measuring](../patterns/measuring.md). This is the current status page; older result pages preserve their
original revisions and failed attempts.

| Area | Implemented and verified | Remaining acceptance |
|---|---|---|
| Asset preparation | Shared catalog, bounded worker, owner scopes, cancellation and release. Godot 4.4.1 native checks: cache 23, declarations 2,250, actual combat roots 143, derived recipes 47; clean logs. | Declared roots are not proof of every dynamic path. Forest lantern-post/cookfire/weapon-rack models and environment fire textures are now declared; shared camp-model cache routing migrated. Actual BG/Arena builder contract: 7 checks, zero undeclared cache requests or runtime warnings/errors. |
| World construction | Terrain rows, grass jobs, forest/fern checkpoints and sea-chart CPU rows use the shared scheduler. Terrain 27 native assertions passed. Current BG and Arena scheduled/synchronous terrain, grass, spawn, obstacle and interaction hashes match. | BG still recorded a 466.7 ms builder slice and 42 ms job step in a headless diagnostic. Mesh upload, masks/collision, material walks and minimap GPU readback are not all incremental. Town hashes match but its headless run has a PagedAllocator shutdown error; native town/coast checks pending. |
| Actual Arena | Current `2a2f1e2`: rendered client + headless client + local worker: 34 assertions passed, two rounds, survivor skills/gear and byte-identical saves retained, content scopes ready and released at teardown. Worker exited naturally and released its UDP port. Screenshot inspected; no runtime errors. | Three layout/Metal warnings remain across the two clients. This current run had no competing Godot. Functional evidence only; larger team configurations/Steam transport and accepted timings need separate checks. |
| Actual Battlegrounds | Forest construction parity passed. Arena fixture also verified real BG lobby class selection and Ready invalidation. New forest monsters resolve through the existing enemy/model registry. | Current rendered client passed 28 checks for entry, combat, swaps, extraction, survivor saving, re-entry, death and scope retirement. Server-mediated two-player PvP/spectating passed 24 checks. Screenshots inspected. The full gate was stopped red on two server reset assertions; a clock probe proved the round did collapse at 150 simulation seconds and rebuilt. The corrected fixture observes actual death/reset/rebuild transitions continuously and passed 45 checks (18 server / 27 client), including the configured 150-second simulation boundary and a fully rebuilt next lobby. Both processes exited 0 with no runtime errors; seven client rendering/UI warnings remain. Whole-run, late-join and peak-capacity claims remain separate. |
| Effects and lifetimes | Current material lifecycle 73 clean assertions; prior 4.4 all-class replay 387 clean assertions. World-owned callbacks and surface-override retirement preserve cached meshes. | Current full replay, long-session residency, delayed variants and performance under six-actor spell floods. Online preparation still covers all classes rather than a changing roster. |
| Sandbox | Hosted practice passed 20 current two-client checks: late join, FFA damage/respawn, no local bots/autosave, byte-identical story save, no practice save, return and natural worker/port cleanup. Screenshot inspected; no runtime errors, three layout/Metal warnings. | Current solo/entry acceptance, full gate and matching backend/client rollout. Do not describe Sandbox as live based on source alone. |
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

The original broad preload policy moved costs into loading and increased residency. This closure narrows forest
families, removes extracted model textures from root declarations and avoids drawing hidden 3D worlds during
construction. These changes are not an accepted performance result: the current matched diagnostic is below.
Earlier 4.3 gains also increased loading and memory and were rejected.

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

## Latest run-content integration

All twelve run skills are captured from actual Archer/Plague/Warlock casts. The declaration contract now checks
`Data.RUN_SKILLS` as well as story/shared skills. Shared run-proc and consumable presentation variants are prepared
and included in the stress workload; skill/gem reward icons use the competitive zone scope. The nightly baseline
identity now includes the replay recipe hash, so changed workloads cannot silently reuse old baselines. Fourteen
audit unit tests pass. The installed immutable runner is `e24897599182100d`; no full nightly pass is claimed.

## Current performance decision: hold publication

All current diagnostic runs had `focused=false`; macOS reports `CGSSessionScreenIsLocked=true`. The user has
been asked to unlock the desktop. Existing layout/Metal warnings also prevent strict performance acceptance.
The following are single-process diagnostics on identical Godot 4.4.1/Metal/High settings and identical updated
six-actor recipes, with measurement shims on the `9ea4830` baseline. They are **not accepted before/after gains**.
The workload is an extreme effect flood, not ordinary combat or six network clients.

| Diagnostic | Baseline `9ea4830` | Final runtime `2a2f1e2` |
|---|---:|---:|
| Arena loading | 14.0 s | 43.1 s |
| Arena engine-reported VRAM | 1,888 MB | 2,958 MB |
| Forest loading | 31.3 s | 79.5 s |
| Forest engine-reported VRAM | 2,336 MB | 3,787 MB |
| Measured gameplay synchronous cache requests | 34 Arena / about 30 forest paths | 0 in both modes |

The initial candidate forest took 100.4 s / 4,773 MB before narrowing forest dependencies and suspending hidden
3D drawing. The later root-texture filter did not materially improve loading/residency. Do not claim it did.
Raw `kpi-final`, `kpi-loading-refined` and `kpi-model-roots` runs, patches and manifests remain under closure evidence.

Release blockers are concrete:

1. Finish a clean full functional gate after the verified BG fixture correction, including solo Sandbox/entry, all-class/run-skill
   replay and the remaining UI/co-op tests. Gate 5 is **red/incomplete**, not a release pass.
2. Reduce and measure preparation/residency on an unlocked desktop, then complete three valid matched repeats.
   Online all-class preparation, broad non-forest zone families and remaining atomic construction are still open.
   Preserve current art/gameplay and keep omitted dependencies visible through miss checks.
3. Obtain the shared staging handoff, publish matching client/broker/worker exports, and verify remote operation.
   Sandbox requires backend changes; this is not a client-only deployment. No push or deployment in this closure.

The BG clock probe also measured about 150 simulation seconds over 200 wall seconds during a source/debug
server + rendered-client run. That is not a release-server capacity measurement. Functional timer assertions now
check the simulation boundary with a bounded wall timeout; they do not certify tick rate or conceal that finding.

Final source check: `origin/staging` remains `3d4c661`, and Claude-1's latest committed gameplay remains `9ea4830`.
A separate unmerged `origin/claude-2/hero-codex` branch appeared at `f13c496` during the last fetch (no PR at this
checkpoint). It moves hero/run/talent data into JSON and adds an editor. It is not included in these results;
when integrated, rerun declaration/recipe capture and gameplay checks against its data-loading changes.
