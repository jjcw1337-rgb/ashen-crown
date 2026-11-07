# Monsters (game/monsters/<monster>/)

One folder per monster, holding everything that is only that monster's. Its stats and text stay in
`game/systems/data/data.gd` `ENEMIES` under its kind, until the one data source (docs/architecture_cleanup.md, step 5).

| In the folder | What |
|---|---|
| its model (`<kind>.glb`) | the Meshy model (MeshyMonster.MODELS points at it) or its own body's files |
| `<monster>.gd` or `<monster>_brain.gd` | its brain if it has its own: its rules, no drawing (a boss's extends BossBrain; the others are static functions on the Enemy, called from Enemy._think_combat) |
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
| `hrimgar/` | `ice_troll` | Hrimgar the Frostbound (boss): Glacial Slam, Frost Lances, Rime Roar, Avalanche |
| `mossbeard/` | `hermit`, `spore_shroom` | Old Mossbeard (boss) and his Poison Mushrooms: Spore Bolt, Sprouting, Thorn Snare, Spore Step, Bramble Burst |
| `king_grubb/` | `goblin_king`, `grabber` | King Grubb the Gilded (boss) and his Gold Grabbers: his fight (`hoard.gd`: his gold is his life), the goblins' bodies (`goblin.gd`), his model, tests. His fight needs no vault: without tunnels his grabbers come from round him, so any camp can have him (`hoard_test`) |
| `bear/` | `bear` | The bear: its body (`bear.gd`, the Meshy bear on its own skeleton), brain (`bear_brain.gd`), model, tests |
| `feral/` | `feral` | The Feral: its body (`feral.gd`, five models), brain (`feral_brain.gd`: perched in trees, the pack's lunges), tests |
| `hollow_sloth/` | `sloth_fire`, `sloth_ice`, `sloth_storm` | The Hollow Sloths: body and brain (`hollow_sloth.gd`), three models, tests |
| `fallen/` | `fallen`, `fallen_skirmisher`, `fallen_reaver`, `fallen_stalker` | The Fallen: brains (`fallen_brain.gd`: the skirmisher's lunge, the reaver's cleave, the stalker's hook), four models, tests |
| `zombie/`, `treant/`, `dark_elf/`, `troll_shaman/`, `goblin_guard/`, `skeleton_archer/` | | The Verdant Reach's camp monsters: models |
| `bandit/`, `gladiator/`, `champion/` | | models |

Still to move:
- `goblin.gd`'s `imported_rig`, which every Meshy monster's body stands on: it goes to `game/systems/bodies/`;
- the lion (`lion.gd`, which the Archer's wolf also stands on: it goes to `game/systems/bodies/`);
- the dwarf, still in `assets/models/monsters/`.
