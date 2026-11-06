# Ashen Crown: instructions for every coding agent

This file is the shared entry point for **any** agent working in this repo (Claude Code, Codex, ChatGPT, on any
machine). Claude reads it through CLAUDE.md, which holds the full code map and the history of each system.

## Read first

1. **The default patterns:** follow these unless a task says otherwise, and update them when you change a pattern.
   - [Loading and first-time costs](docs/patterns/loading.md): ResCache, warm-ups, no shader per cast, zone preloads
   - [Dedicated servers](docs/patterns/servers.md): the stripped server export, no pixels or meshes on servers,
     the 30 fps tick, matches started when there is room
   - [Multiplayer shape](docs/patterns/multiplayer.md): Enter World + Steam co-op vs. lobby-browser matches on our servers
   - [Skill effects](docs/patterns/effects.md): effects are events; handlers only draw
   - [Measuring](docs/patterns/measuring.md): which tool, how many runs, the budgets
   - [Code organization](docs/patterns/code-organization.md): where things live, typed GDScript, tests, branches
   - [Making assets](docs/patterns/assets.md): Meshy concept → model → Blender prep/rig → Godot, the quality bar, budgets and performance rules
2. **CLAUDE.md**: the code map ("Code map"), every system's rules and gotchas, and the test list.
3. **CONTRIBUTING.md**: human setup and workflow.

## Ground rules

- Godot **4.4.1** (desktop), binary on this Mac: `/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot`.
- Before pushing: run `bash tools/nightly/gate.sh <logdir>` from inside the worktree you are testing; it must be green.
- Branches: your own worktree; previews on `test-*`; `staging` only with a green gate; `main` only on an admin's
  explicit request. Never force-push over someone else's commits; rebase on the latest remote first.
- Never put credentials in the repo, prompts, logs or chat. Never commit `.godot/`, `build/`, `server/` or `.blend`.
- Say when something is unmeasured. A fix counts only with before and after numbers from the same tool.
