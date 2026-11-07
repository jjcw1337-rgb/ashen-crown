# The Verdant Reach (game/maps/verdant_reach/)

The Battlegrounds' map: a 210 m forest of monster camps, four starting glades at its corners, four Extraction
Portals at its edges and two bosses in its depths. Players come in from a Battlegrounds lobby as run characters
(level 0), clear camps for skills, rites, gear and gems, and extract to keep their hero as a survivor.

| File | What |
|---|---|
| `verdant_reach.gd` | `BgForest`: builds the map (zone `bg`): relief, trails, the stream, trees, regions, and the camps from its `CAMPS` table |
| `camps.gd` | `Camps`: a camp's rules: its monsters (own pack), its sealed chest, the tier's level and loot, the chest's colours |
| `forest_life.gd` | `ForestLife`: the forest's life: grass, flowers, mushrooms, birds, butterflies, wind |
| `battlegrounds.gd` | `Battlegrounds`: the raid's rules on its match server: rounds, portals, extraction, deaths, PvP checks |
| `bg_matchup.gd` | `BgMatchup`: the HUD's matchup cards (the raiders' classes) |
| (its bosses) | Hrimgar (`game/monsters/hrimgar/`) and Old Mossbeard (`game/monsters/mossbeard/`): their camps are rows of `CAMPS` |
| `props/` | the forest's own Meshy pieces: mushrooms, fungus (also the Poison Mushroom's body), brambles, ice crystals, the frozen pillar, the ruins (arch, broken column, column, drum), the elves' watchtower (`tower`) and the frost hollow's ice rock |
| `tests/` | `bg_test` (server + client), `bg_admin_test`, `bg_pvp_test` (server + two players), `camp_test`, `camp_reach_test`, `bg_boss_test` |
| `tools/` | `forest_shots` (screenshots), `bg_sound_probe` (what the raid sounds like) |

**A camp** is one row of `CAMPS`: its id, name, tier (1 to 3, 4 for a boss), centre and radius, region (its
dressing: `mush`, `elf`, `frost`, `ruins`, `barrow`, `forest`) and foes (kind, count, champion, offset). Camps.add
spawns them and the chest. To add a camp, add a row; a boss camp names its `boss` (a kind with a brain in `game/monsters/`).

Still borrowed from outside, to move with their owners:
- the other monsters (`game/systems/data/data.gd` `ENEMIES`, their brains in `enemy.gd`, bodies in `goblin.gd`): they go to
  `game/monsters/<name>/` like the bosses;
- the camp's models: `game/maps/camp/props/camp/` tent and runestone, `props/waypoint/` banner and crystal rune;
- the PvP checks in `battlegrounds.gd` (`pvp_pair`, statuses), which the Arena shares, go to `game/systems/` with the
  damage and effect system.
