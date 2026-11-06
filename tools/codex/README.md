# Hero Codex editor

A web editor over `data/codex/`. These are the JSON files the game loads its heroes' skills, rites, gems and
consumables from (`scripts/codex.gd`). Standard-library Python only.

```
python3 tools/codex/server.py --port 8765            # http://127.0.0.1:8765, basic auth
cloudflared tunnel --url http://127.0.0.1:8765        # a public https URL for it (trycloudflare.com)
```

- **Password**: `~/.config/ashen-codex/password` (generated on the first run; never in the repo). Any user name
  works, and the user name is written into each commit message.
- **Saving** validates the file, writes it, and commits only that file on the checkout's current branch. Saving is
  refused when someone else saved the same file since you loaded it.
- **Rules**:
  - An entry that is *in game* can be edited but not deleted.
  - A skill can't be switched to *in game* from here, because it needs code first.
  - A rite can go live from here only when every effect key is one the game reads (`data/codex/fx_keys.json`: the shared keys and the hero's own, plus
    `dmg:`, `cd:` and `cost:<skill>`).
- **Publish preview** pushes the branch, and pushes it to `test-codex` too, which starts the preview build. It is
  only allowed from a `claude-2/` task branch. Merging into staging stays with the integrator.
- `godot --headless --path . -s tools/codex_export.gd` rewrites the files from the game's data. It keeps design
  entries and any text that only the Codex has. Run it after adding a skill or a talent in code.
- `tools/codex_test.gd` checks that the game and the Codex agree.
