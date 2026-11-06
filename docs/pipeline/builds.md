# Builds and tests

How the game is tested, built and shipped. CI builds; it runs no Godot tests (the preview build runs the lobby
service's Python tests), so you run them.

## Tests

Every feature has a headless test: a script that drives the game and prints `[X] ok` or `[X] FAIL` lines. A test
fails on any `FAIL` line, a `Parse Error`, or not finishing.

- A hero's tests are in `game/heroes/<hero>/tests/`. Everything else is in `tools/*_test.gd`, and the lobby service's
  are `deploy/lobbies/test_*.py`.
- Run one with `godot --headless --path . --fixed-fps 60 -s <test>.gd`. `--fixed-fps 60` runs the game in game time,
  so a test waits in frames and never by the wall clock.
- A test that fails with "Identifier not found: Sfx" touches the Sfx autoload before it exists. Run it through
  `tools/_late.gd`: `godot --headless --path . -s tools/_late.gd -- res://tools/<test>.gd`.
- Multiplayer tests run as two or three processes, a server and its players (`tools/bg_test.gd`,
  `tools/bg_pvp_test.gd`, `tools/mp_test.gd`). `tools/nightly/gate.sh` shows how each pair is started.
- Run the tests beside what you touched, and say which ones you ran. `tools/nightly/gate.sh <log dir>` runs 32 test
  scripts (the multiplayer ones as server and player pairs) and takes a long while. It was the nightly check before
  staging; admins don't require it before a push.

## What CI does

| Push to | Workflow | Builds | Goes to |
|---|---|---|---|
| `staging` | `.github/workflows/staging.yml` | Windows, Mac and Linux pointed at the staging backend, plus the stripped server | itch's staging channels and Steam's `staging` beta branch (each only once its settings exist); the server build is kept as the `AshenCrown-server` artifact |
| `test-*` | `preview.yml` | Windows, Mac and Linux | attached to the run as downloads; nothing is published |
| `main` | `deploy.yml` | the browser version and the desktop downloads | the repository's GitHub Pages site |

- Each workflow uses Godot 4.4.1, except the browser version, which uses 4.5.1 (`deploy.yml` says why).
- `tools/ci/write_build_env.sh` writes `scripts/build_env.gd` for the target, which says which backend a build talks
  to. A staging build without the staging settings stops rather than fall back to local.
- The staging run smoke-tests the server build: it must start and print no `SCRIPT ERROR`.

## What ships

`export_presets.cfg` decides what goes into a build.
- `tools/` and every hero's `tests/`, `tools/` and `build/` are left out.
- `build/` folders also hold a `.gdignore`, so Godot never imports them.
- **Linux Server** is the stripped build: textures with no pixels, meshes with only their bounding box. It is what
  match servers run ([multiplayer](../systems/multiplayer.md)).

Deploying the server build is done by hand: see "Deploying" in [multiplayer](../systems/multiplayer.md).
