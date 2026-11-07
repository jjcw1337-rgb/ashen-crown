# Hero Codex editor

A web editor over `data/codex/`. These are the JSON files the game loads its heroes' skills, rites, gems and
consumables from (`game/systems/data/codex.gd`). Standard-library Python only.

```
python3 tools/codex/server.py --port 8765            # http://127.0.0.1:8765/?key=<link key>
cloudflared tunnel --url http://127.0.0.1:8765        # a public https URL for it (trycloudflare.com)
```

- **Access**: the link is the key, so there is no login prompt (Blaine, 2026-11-06).
  - Opening `/?key=<key>` once sets a cookie that lasts a year. The key is in `~/.config/ashen-codex/link_key`,
    generated on the first run and never in the repo.
  - The page asks once for a name to write into each commit message.
  - HTTP basic auth with `~/.config/ashen-codex/password` still works for scripts.
- **Saving** validates the file, writes it, and commits only that file on the checkout's current branch. Saving is
  refused when someone else saved the same file since you loaded it.
- **Rules**:
  - An entry that is *in game* can be edited but not deleted.
  - A skill can't be switched to *in game* from here, because it needs code first.
  - A rite can go live from here only when every effect key is one the game reads (`data/codex/fx_keys.json`: the shared keys and the hero's own, plus
    `dmg:`, `cd:` and `cost:<skill>`).
- **Publish preview** pushes the branch, and pushes it to `test-codex` too, which starts the preview build. It is
  only allowed from a `claude-2/` task branch.
- **Live mode** (`--live staging --godot <godot>`, Blaine 2026-11-06: the editor updates the shared game). Run it on a
  worktree of its own on the branch `claude-2/codex-live`, for example
  `git worktree add -b claude-2/codex-live ../ashen-crown-claude-2-codex origin/staging`, then import it once
  (`godot --headless --path . --editor --quit`).
  - The checkout follows `origin/staging` by itself, at most once a minute when the page loads. Unpublished saves
    are replayed on top. It never touches uncommitted changes, and a conflict is aborted and shown on the page.
  - **Publish to the game** runs `tools/codex_test.gd`, then pushes to `staging` as a fast-forward, never a force.
    The next staging build ships the edit.
- `godot --headless --path . -s tools/codex_export.gd` rewrites the files from the game's data. It keeps design
  entries and any text that only the Codex has. Run it after adding a skill or a talent in code.
- `tools/codex_test.gd` checks that the game and the Codex agree.
