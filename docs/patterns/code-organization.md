# Code organization

1. **Where things live:** `scripts/` is the game (the code map is in CLAUDE.md, "Code map"), `tools/` holds headless
   tests and measuring tools, `deploy/` the servers, `assets/` the files (.glb only, never .blend), and `docs/` the plans
   and these patterns.
2. **Typed GDScript.** Inference from a Variant is an error: write `var x: Type = ...`. A new `class_name` needs
   `godot --headless --path . --import`, which rebuilds the class cache.
3. **One concern per class**, named for it: a class's look in `<class>.gd`, its skills in `<class>_skills.gd`, its
   effects in `<class>_fx.gd`. **Tuning is data** (`scripts/data.gd`, `scripts/talents.gd`), not numbers scattered in
   code; the constants at the top of a file are its tuning.
4. **Comment the why**, with the measured number and who asked, when a choice isn't obvious. The code's comments and
   CLAUDE.md are where the next agent learns the rule.
5. **Every feature has a headless test** in `tools/` that prints `[X] ok/FAIL` lines. The gate,
   `bash tools/nightly/gate.sh <logdir>`, run from inside the worktree being tested, must stay green before a push.
6. **Branches:** work in a worktree; push previews to `test-*`; push to `staging` once the gate is green (CI builds
   itch staging). Never force-push over collaborators' commits. `main` only on an admin's explicit request.
7. **Secrets** stay in their local stores (`~/.config/...`, Nakama env on the server). Never in the repo, prompts or
   Discord.
