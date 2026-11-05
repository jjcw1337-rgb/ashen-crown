# Audit verification

This page records the initial static audit at `123b77b`. The subsequent runtime probes, limitations and revised design are in [VERIFICATION.md](VERIFICATION.md) and [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md). Statements below about tests not performed apply to that initial audit.

2026-11-05. Audited source baseline: `8845213e29577b81fda420b2a0b89e5799231002`.

Completed: reviewed the supplied brief, branch instructions and relevant performance notes; traced resource access, zone loading, warmers, combat queries, projectile creation and benchmark selection; researched primary engine/vendor/developer sources; generated a reproducible lexical inventory.

`python3 tools/perf_inventory.py` completed successfully. Its output reports 146 direct load sites, 30 ResCache accesses, 7 preloads, 108 shader creations, 3 background requests and 3 threaded collections. The recorded model manifest has five zone keys. The tracked PNG/JPEG import subset contains 294 import configurations. These are static observations, not runtime performance measurements.

Validated the inventory tool's Python syntax, every CSV row against its actual source line, and every local report link. `git diff --check` completed successfully. Runtime tests are not applicable to these documentation and inventory-only changes.

The inventory excludes comments/string contents when identifying calls. Dynamic paths are labeled unresolved. Function names are the most recent enclosing-style function declaration found by a lexical scan, not a parser/call-graph proof. Generated source, embedded texture import settings and all runtime dependency branches are not comprehensively covered.

Not performed: new rendered benchmark runs, an all-class/all-zone sweep, fresh shader-cache tests, memory soak, visual comparison, gameplay regression tests, or server load testing. No runtime optimization or performance improvement is claimed from this change. Historical timings in the audit are explicitly attributed to existing project reports.

No staging/production deployment, server modification, shared asset import, shared cache deletion, asset generation, texture conversion or game-code modification was performed. The deliverable is the audit, design and inventory tool; implementation and before/after validation remain future work.
