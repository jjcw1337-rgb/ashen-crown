# Architecture cleanup

Agreed with Blaine on 2026-11-06. This is where the code is going and in what order. Update the status lines as
work lands; change the plan here first if it changes.

## Why

- Code is grouped by type (`scripts/`, `assets/`, `tools/`). One skill's pieces sit in up to 8 places.
- Shared code is named after whatever needed it first: `goblin.gd` builds every monster, `knight_mocap_rig.gd`
  every hero body, `lion.gd` the archer's wolf, `arrow_fx.gd` every burn.
- The same rule is written several times. A burn has four versions (monster, player, sandbox bot, the server's
  PvP check). Statuses exist once for players (`pvp_status.gd`) and again for monsters (`enemy.gd`).
- Clients send finished damage numbers (`sv_enemy_hit`, `sv_pvp_hit`), and the server accepts them.
- Skill data lives in three places: `data.gd`, `data/codex/`, and `code_base.json`.

## Target layout

```
heroes/<hero>/      body/ (model, rig, dyes), weapon/, skills/<skill>/ (code, effects, its own models),
                    companion/, shared/ (what only this hero's skills share), build/ (Blender and other build
                    scripts), tests/, tools/ (previews)
monsters/<monster>/ model, data, its brain if it has its own
maps/<map>/         verdant_reach/, arena/: the map code and its props (borrowed pieces move here)
items/              gems, consumables, shared rites
systems/            the shared rules: gameplay (stats, effects, statuses, hooks, damage), skills (cost,
                    cooldown, aim, delivery), fx/<fire|frost|lightning>/ (with their own textures and models),
                    bodies (rigs, animation), ai, world, net, loading, ui, audio
tools/              the pipeline (Meshy, Blender, audio), project-wide tests, CI. Never shipped.
```

Rules:
- Content (heroes, monsters, maps, items) uses systems. Systems never name a hero, monster or map.
- Where a piece goes depends on how many things use it:
  - one skill uses it: it goes in that skill's folder;
  - one hero's skills share it: it goes in that hero's `shared/`;
  - several heroes or monsters use it: it goes in `systems/`.
- Some things are already one central system: the codex data (`data/codex/`), the sound bank and the skill icons.
  They stay central for now. Each hero's `codex.json` may move into its folder later, with the loader and the
  editor finding `heroes/*/codex.json`. That needs no master file.
- `tests/`, `tools/` and `build/` inside a hero are excluded from exports (`export_presets.cfg`). `build/` has a
  `.gdignore`.
- King Grubb is kept as content (`monsters/king_grubb/`), not deleted with Act I. Everything else that's cut is
  deleted, because git keeps the history.

## The gameplay core (systems/gameplay, systems/skills)

Modelled on Unreal's Gameplay Ability System and Slay the Spire 2's hooks, built small:
1. **Stats** on every combatant. Heroes and monsters share one combatant component; today they share no base class.
2. **Effects** that change stats. An effect is instant (a hit), over time (a burn) or timed (+40% for 12 s), and
   has a stacking rule.
3. **Statuses and tags** such as burning, feared, frozen or Branded, which other rules check.
4. **Hooks** (on hit, on kill, on cast, when struck) that rites, gems and items subscribe to. These replace the 59
   procs that are now one `match` in `run_talents.gd`.
5. **Cues**, which draw the effects. Today's fx events already work this way.
6. **Delivery**: projectile, area, ground zone, channel/tether, stages, summon. These extend `SkillSpec` rather
   than replacing it.

Authority: **server-side by default** in the Battlegrounds, the Arena and the Sandbox. A client sends what it wants
to do and what it touched. The server checks that and computes the result from its own copy of the player's build.
This means the server owns the build (camp offers, picks, rites, gems).
- The core is plain data, with no nodes and no meshes, so the stripped server can run it cheaply.
- An effect lives where its target is simulated.
- Ship level A first: the server computes the results. Stay ready for level B, where the server also flies
  projectiles.

Every hit and effect goes to a **combat log**, which is used both for balance and as the proof described below.

## Order

1. **Folders.** Each hero's own code and models move into `heroes/<hero>/`. These are moves only, and play doesn't
   change. All heroes are done back to back, starting with the Archer. Shared files (the fire in `arrow_fx.gd`, the
   frost toolkit in `frost_volley_fx.gd`, `arc_fx.gd`) stay where they are until step 3 gives them a home.
2. **Reference recordings.** Before damage changes, record a fixed-seed, fixed-frame-rate fight for each hero
   (every skill on training dummies, plus one PvP pair through a real server) as a combat log. Every later step
   reproduces it or explains each difference.
3. **The new damage and effect system**, server-side from day one. Move one hero, then the rest. Nothing new is
   built on the old path.
4. **One data source.** The codex JSON is the only copy. The copies in `data.gd`, `run_talents.gd` and
   `talents.gd` go, and then so do `code_base.json` and the three-way merge.
5. **Real ids** (`pierce` → `fire_arrow`) everywhere at once, with aliases for saved survivors. Ids travel over the
   network, so the server deploy and the clients ship together.

Cuts run alongside: the old crypt, the old Warlock (the gnome body and the four-skill kit), Act II, Act I's story,
the coast, camp life, the Last Flame and the co-op server. For each old system: move what the live game still uses,
delete the rest, then test.

Touch points to coordinate:
- Claude-1's loader: its recorded file lists and the coming per-class lists, which become "load the hero's folder".
- The codex editor.
- Server deploys.
- Export filters.
- Saved survivors.

## Who does what (split by files, so nobody edits the same thing)

- **Claude-1: the world side.**
  - Tasks: the cuts (the old crypt, Act II, Act I's story, the coast, camp life, the Last Flame, the co-op server;
    King Grubb is kept) and the loading overhaul.
  - Owns: `world.gd`, `forest_camp.gd`, `bg_forest.gd`, `camps.gd`, `battlegrounds.gd`, `res_cache.gd`, the
    preload and warm-up lists, every zone builder, and the files of everything being cut.
- **Claude-2: the hero side.**
  - Tasks: every hero into its folder, the per-skill split (the Archer first, as the template), the shared effects
    into `systems/fx/`, one `codex.json` per hero, then the damage and effect system.
  - Owns: `heroes/**`, `systems/**`, `class_skills.gd`, `skill_fx.gd`, `skill_spec.gd`, `run_talents.gd`,
    `run_build.gd`, `codex.gd`, `data/codex/`, `tools/codex/`.
- **Shared big files** (`game.gd`, `ui.gd`, `hero.gd`, `net.gd`, `enemy.gd`): either of us may edit them.
  - Keep commits small, and pull before starting.
  - Before a large edit, add a line under "In progress" below and remove it when it lands.
- Anything not listed: ask Blaine or JJ before starting.

### In progress

- Claude-2: the Archer's per-skill split (`heroes/archer/**`, plus small hook changes in `hero.gd` and
  `class_skills.gd`).

## Cutting an old system: what the live game still borrows

Before deleting an old system, move what the live game still uses out of it. Known borrowings (2026-11-06; check
again with `git grep` before each cut):
- **The Verdant Reach** (`bg_forest.gd`) uses models from:
  - Act II: `models/roman/` arch, broken, column, drum (its ruins);
  - Grubb's fort: `models/fort/tower`;
  - the Sloths' lairs: `models/lairs/ice_rock`, plus the frost floor texture `SlothLair._ground_tex("cold")`;
  - the camp: `models/camp/` tent and runestone;
  - the waypoint: `models/waypoint/` banner and crystal_rune;
  - the old crypt's lower floors: `models/bg/` mushrooms, fungus, brambles, ice_crystals, frozen_pillar.

  These move to `maps/verdant_reach/props/`.
- **Monsters:** the forest camps use Act I monsters (zombies, the three Fallen, the Feral, the bear, the goblin
  guard).
  - All of them are built on `Goblin.imported_rig` (`goblin.gd`, King Grubb's file). It goes to `systems/bodies/`.
  - The Poison Mushroom loads through `BgFloors.prop` (the crypt's floors).
- **The archer's wolf** runs on `lion.gd` (the Act II arena lion's skeleton and pose).
- **Every camp chest** is built by `World._chest` (`world.gd`).
- **`World.crypt_shell`** is used by the Sandbox (`sandbox.gd`) and the Last Flame (`vigil.gd`) as well as the old
  crypt.
- **King Grubb is kept** as `monsters/king_grubb/`: his model, `hoard.gd` and his part of `goblin.gd`.

## Status

- [ ] 1. Folders: the Archer (`87bae1f`) and the Plague Doctor (`8550926`) are done. Next: the Wraith, Demon, Warlock,
  Doug, the dragons and the Knight. The Knight's body builder goes to `systems/bodies/`.
- [ ] 2. Reference recordings
- [ ] 3. Damage and effect system
- [ ] 4. One data source
- [ ] 5. Real ids
- [x] `concepts/` removed (2026-11-06)
