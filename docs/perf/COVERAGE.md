# Shared performance coverage — 2026-11-05

The short working guidance lives in [loading](../patterns/loading.md), [effects](../patterns/effects.md)
and [measuring](../patterns/measuring.md), reached through AGENTS.md and CLAUDE.md. This page records coverage,
not another rulebook. Update affected rows as work lands; no percentage implies untested content is complete.

| Area | Implemented / evidence | Still needed |
|---|---|---|
| Shared loading | ContentCatalog roots, one bounded loading worker, owner scopes, cancellation and release. Cache 23, declarations 1,775, actual roots 278 and fragment 47 checks passed on 4.4.1. | Audit remaining direct loads and session-long references; resource counts do not prove every content path is covered. |
| Zone / screen lifecycle | Game preparation, host admission, return-to-title cleanup. Native host preparation: 10 assertions, zero errors, one Metal warning; screenshot inspected. | Full current-engine travel/interruption/late-join suite and UI residency; actual Steam transport remains a separate check. |
| Construction | Deterministic grass jobs; shared fragment recipes for Plague vial/vat. Earlier layout parity checks retained. | Other builders, minimap and expensive effect assembly; repeat parity after integrating new map builders. |
| Effects / materials | All-class replay: 387 clean assertions on 4.4.1; cached-mesh retirement: 73 clean checks. Delayed visuals use world-owned callbacks. | Delayed variants, monster/boss effects and every class combination; long-session memory soak. |
| PvP priority | Three six-actor profiles: mixed spells, moving dragons, forest summoners/status effects; nightly moving-target simulator and Sandbox lifecycle fixtures. | New profiles and solo/hosted Sandbox need current-engine gameplay/render acceptance. Presentation floods do not verify network matches. Latest six-client attempt was stopped for memory pressure, not passed. |
| Lean servers | Client preparation skips dedicated servers; retain Claude's server builders/capacity policy. | Re-measure affected modes after integrating gameplay/map changes; client FPS cannot certify server capacity. |
| Nightly audit | Installed at 22:30 Mac local time, bounded busy retries, isolated published build, three repeats, median and worst-repeat checks. Expanded runner: 13 unit tests passed; installed preflight deferred correctly. Earlier launchd/isolation probes passed. | Full published-build workload awaits staging contracts and an available test window. Installation is not an audit pass. |
| Release | Latest full 4.4 gate reached 13 green cases before interruption; source is committed locally. | Complete green gate, latest Claude integration, exports/publication verification. This continuation is not pushed or live. |

Evidence and commands: [implementation](IMPLEMENTATION.md), [staging results](STAGING_RESULTS.md),
[nightly operation](NIGHTLY_AUDIT.md), `tools/ci/perf_contracts.py`, `tools/nightly/gate.sh`,
`tools/nightly/bench.sh`. Keep functional correctness, performance acceptance and publication status distinct.
Earlier improvements also increased loading time and VRAM; no complete performance acceptance is claimed.

## Integration with Claude's current work

Reviewed committed `test-godot-44` through af34478: multiplayer run characters, camps, survivors and the
Verdant Reach replace parts of the old flow/map. Integrated committed changes through af34478 in a4c37c8. Claude's subsequent uncommitted lobby redesign remains separate.
Preserve those product decisions. Adapt the catalog, builder scheduling and affected tests to the new paths;
do not restore retired modes merely to satisfy old fixtures. The existing `crypt` KPI identifier currently
means the Battlegrounds scenario; verify what it actually builds before comparing old/new map measurements.

The shared Mac's heavy-tests and staging claims remain with Claude-1 at this checkpoint. No competing test
run was started. The handoff records the local branches and overlapping interfaces for integration.

## Sandbox / recurring QA checkpoint — 2026-11-05

[Sandbox behavior and validation](SANDBOX.md) records the solo/hosted paths and test commands.
Mode-specific solo controls preserve retired Waves. Worker free-for-all, automatic respawns and
late admission are implemented but not gameplay-verified. New broker support requires backend rollout.
Fifty-four broker/HTTP, thirteen nightly-audit and thirteen benchmark/log checks pass; fourteen changed
GDScript files parse with gdtoolkit (grammar only, not native compilation). Bash syntax and diff checks pass.
The installed audit runner includes the additions; its full exported workload awaits their staging rollout.
No new GPU results, full green gate, staging push, live Sandbox or server-capacity gain is claimed.
