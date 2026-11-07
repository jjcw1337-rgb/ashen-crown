# The Last Flame (archived)

The co-op horde defence: a sanctum round an altar fire, waves of monsters through glowing breaches, the fire fed
with logs from the moor, the fallen rising by the altar, and the Hall of the Last Flame leaderboard on the title. It
was retired from play on 2026-11-05 (no lobby mode, no solo start, the camp's Vigil Gate sealed) and archived whole on
2026-11-06 (Blaine). This folder has a `.gdignore`, so Godot neither imports nor exports it.

| File | What |
|---|---|
| `vigil.gd` | `Vigil`: the sanctum's builder (`Vigil.build`, zone `vigil`), the waves (`WAVES`), the fire (`FUEL`, `feed`), the round (`begin`, `apply`, `fx`), `respawn_at` |
| `flame_board.gd` | `FlameBoard`: submit a run's waves, read the best ten (Nakama RPCs `flame_submit`, `flame_top`) |
| `vigil_shots.gd` | its screenshots |

## To bring it back

Move the two scripts back under `game/maps/last_flame/`, then put back the hooks it had. The commit that archived
it removed every one of them (`git log -- archive/last_flame`, then `git show` that commit for the exact lines):

- `scripts/world.gd` `build`: `Vigil.ZONE: Vigil.build(self)`.
- `game/game.gd`:
  - `indoor()` and the zone's environment (an `elif kind == Vigil.ZONE` block: warm ambient, the altar's light);
  - the zone title (`Vigil.ZONE: return Vigil.TITLE`);
  - `_interact` kinds `vigil_gate` (travel to `Vigil.ZONE`), `vigil_exit` (back to the camp's `from_vigil` spawn)
    and `vigil` (kindle it, feed it a log: `net.vigil_feed`, `net.vigil_hi`, `net.request_vigil`);
  - the waypoint's activity (`waypoint_activities`, `waypoint_activity_go`, the `zone in [...]` list);
  - the death respawn (`Vigil.respawn_at`).
- `game/systems/net/net.gd`: `vigil_state`/`cl_vigil`, `vigil_event`/`cl_vigil_fx`, `request_vigil`/`sv_vigil`,
  `vigil_feed`/`sv_vigil_feed`, `vigil_hi`/`sv_vigil_hi`.
- `game/systems/combat/projectile.gd`: a projectile hits nodes in the `objective` group (the flame).
- `scripts/monster_warm.gd`: warm the waves' monsters (`Vigil.WAVES`).
- `game/systems/data/data.gd` `WAYPOINT_ACTIVITIES`: the `vigil` entry.
- `game/systems/net/mp_mode.gd`: `WAVES` and the solo label; `scripts/lobby_client.gd` `play_solo_waves`;
  `game/systems/net/match_instance.gd`: the `waves` mode (`begin`, finished when the flame is `lost`); the lobby service's
  `waves` mode (`deploy/lobbies/service.py`, removed earlier).
- `game/maps/camp/forest_camp.gd`: the Vigil Gate (`VIGIL_GATE`, its portal and two stone posts, the `from_vigil`
  spawn).
- `scripts/title_home.gd`: the Hall of the Last Flame board (`_build_board`, `refresh_board`, called from
  `UI.show_title`).
- `deploy/nakama/modules/ashen.lua`: the `last_flame` leaderboard and `flame_submit` / `flame_top`.
- Its tests: `tools/lobby_modes_test.gd` and `lobby_late_join_test.gd` ran a `waves` lobby too.
