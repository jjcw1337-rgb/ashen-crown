# Targeted verification of the performance design

2026-11-05. Follow-up requested by Blaine: test the signals and review existing work before implementing anything system-wide. Runtime tests pin staging `8845213`; the audit branch contains tools/docs only after temporary instrumentation is removed.

## Revisions reviewed

The measurement revision is deliberately fixed. During this review, staging advanced to `83678ef`, changing the title to one hero and reorganizing home/LAN controls. Its source diff and updated `CLAUDE.md` were reviewed. It removes the second dais and its visual effects, but does not change `Game.load_zone`, `ResCache`, `ZonePreload` or `Kpi`. The title construction still occurs during `ui.setup`. Thus the proposed shared contracts remain applicable, but the title timings below belong to the older two-dais revision and are **not** measurements of the newly shipped title. The separate triage branch `c3153b5` was also reviewed for cleanup and lifetime changes.

## What was tested

- Exercised the existing nightly comparison with six synthetic fixtures. Unchanged data passed and a 60→40 FPS control failed. **Seven missing scenarios, 500 ms p99, 20 hitches/minute and a 20-second load each passed when average FPS was unchanged.** These are deliberately constructed inputs, not claims about actual gameplay. Reproducer: [`perf_verify_gate.py`](../../tools/perf_verify_gate.py).
- Ran real Forward+ moor/fight scenarios and a diagnostic half-resolution intervention, with phase/query probes and an independent monotonic frame observer. Retained every result rather than selecting the fastest. The initial nine-run set had other headless Godot tests active; it is diagnostic evidence, not a clean hardware baseline. The intervention did not record its effective scale in those runs, so **no resolution-scaling performance conclusion is drawn**.
- Ran three real title → new knight → character window twice → moor/camp round trips. Inspected actual title, world and fight captures. The test profile persists between these flows; they are repeated user journeys, not identical first-install experiments. A second title-idle window was added for flows 2–3 to separate initial display work from later idle behavior.
- Repeated core scenarios after the competing Godot tests cleared, recording actual render scale and window focus as well as detecting any new competing Godot process. Other ordinary desktop apps remained active; “quiet” means no other Godot, not a controlled lab machine.

Detailed measurements and validity information are in [the generated evidence](evidence/verification-summary.json). Values from different conditions must not be pooled into one claimed FPS gain.

## Measured signals

These are diagnostic observations, not optimized before/after results:

| Observation | Evidence | Decision |
|---|---|---|
| Regression gate coverage | Four deliberately bad conditions accepted: missing scenarios, p99, hitch rate, load duration | Repair the measurement contract before judging system-wide changes |
| Character panel first/repeat use | Six openings, observed maximum frame 21–82 ms | Preserve the working UI warmer; this tested path is not the first rewrite target |
| Repeated world transitions | Camp→moor observed longest callbacks about 3.5–5.8 seconds, including repeated visits | Asset reuse alone does not make construction incremental |
| Startup title/UI construction | Two instrumented flows measured about 6.1 and 6.7 seconds inside UI setup | Include title construction in preparation scheduling, before first-visible readiness |
| Full-scan enemy queries | Quiet wrapper runs measured about 2.3–3.9 ms per sampled frame in query bodies | Worth an isolated spatial-query experiment, not proof a particular index wins |

Nine initial scenario runs, six no-other-Godot runs, three attempted-focus runs and three user-flow runs were retained. The first eighteen scenario logs have no script/parse/runtime error lines; one of the three flow logs reports a shader/RID leak at exit. Their numeric FPS results are in the evidence, but the wrapper reported no window focus; foreground requests did not change it. Native presentation/visibility was not established for those runs, so treat them as rendered diagnostic viewport measurements, not a player-facing FPS baseline. This limitation does not turn the observed synchronous call spans or synthetic gate behavior into hypothetical findings.

Three further runs through the normal main scene completed with zero script/parse/runtime error lines, no competing Godot, a visible native window and render scale 1. They still reported no window focus. Moor FPS was 14.5–22.6 (median 14.8) in these source/debug conditions, with substantial spread. This confirms that the normal KPI route runs, but does **not** establish a focused/exported release baseline or prove that the wrapper caused the earlier low rates.

A resource-only probe in three separate processes also confirmed that `ResCache` returns the same loaded resource on 1,000 repeated accesses, keeps it alive after the caller releases it, and permits release when its retained references are cleared. Initial loads took 58–91 ms; the 1,000-hit loops took 0.47–1.44 ms total. Logs were clean. This tests one fire-arrow resource and process-cold Godot resource state, not cold disk/driver state, scene instantiation or shader readiness. **The existing cache works; its missing shared readiness/lifetime policy is the architectural issue.**

## Findings that affect the design

**The measurement system needs a stronger contract.** The gate probes turn the previous code-review concern into a reproducible behavior. Coverage, required metrics, runtime validity and frame-time budgets must be part of the gate, alongside its useful existing average-FPS check.

**Frame clocks need explicit definitions.** The official KPI records `delta / Engine.time_scale`; a separate observer records elapsed monotonic time between main-loop callbacks. They do not yield interchangeable spike magnitudes/counts. Combat hitstop explains why raw simulation delta also differs from the KPI's corrected delta: do not compare the raw delta count with the official result and call them the same metric. The independent sampling windows differ at their boundaries by approximately one frame. A callback interval is a main-loop stall observation, not a hardware presentation timestamp.

**Background resource requests are not the end of loading.** Temporary spans around the existing implementation showed substantial time in synchronous world construction, minimap preparation/drawing, skill preparation and UI preparation. These are inclusive stages: `world_build` can include waiting for a resource; minimap timing includes awaited frames and other work scheduled in them. The probes do not claim to separate disk, decompression, GPU upload and shader compilation inside those stages.

**The title is part of startup work.** `Game._ready` calls `ui.setup` before `_boot_preload`; UI setup constructs the title stage. The added boot span measured that setup separately. A policy that begins all preparation after title construction misses that earlier synchronous work. The title itself also needs a distinction between first-visible readiness and steady idle cost.

**Keep the UI warming already present.** All six character-window openings in the three flow probes stayed below 100 ms per observed frame. This is evidence that the tested path currently works acceptably under that threshold, not a proof that every UI panel or preset is prepared. Large transition pauses remained in the same journeys, supporting a shared staged coordinator rather than replacing the successful panel warmer.

**Retirement deserves a common owner.** Claude's unmerged `nightly-2026-11-05-triage` work includes `SkillFx.clear(hero)` on zone departure and weak-reference/callback lifetime fixes. That work was inspected, not merged or independently certified here. It fits the proposed lifecycle system and should be integrated rather than duplicated. One flow run also emitted a shader/RID leak at exit; that run is not a completely clean pass, even though its transitions completed.

**Nearby-enemy queries are a measurable candidate, not a universal rewrite mandate.** Instrumentation counts calls and elapsed query-body time. This includes a small amount of measurement overhead and does not measure the cost of maintaining a proposed index. A spatial index still needs representative-density, update-cost and semantic-equivalence tests before adopting it across combat.

## Conditions and limitations

Apple M6, 16 GB unified memory, macOS 27.0; Godot 4.3 stable `77dcf97d8`, Vulkan/MoltenVK Forward+, source/debug runtime, High, 1600×900 viewport, VSync disabled for diagnostic throughput. Global and game RNG are seeded by the wrapper; existing scenario logic is preserved. Wall-time-driven simulation, external scheduling and GPU-driver caches still prevent bit-for-bit replay.

Imported resources are reused read-only from the existing prepared cache; there was no full import or shared cache deletion. The isolated working tree needed additional existing import descriptors before the title/camp flow could run. The first incomplete-cache attempt is retained separately and excluded from valid flow results. This was a local harness setup problem, not evidence that shipped clients lack those assets.

A preliminary stock-cache run emitted a Vulkan pipeline-cache write error. Subsequent diagnostics disabled **Godot's disk pipeline cache in this worktree only**; the shader cache and driver cache were not erased. Consequently these are not certified cold-driver or stock exported-build startup numbers. Godot explicitly distinguishes its disk pipeline cache from the driver's cache. [Godot 4.3 ProjectSettings](https://docs.godotengine.org/en/4.3/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-pipeline-cache-enable)

The initial wrapper had a parse error from an API unavailable in 4.3; a resource-only probe also initially hit a Variant type-inference error. Both were corrected before their successful measurements. Failed/aborted pilot logs remain in the local evidence directory. Do not turn “exit 0” into “clean pass”: the manifests retain engine warnings/errors separately, and the flow leak is reported above.

No all-class/all-zone matrix, multiplayer late-join performance test, cross-platform export comparison, GPU capture, long memory soak or benchmark of a replacement architecture was performed. No frame-rate improvement, production regression or memory-leak fix is claimed. The spatial index, pools, compression policy and cache size remain implementation hypotheses or sizing decisions.

## Reproduction and review

Local raw evidence: `workspace/output/perf-verification/` (logs, full frame traces, screenshots, manifests and failed pilots). Checked-in evidence is a compact summary, not a replacement for those raw files.

The wrappers use an isolated `user://` directory and force local/offline backend configuration. The `--native` runner uses the normal main scene and its configured build environment; confirm a local/offline configuration before reproducing it. Prepare resources in a separate checkout; **never invoke editor/import with the read-only shared cache links used by this audit worktree**. Use an isolated `override.cfg`, for example:

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="AshenCrown-PerfVerify-YOUR-RUN"
[display]
window/size/mode=0
window/size/window_width_override=1600
window/size/window_height_override=900
window/vsync/vsync_mode=0
[rendering]
rendering_device/pipeline_cache/enable=false
```

Apply [the temporary diagnostic patch](evidence/phase-query.patch) only to an isolated matching checkout to reproduce phase/query counters; it is not an optimization and is not part of the runtime changes in this branch. The ordinary scenarios can run without it, but query/phase diagnostics will be empty. Commands:

```sh
python3 tools/perf_verify_gate.py /absolute/output
python3 tools/perf_verify_runs.py /absolute/Godot /absolute/output/quiet --require-quiet --only moor,fight
python3 tools/perf_verify_runs.py /absolute/Godot /absolute/output/flow-verified --flow
python3 tools/perf_verify_runs.py /absolute/Godot /absolute/output/native --native --require-quiet --only moor
python3 tools/perf_verify_report.py /absolute/output docs/perf/evidence/verification-summary.json
```

The runner times out its own child, refuses a pre-existing competing renderer and records concurrent headless processes. `--require-quiet` rejects a run if another Godot appears. It does not stop anyone else's work or publish metrics. Remove the temporary runtime patch and local overrides after measurement. Both were removed after this audit; game and KPI source were byte-checked against the original commit. Only diagnostic tools, evidence and design documentation remain changed. No own test processes remain. Read-only resource-cache links remain in the isolated worktree, so the no-import restriction still applies.

The resulting [system design](SYSTEM_DESIGN.md) specifies five shared contracts. Implement the contracts incrementally around existing helpers, then use improved measurements to decide which expensive implementation to change first. This follows the engine's distinction between sustained cost, intermittent stalls and loading, and its emphasis on hypothesis tests. [Godot optimization guidance](https://docs.godotengine.org/en/4.3/tutorials/performance/general_optimization.html)
