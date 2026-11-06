# Code organization

1. **Where things live:** see AGENTS.md's table and `docs/architecture_cleanup.md`. In short, `game/heroes/<hero>/` holds
   everything one hero owns, `game/systems/` the shared rules, `scripts/` and `assets/` whatever hasn't moved yet,
   `tools/` the project-wide tests and pipeline, `deploy/` the servers, and `docs/` the plans and these patterns. Models
   are committed as `.glb` only, never `.blend`.
2. **Typed GDScript.** Inference from a Variant is an error: write `var x: Type = ...`. A new `class_name` needs
   `godot --headless --path . --import`, which rebuilds the class cache.
3. **One concern per file**, named for it: a hero's look, its skills and their effects are kept apart, and each
   skill has its own folder (`game/heroes/<hero>/skills/<skill>/`). **Tuning is data** (the Hero Codex, `data/codex/`),
   not numbers scattered through the code; the constants at the top of a file are its tuning.
4. **Comment the why**, with the measured number and who asked, when a choice isn't obvious. The code's comments and
   short docs are where the next agent learns the rule.
5. **Every feature has a headless test** that prints `[X] ok/FAIL` lines. A hero's tests are in
   `game/heroes/<hero>/tests/`; the rest are in `tools/`. Run the tests for what you touched. `tools/nightly/gate.sh`
   runs them all (about 25 minutes).
6. **Branches:** work in a worktree, and push previews to `test-*`. Push to `staging` when an admin asks; CI builds
   it for itch and Steam staging. Never force-push over collaborators' commits. Push to `main` only on an admin's
   explicit request.
7. **Secrets** stay in their local stores (`~/.config/...`, Nakama env on the server). Never in the repo, prompts or
   Discord.
