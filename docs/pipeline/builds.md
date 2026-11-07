# Builds and tests

## Tests

Features have headless tests: scripts that drive the game and print `[X] ok` or `[X] FAIL` lines. A hero's are in
`game/heroes/<hero>/tests/`; the rest are `tools/*_test.gd`.
- Run one with `godot --headless --path . --fixed-fps 60 -s <test>.gd`, so it runs in game time.
- If it fails with "Identifier not found: Sfx", run it through `tools/_late.gd`:
  `godot --headless --path . -s tools/_late.gd -- res://<test>.gd`.
- Multiplayer tests run a server and players as separate processes; `tools/nightly/gate.sh` shows how. That script
  runs most of the tests and takes a long while; nobody requires it before a push.
- `tools/hero_reference.gd <hero>` checks what every skill of a hero does to training dummies against its record
  (`tools/references/<hero>.json`), so a rebuild can prove it changed nothing.
- `game/maps/verdant_reach/tests/bg_pvp_test.gd` (a server and two players, run through `tools/_late.gd`) takes a
  hero's name (`dragon <class>` for the dragons) and proves the server made and dealt its skills.

## CI

| Push to | Builds | Goes to |
|---|---|---|
| `staging` | Windows, Mac, Linux for the staging server, plus the stripped server build | itch and Steam's staging branch |
| `test-*` | Windows, Mac, Linux | downloads on the run, nothing published |
| `main` | the browser version and the downloads | the GitHub Pages site |

CI runs no game tests, so you run them. `export_presets.cfg` leaves `tools/` and every hero's and map's `tests/`,
`tools/` and `build/` out of builds. The stripped "Linux Server" build is what match servers run ([multiplayer](../systems/multiplayer.md)).
