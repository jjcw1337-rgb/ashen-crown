# Monsters (game/monsters/<monster>/)

One folder per monster, holding everything that is only that monster's. Its stats and text stay in
`game/systems/data/data.gd` `ENEMIES` under its kind, until the one data source (docs/architecture_cleanup.md, step 5).

| In the folder | What |
|---|---|
| `monster.gd` | **its card** (every folder has one, like a hero's class script): the kinds it is, its Meshy models' rigs (`RIGS`), its personality, and any of its own hooks (below) |
| its models (`<mesh>.glb`) | the Meshy models (built on `MeshyRig` by `game/systems/bodies/meshy_monster.gd` from the card's `RIGS`), or its own body's files |
| `<monster>.gd`, `<monster>_brain.gd` | its own body and brain: its rules, no drawing (a boss's extends `BossBrain`; a family's brain is static functions on the Enemy) |
| `<monster>_fx.gd` | its look: what its fx events draw and play on every game |
| `sounds/` | the sounds only it makes (`tools/audio/build_sfx.py` finds every `game/**/sounds/`) |
| `tests/`, `tools/` | its own tests and tools |

**The registry** (`monsters.gd`, `Monsters`) lists the cards (`CARDS`) and names no monster. `Enemy`
(`scripts/enemy.gd`: life, statuses, movement, the shared melee and ranged fighting) asks it, it asks the kind's card,
and whatever the card leaves out is the shared way. What a card can declare (all but `KINDS` optional):

| On the card | What |
|---|---|
| `KINDS` | the `Data.ENEMIES` kinds it is |
| `RIGS` | its Meshy models' rigs by the def's `mesh` (`tools/blender/act1/layout_to_gd.py <folder> <mesh> layout.json` writes them) |
| `PERSONALITY` | its Anim personality (a name, or `{kind: name, "*": default}`; else `"warrior"`) |
| `MOVES` + `begin` / `during` / `impact` / `finish` | the special moves it plays itself |
| `FALL := "side"` or `fall(e, f, delta)` | how its body goes down |
| `build_rig` / `pose_rig` / `model_paths` | a body of its own (else its Meshy rig, a code-built skeleton or figure) |
| `brain(e)` | a boss's brain |
| `combat`, `idle` | its own fighting and its own idle |
| `on_setup`, `on_placed` | its own start: once its body is built, once it stands where it lives |
| `fx(e, ev) -> bool` | draws its own fx events |
| `rest_overlay`, `net_lift`, `heavy_steps` | its body's resting overlay, a client's height for it, a ground-shaking walk |

**Adding a monster:**
1. Make a folder with its models and a `monster.gd` card. Copy the plainest one (`zombie/monster.gd`) and add only the
   hooks it needs.
2. Add a line in `Monsters.CARDS`.
3. Give it a `Data.ENEMIES` entry (its stats, `look`, `mesh`, `ai`; the numbers move to the codex later).
4. Put it in a camp: a row of a map's `CAMPS`.
5. Run `game/monsters/tests/every_monster_test.gd` (through `tools/_late.gd`; it's in the gate). It spawns every carded
   kind in the Sandbox, which must build its body, animate, fight and die. The Sandbox panel can also spawn any monster
   ("Spawn").
6. Check it rigged and moving with `game/monsters/tools/monster_lineup.gd` (`-- out.png [kind ...]`, through
   `tools/_late.gd`). It shows idle, walk, run and attack frames on the game's own rig.

Rules never draw: a brain sends `Enemy._fx(event)` before a move lands, and the `_fx` script draws it on every
player's game (the stripped server has no meshes).

**Bosses** extend `BossBrain` (`boss_brain.gd`, shared by every boss): they name their moves (seconds, impact,
pose), pick one, start it (cooldown and warning) and land it; the loop, targeting and move playback are shared.
Its card's `brain(e)` gives a kind its brain. A boss can stand in any camp: a camp row's `boss` is its kind
(game/maps/verdant_reach/verdant_reach.gd `CAMPS`).

| Monster | Kind | What |
|---|---|---|
| `hrimgar/` | `ice_troll` | Hrimgar the Frostbound (boss): Glacial Slam, Frost Lances, Rime Roar, Avalanche |
| `mossbeard/` | `hermit`, `spore_shroom` | Old Mossbeard (boss) and his Poison Mushrooms: Spore Bolt, Sprouting, Thorn Snare, Spore Step, Bramble Burst |
| `king_grubb/` | `goblin_king`, `grabber` | King Grubb the Gilded (boss) and his Gold Grabbers: his fight (`hoard.gd`: his gold is his life), the goblins' bodies (`goblin.gd`, sculpted with `sculpt.gd`), his model, tests. His fight needs no vault: without tunnels his grabbers come from round him, so any camp can have him (`hoard_test`) |
| `bear/` | `bear` | The bear: its body (`bear.gd`, the Meshy bear on its own skeleton), brain (`bear_brain.gd`), model, tests |
| `feral/` | `feral` | The Feral: its body (`feral.gd`, five models), brain (`feral_brain.gd`: perched in trees, the pack's lunges), tests |
| `hollow_sloth/` | `sloth_fire`, `sloth_ice`, `sloth_storm` | The Hollow Sloths: body and brain (`hollow_sloth.gd`), three models, tests |
| `fallen/` | `fallen`, `fallen_skirmisher`, `fallen_reaver`, `fallen_stalker` | The Fallen: brains (`fallen_brain.gd`: the skirmisher's lunge, the reaver's cleave, the stalker's hook), four models, tests |
| `zombie/`, `treant/`, `dark_elf/`, `troll_shaman/`, `goblin_guard/`, `skeleton_archer/` | | The Verdant Reach's camp monsters: models |
| `lion/` | `lion` | The Arena's lion: its model (its body is the shared quadruped, `game/systems/bodies/lion.gd`) |
| `bandit/`, `gladiator/`, `champion/` | | models |
| `tools/` | | `monster_lineup.gd`: the contact sheet of every kind, rigged and moving |

| `spider/` | `spider` | The spider: code-built (Models.crawler), a card only |

`lion/`'s card also covers `spirit_beast`, the Archer's wolf on the same body; its model is the Archer's
(`assets/models/monsters/wolf.glb`, to move with the Archer's companion).
