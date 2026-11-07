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
game/                 everything that ships (Godot loads it as res://game/...)
  heroes/<hero>/      body/ (model, rig, dyes), weapon/, skills/<skill>/ (code, effects, its own models),
                      companion/, shared/ (what only this hero's skills share), build/ (Blender and other build
                      scripts), tests/, tools/ (previews)
  monsters/<monster>/ model, data, its brain if it has its own
  maps/<map>/         verdant_reach/, arena/: the map code and its props (borrowed pieces move here)
  items/              gems, consumables, shared rites
  ui/                 the screens: title/, class_picker/, lobby/, run/ (build window, offers, Codex), hud/;
                      ui.gd is split into these
  systems/            the shared rules: gameplay (stats, effects, statuses, hooks, damage), skills (cost,
                      cooldown, aim, delivery), fx/<fire|frost|lightning>/ (with their own textures and models),
                      bodies (rigs, animation), ai, world, net, loading, audio
tools/                the pipeline (Meshy, Blender, audio), project-wide tests, CI. Never shipped.
deploy/  docs/  addons/ (GodotSteam: Godot wants it at the root)  project.godot  main.tscn
```

Rules:
- Content (heroes, monsters, maps, items) uses systems. Systems never name a hero, monster or map.
- Where a piece goes depends on how many things use it:
  - one skill uses it: it goes in that skill's folder;
  - one hero's skills share it: it goes in that hero's `shared/`;
  - several heroes or monsters use it: it goes in `game/systems/`.
- Some things are already one central system: the codex data (`data/codex/`), the sound bank and the skill icons.
  They stay central for now. Each hero's `codex.json` may move into its folder later, with the loader and the
  editor finding `game/heroes/*/codex.json`. That needs no master file.
- `tests/`, `tools/` and `build/` inside a hero are excluded from exports (`export_presets.cfg`). `build/` has a
  `.gdignore`.
- Cuts keep the good things and drop the machinery (see "Cutting an old system").

## The gameplay core (game/systems/gameplay, game/systems/skills)

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

Each step is done for the Archer first, all the way through, and the other heroes copy it.

1. **Folders.** Each hero's own code and models move into `game/heroes/<hero>/`. These are moves only, and play doesn't
   change. Shared files (the fire in `arrow_fx.gd`, the frost toolkit in `frost_volley_fx.gd`, `arc_fx.gd`) stay where
   they are until step 2 gives them a home.
2. **The Archer, end to end: the template.** Every file the Archer touches is rebuilt until it follows every rule in
   `AGENTS.md` and the docs it points to:
   - one folder per skill, with its rules (`<skill>.gd`) and its look (`<skill>_fx.gd`); `archer.gd` keeps only the
     body and the routing;
   - every number a player sees comes from `data/codex/heroes/archer.json` (today Fire Arrow's ×1.3, `RANGE`,
     `VOLLEY_R` and the rest are constants in `archer.gd`);
   - the shared fire, frost and arc effects move to `game/systems/fx/`, so other heroes stop borrowing the Archer's
     files;
   - its crowd control is reviewed for PvP and sent through `PvpStatus`. Today Thunderstep's stun is PvE-only
     (`PvpStatus` keeps other classes' stuns off players until each is reviewed), and Frost Volley's chill reaches
     players through `send_pvp_effect`, with no diminishing returns;
   - the code outside its folder that names it (`hero.gd`, `ui.gd`, `run_talents.gd`, `enemy.gd`, `game.gd`…) shrinks
     to the registration list in `docs/content/heroes.md`;
   - one contract for a hero's skills, written in `docs/content/skills.md`. Today the Archer is static functions with
     its state on `Hero`, and the Plague Doctor an object per hero (`Hero.pd`).

   Play doesn't change except for those fixes. The proof: `game/heroes/archer/tests/archer_reference.gd` reproduces
   the recorded damage, burns, stuns and chills of every skill; its other tests and `tools/coop_fx_test.gd` pass;
   and its skills are checked from the game camera. The other heroes then follow its template.
3. **Reference recordings.** Before damage changes, record a fixed-seed, fixed-frame-rate fight for each hero
   (every skill on training dummies, plus one PvP pair through a real server) as a combat log. Every later step
   reproduces it or explains each difference.
4. **The new damage and effect system**, server-side from day one ([combat](systems/combat.md), "What's changing").
   Move the Archer, then the rest. Nothing new is built on the old path.
5. **One data source.** The codex JSON is the only copy. The copies in `data.gd`, `run_talents.gd` and
   `talents.gd` go, and then so do `code_base.json` and the three-way merge.
6. **Real ids** (`pierce` → `fire_arrow`) everywhere at once, with aliases for saved survivors. Ids travel over the
   network, so the server deploy and the clients ship together.

Cuts run alongside: the old crypt, the old Warlock (the gnome body and the four-skill kit), Act II, Act I's story
(the moor and the fort), the co-op server, plus archiving sailing and the Last Flame. The starting camp stays for
now. Follow "Cutting an old system".

Touch points to coordinate:
- Claude-1's loader: its recorded file lists and the coming per-class lists, which become "load the hero's folder".
- The codex editor.
- Server deploys.
- Export filters.
- Saved survivors.

## Who does what (split by files, so nobody edits the same thing)

- **Claude-1: the world side.**
  - Tasks: the cuts (the old crypt, Act II, Act I's story, the co-op server; archiving sailing and the Last Flame;
    see "Cutting an old system") and the loading overhaul.
  - Owns: `world.gd`, `game/maps/**`, `game/monsters/**`, `res_cache.gd`, the
    preload and warm-up lists, every zone builder, and the files of everything being cut.
- **Claude-2: the hero side.**
  - Tasks: every hero into its folder, the per-skill split (the Archer first, as the template), the shared effects
    into `game/systems/fx/`, one `codex.json` per hero, then the damage and effect system. The docs by concept
    (`AGENTS.md`, `docs/content/`, `docs/systems/`, `docs/pipeline/`).
  - Owns: `game/heroes/**`, `game/systems/**`, `class_skills.gd`, `skill_fx.gd`, `skill_spec.gd`, `run_talents.gd`,
    `run_build.gd`, `codex.gd`, `data/codex/`, `tools/codex/`.
- **Shared big files** (`game.gd`, `ui.gd`, `hero.gd`, `net.gd`, `enemy.gd`): either of us may edit them.
  - Keep commits small, and pull before starting.
  - Before a large edit, add a line under "In progress" below and remove it when it lands.
- Anything not listed: ask Blaine or JJ before starting.

### In progress

- Claude-2: the Archer, end to end (`game/heroes/archer/**`, `game/systems/**`, plus the Archer's places in `hero.gd`,
  `class_skills.gd`, `skill_fx.gd` and `run_talents.gd`).
- Claude-1: the monsters into `game/monsters/<name>/` (the Verdant Reach's first; King Grubb as a boss any camp can
  use), then the remaining cuts (Act II, the moor and fort, sailing and the Last Flame to `archive/`).

## Cutting an old system

Blaine, 2026-11-06: keep the good things we built, drop the old machinery. Every piece of an old system goes into one
of three buckets:
1. **Keep live, in `game/`.** These are the monsters and bosses, each a camp or boss for the Battlegrounds:
   - King Grubb with his gold-sack fight (`hoard.gd`, his part of `goblin.gd`, his model) and the Gold Grabbers;
   - the three Hollow Sloths;
   - the bear, the Feral, the three Fallen, the bandits, the gladiator, Aurelius and the lion.

   They go to `game/monsters/<name>/`. Anything the live game still uses (the list below) also stays live.
2. **Archive: good assets, not built.** Good models and textures that nothing uses yet go to `archive/`. That
   folder has a `.gdignore`, so Godot neither imports nor exports it, and it stays in the repo for a future map to
   pull back into `game/`. Examples are the fort (palisade, towers, gatehouse, great hall), the Roman/Aurelia set,
   the coast and islands, and the crypt props. Today every model in the project ships in the download whether it's
   used or not.
3. **Delete: the old machinery.** This covers the story-mode code (zone builders for the moor, fort and Aurelia),
   acts, and the co-op server with its party queue (Blaine: "we can get rid of that entirely"). Git keeps the
   history.

**Archived whole, code included** (Blaine, 2026-11-06):
- **The Last Flame**: `vigil.gd`, `flame_board.gd`, its sanctum, waves and leaderboard. It goes to
  `archive/last_flame/`.
- **Sailing** ("we don't want to lose the boat stuff"). That means the
ocean (`ocean.gd`: waves, shore and depth), the boats (`boat.gd`, `boat_ride.gd`, `boat_shop.gd`, `Data.BOATS`),
the coast and the five islands (`coast.gd`, `isles.gd`, `isle_*.gd`, `height_grid.gd`), Osric the shipwright, and
their models, textures and sounds. They go to `archive/sailing/`.

Each archived feature gets a short `REVIVE.md` listing the hooks it had in `game.gd`, `hero.gd`, `net.gd` and
`ui.gd`, so it can be wired back in. Other features to keep this way need an admin's say-so: add them here.

**Not cut yet: the starting camp** (Blaine: "we don't want to get rid of that quite yet"). That covers the camp and
the World-Tree Island, its people (traders, guards, the smith, ravens), day and night, the waypoint, quests and
Enter World. It stays live as it is until an admin decides.

Order for each old system:
1. Move what the live game borrows (below).
2. Move the monsters to `game/monsters/`.
3. Archive the good assets.
4. Delete the rest.
5. Run the tests for what's left.

Do one old system per push.

### What the live game still borrows

Known borrowings (2026-11-06; check again with `git grep` before each cut):
- **The Verdant Reach** (`game/maps/verdant_reach/`) uses models from:
  - Act II: `models/roman/` arch, broken, column, drum (its ruins);
  - Grubb's fort: `models/fort/tower`;
  - the Sloths' lairs: `models/lairs/ice_rock`, plus the frost floor texture `SlothLair._ground_tex("cold")`;
  - the camp: `models/camp/` tent and runestone;
  - the waypoint: `models/waypoint/` banner and crystal_rune;

  These move to `game/maps/verdant_reach/props/`.
- **Monsters:** the forest camps use Act I monsters (zombies, the three Fallen, the Feral, the bear, the goblin
  guard).
  - All of them are built on `Goblin.imported_rig` (`goblin.gd`, King Grubb's file). It goes to `game/systems/bodies/`.
  - The Poison Mushroom's body is the forest's `props/fungus` (`Enemy`, its `"prop"`).
- **The archer's wolf** runs on `lion.gd` (the Act II arena lion's skeleton and pose).
- **Every camp chest** is built by `World._chest` (`world.gd`).
- **`World.crypt_shell`** and its pillar, bones and sconce (`ArenaProps`) are used by Act III's crypt.

## Status

- [ ] 1. Folders: the Archer (`87bae1f`) and the Plague Doctor (`8550926`) are done. Next: the Wraith, Demon, Warlock,
  Doug, the dragons and the Knight. The Knight's body builder goes to `game/systems/bodies/`.
- [ ] 2. The Archer, end to end. Done: the reference recording; `game/systems/skills/` (`Skill`, `Missile`,
  `GroundZone`, `DelayedArea`); all eleven of his skills in their own folders with their numbers in the codex,
  Thunderstep's stun 3 s and on players too (Blaine, 2026-11-07); Hunter's Mark no longer named in `enemy.gd`; his
  body and bow in `body/`, his arrow models in `weapon/`; `hero.gd`, `ui.gd` and `run_talents.gd` reach him through
  `ClassSkills`' optional hooks (`archer.gd`: 957 lines to about 190). The shared lightning is
  `game/systems/fx/lightning/` (ArcFx) and the frost toolkit `game/systems/fx/frost/` (FrostFx), with Frost Volley's
  own look in his folder. The body fire every burn shows and the simulated-flame
  building blocks are `game/systems/fx/fire/flame_fx.gd` (FlameFx), the game clock `game/systems/game_clock.gd`, and
  his arrows' look `shared/arrow_fx.gd`. Left: the burn's look chosen by class in `RunTalents` and `Enemy.ignite` (with
  the statuses work); joining FlameFx and the older FireFx (torches, campfires).
- [ ] 3. Reference recordings
- [ ] 4. Damage and effect system
- [ ] 5. One data source
- [ ] 6. Real ids
- [x] `concepts/` removed (2026-11-06)
- [x] Docs by concept: one root `AGENTS.md`, and a doc per piece of content, system and pipeline (2026-11-06)
- [x] The old crypt Battlegrounds cut (its map, floors below, antechamber gates, bells, stash daises and the stash's
  slow); its models in `archive/hollow_crypt/`. The old raid page, server screen, raids on the clock and the
  waypoint's walk down go too: the lobby browser is the only way in (2026-11-06).
- [ ] Monsters into `game/monsters/<monster>/`: done: Hrimgar and Old Mossbeard (on a shared `BossBrain`).
- [x] The Last Flame archived whole: `archive/last_flame/` with its REVIVE.md (2026-11-06).
- [x] Maps: the starting camp is `game/maps/camp/` (its builder, people, island, waypoint, models, tests; 2026-11-06).
- [x] Maps: the Verdant Reach is `game/maps/verdant_reach/` (its builder, camps, life, the Battlegrounds' rules,
  the bosses' brains, props, tests; 2026-11-06).
- [x] Maps: the Arena is `game/maps/arena/` (the template for every map: its map, props, modes, tests, README;
  2026-11-06).
