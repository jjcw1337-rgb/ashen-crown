# Loading migration: release status — 2026-11-06

Runtime candidate `a0e7c07` includes staging `66172e2` (forest cleanup). The full functional gate finished with failures; focused corrections are running;
**this candidate is not yet published and has not passed performance acceptance**.
Shared guidance: [loading](../patterns/loading.md), [effects](../patterns/effects.md),
[measuring](../patterns/measuring.md). Raw local evidence: `workspace/output/perf-resume/`.

## Whole-change review

Main candidate: `test-codex-release-20261106` at `a0e7c07`, incorporating staging `66172e2`.
The older `test-codex-perf` checkout and detached comparison worktrees are not separate release candidates.
PR #4 remains the integration PR. Publication status below must be updated from actual CI/server evidence.

| Shared system / area | Delivered code | Current evidence / remaining limit |
|---|---|---|
| Asset readiness | `ContentCatalog` declares zone, class, monster and UI roots; `ResCache` shares one bounded loading worker and tracks owners. `Game` waits before activating play. | Native declarations, real root loading and BG/Arena world dependency checks pass. Unusual dynamic content still needs declarations. |
| Resource lifetime | Scope release, cached immutable mesh fragments, warm-material retirement and `SurfaceMaterials` cleanup. | Cache/material lifecycle and repeated Sandbox cleanup pass. Legacy references and long-session memory are not fully resolved. |
| World construction | Incremental terrain rows and grass, checkpoints in forest/camp/fern builders, incremental sea-chart CPU work. Used through the shared world path for story/travel and match worlds. | Terrain contracts and earlier scheduled/synchronous world parity pass. Mesh upload, collision/masks, minimap GPU readback and some effects remain atomic. |
| Class and effect preparation | Actual recorded skill events, current run skills, delayed effects, shared talent/consumable variants, monster and reward-card preparation. Solo prepares its class; online prepares all classes. | Current all-class replay passes 649 assertions without errors/warnings. Online preparation is still broader than the actual roster; no all-combination GPU certification. |
| Story, town and UI | Preserve current staging gameplay; repair save recovery, title/loading lifecycle, multiplayer layout and run-HUD visibility. | Current story/save, UI input, four-size lobby, run/survivor, Codex and camp-access checks pass. Title's raw file-count diagnostic incorrectly includes backup files; isolated character-ID check passes, fixture correction pending. |
| Battlegrounds and PvP | Preserve automatic forest start, camp rewards and extraction; fix fresh-run ticket identity, result Return flow, low-FPS bow instability and swept-arrow collisions. | Current BG and two-player PvP checks pass. Earlier ordinary normal-clock BG completion predates the final forest cleanup; final remote journey remains required. BG has tangent/Metal/ObjectDB exit warnings. |
| Sandbox | Requested public solo entry and authenticated hosted practice, temporary class/gear, bounded bots, respawn, late join, no save/reward stakes. | Current solo/entry/repeated cleanup pass. Matching broker/worker deployment and final hosted remote checks remain. |
| Measurement and enforcement | Wall-clock benchmarks, required scenario/repeat coverage, median/worst-repeat limits, log/focus/concurrency checks, per-resource timing, CI dependency/construction guards. | Guard/Python checks pass. These tools expose regressions; they do not establish a performance win. Scheduled jobs removed by upstream remain removed. |

At `a0e7c07` versus staging `66172e2`, the diff contains 196 files: 63 game-runtime files
(1,287 added/396 removed lines), 98 test/tool files, 29 documentation/evidence files, two lobby-service
files and four CI files. About 10,000 added lines are documentation and retained diagnostic evidence.
These are exact diff categories, not a completion percentage. The runtime changes and their risks are the
review priority; older failed comparisons remain historical evidence, not current acceptance.

## What is implemented

- Shared content declarations, a bounded single loading worker, resource ownership and release.
- Scheduled terrain/grass construction and forest checkpoints; sea-chart CPU work is incremental.
- Class-effect preparation, current run-skill recipes, monster/reward-icon preparation and material retirement.
- Hosted/solo Sandbox, responsive multiplayer controls, and reproducible functional/performance tools.
- Scheduled jobs were removed by staging `67937fb`; they have not been reinstated. Audit tools remain manual.

## Current verification

| Check | Evidence and limits |
|---|---|
| Ordinary Battlegrounds | `journey-6`: rendered Archer plus real local lobby worker; create/Ready/Start, bell, ordinary walking/combat, camp reward and upgrade, normal five-minute portal opening, server-confirmed extraction, save once and Return/home. Walked 159.6 m, reached level 5, two camps cleared. No teleport, free healing, invulnerability, forced clock or direct result calls. Exit 0, zero runtime errors; tangent/Metal/ObjectDB shutdown warnings remain. Worker exited naturally and released its port. Screenshots inspected. |
| Entry fix | The ordinary test exposed an empty story-save ID being sent instead of the ticket's `run_archer` identity. The client now sends the reserved lobby identity without assigning a story save to the run. Actual admission verified; RPC signatures unchanged. |
| Archer stability | Low-FPS bow integration produced NaN mesh transforms during ordinary combat. Bounded substeps fix the spring; 11 native numerical checks pass clean, and the completed ordinary combat run has no transform errors. |
| Run guidance | Corrected per-frame client HUD hiding, forest objectives/portal/collapse wording, story-quest bleed-through and transient text over run menus. At `a331b23`, rendered BG checks confirm real per-frame guidance and no story-quest bleed-through; the latest merged gate repeats them. Ordinary journey evidence above predates these final UI edits. |
| Lobby layout | Four viewport sizes, 1024×768 through 2560×1440: zero bounds/input failures or runtime errors/warnings. Inspected small-screen renders. Functional only; a small concurrent fixture was recorded. |
| Current skills | Real casts captured Knight 32 events/13 skills, Wraith 50/14, Demon 48/14, Doug 64/15, Serpent 20/9 and Wyvern 29/9. Guards require Aegis burst, Death Mark pop, nonempty Detonation positions, Tomb shatter and Thunderhead bolt/end. Merged Warlock captures retain 64 events. Latest declaration contract: 2,857 checks, zero failures/errors/warnings. |
| Core contracts | Resumed native compile; terrain 27/cache 23/roots 143/world 7/parts 47/material 73 checks clean before the latest dragon integration. Full gate is rechecking current runtime. |
| Latest pre-integration multiplayer | `a331b23`: BG 61 and PvP 24, clean runtime logs; BG has six rendering warnings. World dependencies 7 and story play pass after isolating the asset cache. The full suite was interrupted for the subsequent staging merge; it is not a full pass. |
| Earlier multiplayer evidence | `2a2f1e2`: BG 45, two-player PvP 24, survivor Arena 34 and hosted Sandbox 20; zero runtime errors, rendering/layout warnings documented. These are historical and do not replace the active current-candidate gate. |

## Performance decision

A matched `45e2f82`/`a331b23` six-actor Arena pilot completed without runtime errors and with no
competing Godot processes. Candidate combat had zero synchronous cache misses; the baseline had 34 paths
loaded synchronously. **Both were unfocused**, so FPS/stall numbers are not accepted performance evidence.
The diagnostic still shows the cost of broad preparation: loading 13.3 → 39.9 s and reported VRAM
2,000 → 3,028 MB. First-use maximum was 10.5 → 2.1 s, also unaccepted because of focus. Remaining comparison
runs were stopped instead of counting invalid repeats. This predates the latest Warlock/Codex merge; no
performance result is asserted for the final merged candidate. Evidence: `kpi-release-pilot-4/`.

Do not describe this as an overall speed win, a cold-driver-cache test or a certified performance release.
Online preparation still covers all classes, some construction/upload/minimap operations remain atomic,
and long-session residency plus three valid matched repeats remain open. The earlier 4.3 gains were also
rejected for loading/memory regressions; see [historical results](IMPLEMENTATION_RESULTS.md).

## Final gate corrections

The `a514e74` gate passed native save recovery, BG/PvP, 646 class-effect assertions, title/UI/controls, terrain,
content/world, story, camp/survivor and solo Sandbox/entry checks. It was stopped after two failures: Glacial
Shard skipped enemies on a long frame, and Warlock’s headless fixture emitted a PagedAllocator shutdown error.
The failed logs remain in `gate-integrated-2/`; this is not a full green gate.

A controlled real-project arrow probe reproduced three missed targets, then verified that the corrected swept
query hits/chills all three and selects the nearest ordinary-arrow target (six checks, clean exit/log). Runtime
`3af589e` applies that correction and adds 150/350 ms regressions. The talent fixture’s `scripted` field is a
seconds counter, so its stationary targets now remain still for the whole cast. Warlock’s real-renderer rerun
passed with a clean exit and one Metal warning; the gate uses that renderer on Mac.

The subsequent forest-cleanup merge preserves automatic raid start without bells, quieter ambience, mushroom
size/lifetime fixes and camp accessibility. The ordinary journey and HUD checks follow the new flow. The new
camp-access fixture has isolated saves and normal `current_scene`/teardown. Native compile passed cleanly.
The fresh full gate (`gate-integrated-3/`) completed on this merged candidate without checkpoint reuse.
It recorded 48 green cases and five red cases; the original wrapper was interrupted, so its final process exit
is unavailable. This is not a full green gate. See the correction record below.

## Release checks remaining

1. Finish the current full native/rendered/network gate; retain and fix failures rather than ignoring errors.
2. Inspect current HUD/results and Arena/Sandbox renders. Ordinary completion is separate from `bg_test`
   (accelerated clock/assists) and `run_playthrough` (teleports/healing/direct results).
3. Publish coordinated staging client and lobby worker/broker builds, then verify remote admission/gameplay.
   Sandbox requires the broker/worker update; a client-only upload is insufficient. Main is unchanged.
4. Validate focused performance before making speed/budget claims. Keep the loading/residency tradeoff visible.

The new integration preserves Warlock, Hero Codex, save recovery and newer staging fixes. The corrupt-save
reader now tries backups without emitting JSON parser errors, and character selection/portraits use recoverable
data. The old broken-disconnect diagnostic is opt-in; the release check exercises the repaired path with no
error allowance. New fixtures set `current_scene`, matching a normal launch. A private copy-on-write import cache prevents another checkout’s cache cleanup from invalidating this run. No game-editor import was performed.

The user already authorized staging publication. Local staging integration is reserved by Codex; no other
agent's checkout has been changed. Separate unmerged hero-codex branches are outside this frozen candidate.

## Current release-gate findings

The full run completed 48 green cases. Five cases were red: vendor random work selection; LAN join errors
from retired enemy effects; Plague host's premature class-readiness check; and Arena/Sandbox interrupted by
Codex's own simultaneous diagnostic probe. The latter was a test-scheduling mistake, not evidence of a match
failure. All original logs remain. Title also printed an incorrect duplicate-save diagnostic without failing.

The final runtime change guards enemy hit/chill/stun sends with the existing connected-client check. All 77
RPC declarations remain identical. LAN now uses wall-clock ready voting and waits for actual player/world
readiness; important outcomes fail the process instead of merely printing false. Plague waits for the partner's
class to load. Vendor exercises its real work-selection path with reproducible random draws. Title checks
character IDs, excluding backup files. These fixtures isolate saves/cloud and tear down normally.

Per Blaine's request to reassess and finish, release verification retains the completed checks on unchanged
systems and reruns affected paths. This consolidated evidence is distinct from an uninterrupted green full-gate
run; no old failed output is relabelled as a new pass. The routine full-gate command remains unchanged for future
runs. Final targeted results, CI/publication and remote gameplay must still be recorded before calling this shipped.


Focused correction results so far: native compile, title, vendor, disconnect-during-loading/stale-enemy sends,
LAN host/client and Plague host/client all exit 0 with no runtime errors. Title has one Metal warning; the
others have no warnings. LAN verifies kills/XP, bidirectional effects, loot, return travel and clean disconnect.
Hosted Arena/Sandbox are executing sequentially; publication and remote checks remain pending.
