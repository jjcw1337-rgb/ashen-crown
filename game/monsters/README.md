# Monsters (game/monsters/<monster>/)

One folder per monster, holding everything that is only that monster's. Its stats and text stay in
`scripts/data.gd` `ENEMIES` under its kind, until the one data source (docs/architecture_cleanup.md, step 5).

| In the folder | What |
|---|---|
| its model (`<kind>.glb`) | the Meshy model (MeshyMonster.MODELS points at it) or its own body's files |
| `<monster>.gd` | its brain if it has its own: its rules, no drawing |
| `<monster>_fx.gd` | its look: what its fx events draw and play on every game |
| `tests/` | its own tests, if it has any |

Rules never draw: a brain sends `Enemy._fx(event)` before a move lands, and the `_fx` script draws it on every
player's game (the stripped server has no meshes).

**Bosses** extend `BossBrain` (`boss_brain.gd`, shared by every boss): they name their moves (seconds, impact,
pose), pick one, start it (cooldown and warning) and land it; the loop, targeting and move playback are shared.
`Enemy.setup` gives a kind its brain. A boss can stand in any camp: a camp row's `boss` is its kind
(game/maps/verdant_reach/verdant_reach.gd `CAMPS`).

| Monster | Kind | What |
|---|---|---|
| `hrimgar/` | `ice_troll` | Hrimgar the Frostbound: Glacial Slam, Frost Lances, Rime Roar, Avalanche |
| `mossbeard/` | `hermit`, `spore_shroom` | Old Mossbeard and his Poison Mushrooms: Spore Bolt, Sprouting, Thorn Snare, Spore Step, Bramble Burst |

Not moved yet (their brains are still in `scripts/enemy.gd`, their bodies in `goblin.gd`, `bear.gd`, `feral.gd`,
`sloth.gd`, `lion.gd`, `skeleton.gd`, their models in `assets/models/monsters/`): the rest of the Verdant Reach's
camps, King Grubb and his Gold Grabbers, the Hollow Sloths, the Arena's lion and gladiator.
