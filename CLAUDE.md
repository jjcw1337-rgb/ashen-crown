# Ashen Crown: notes for Claude (and humans)

A Diablo II-style isometric ARPG in **Godot 4.4.1** (GDScript, Forward+ with an OpenGL fallback).
Everything is procedural (models, textures, sound, music) except a few asset files: the intro video
`assets/intro.ogv`, the Act I boss King Grubb `assets/models/grubb_mutant.glb` and the gnome Warlock
`assets/models/gnome_warlock.glb`, and the knight's two bodies `knight_meshy.glb` / `knight_armored.glb` (all generated
with Meshy and rigged in Blender; see "Blender assets"). Two developers (one Windows, one Linux) push to `main`; GitHub
Actions exports Web + Windows + Linux + Mac and publishes them to GitHub Pages.

- Repo: https://github.com/jjcw1337-rgb/ashen-crown
- Live test build + downloads: https://jjcw1337-rgb.github.io/ashen-crown/
- Human setup and workflow: `CONTRIBUTING.md`. Player docs: `README.md`.

**Default patterns (every agent, read these first; `AGENTS.md` is the shared entry point for Codex/ChatGPT):**
[loading](docs/patterns/loading.md) · [servers](docs/patterns/servers.md) ·
[multiplayer](docs/patterns/multiplayer.md) · [effects](docs/patterns/effects.md) ·
[measuring](docs/patterns/measuring.md) · [code organization](docs/patterns/code-organization.md).
When you change one of these patterns, update its file in the same commit.
Shared performance work: [coverage and rollout status](docs/perf/COVERAGE.md);
[installed nightly audit](docs/perf/NIGHTLY_AUDIT.md). Preparation and verification are separate: check the status before calling it shipped.

## Getting the tools (Linux)

Godot 4.4.1 **standard** (not .NET) must be on PATH (upgraded from 4.3 on 2026-11-05: every script and
resource now has a `.uid` file beside it; commit them) as `godot`:
```
wget https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip
unzip Godot_v4.4.1-stable_linux.x86_64.zip && sudo mv Godot_v4.4.1-stable_linux.x86_64 /usr/local/bin/godot
```
**Blender 4.5 LTS** (for models and rigs, see "Blender assets"): `bash tools/blender/setup_blender.sh` installs it
to `/opt` and links `blender` (checksum-verified). Claude's cloud workspace resets, so run it again in a new session;
it needs network access to `download.blender.org`. Run scripts headless: `blender -b --python script.py -- args`
(renders with Eevee work under `xvfb-run -a`). Export `.glb` into `assets/models/`, never `.blend`.

**Meshy** (AI image/text to 3D, paid plan): `python3 tools/meshy/meshy.py text|image|get|check ...` saves a `.glb` plus a
thumbnail. Key from `$MESHY_API_KEY` or `~/.config/meshy/key` (never in the repo); needs `api.meshy.ai` and
`assets.meshy.ai` reachable. Each generation costs credits; results expire on Meshy after 3 days. Clean up, rig and
export with Blender, the way King Grubb was made.

Exporting locally also needs the 4.4.1 export templates (Editor → Manage Export Templates), but
you normally don't export locally: pushing to `main` does it in CI.

## Commands

```
godot --headless --editor --quit                  # import / rebuild the class cache (run after adding a class_name)
godot --path .                                    # play
godot --headless --path . -s tools/playtest.gd    # main gameplay smoke test
```
Headless tests in `tools/` (each prints `[X] ...` lines; look for SCRIPT ERROR / Parse Error):
`playtest`, `unlock_test`, `test_panel_test`, `wraith_test`, `demon_test`, `warlock_test`, `a2_test`, `a3_test`, `run_switch_test`, `drag_test`,
`det_test`, `woodcut_test` (`--fixed-fps 60`), `temper_test`, `woodcut_mp_test` (host + join), `grass_test`, `collision_test`, `aim_test`, `plague_test` (`--fixed-fps 60`), `hoard_test`, `coop_fx_test` (every skill's effects reach a puppet, in one process), `potion_test`, `fort_test`, `sound_test`, `char_test`, `flower_test`, `feral_test`, `talent_test`, `title_test`, `a2_arena_test`, `sloth_test` (the Hollow Sloths roam, notice, hunt, use their three skills, flee, give up, drop a unique), `vendor_test` (the camp's traders, the trade window, walking off closes it), `ui_click_test` (no click on a window, menu, globe or the corner map walks the hero; a control that rebuilds itself on click must `accept_event()` first, or the click leaks through), `camp_life_test` (the traders' moves and talk, the smith on the anvil, the ravens, the smoke, the World-Tree Island and its orbit camera; `--fixed-fps 60`), `bg_test` (the Battlegrounds: a server and a client, `-- --server --port 24611 --raid-fast server` and `-- client 24611`), `bg_pvp_test` (a server and two players, `a` and `b`), `plague_pvp_test` (the same three, `-- a N` / `-- b N`: the Plague Doctor's statuses on another player), `controls_test` (WASD, the left click, the dodge roll, every class), `nightly_net_drop_test` (a client's link closing while a zone loads: no RPC after it), and the co-op pairs `mp_test`, `mp_boss_test` and `plague_mp_test` (run one copy
with `-- host` and one with `-- join`; `mp_boss_test` plays King Grubb's fight with the joining player).
Tool scripts save to `user://ashen_crown_test_save.json`, never the player's save.
Balance: `tools/balance.sh` runs `tools/balance_sim.gd` (bots play every class through Act I, A2 and A3) and flags numbers
outside their target bands. See `BALANCE.md` for the protocol.
Screenshots need a display: `xvfb-run -a godot --rendering-driver opengl3 --path . -- --shot out.png --zone town`
(other flags in `game.gd` `_ready`: `--zone town|wild|lair`, `--run 0|1|2`, `--class knight|wraith|demon|warlock`, `--god`, `--fight`).
The moor's road is `World.road_style()`: the paved Old Kingsroad (2) by default; `--road 0|1|3` shows the old broad
road, the wagon trail and the moor trails for comparison. `tools/zone_overview.gd -- out.png [--road N]` renders a high view of it.

Run the relevant tests before pushing. A push to `main` publishes to everyone in ~5 minutes. **Blaine and jj are equal
Game Factory admins (updated 2026-10-31): either admin's explicit main/production request is sufficient approval**;
do not wait for the other admin or a second confirmation at the Mac. Synchronize upstream and preserve others' commits
before deploying. For a requested preview or an otherwise unspecified "push it", use a `test-*` branch
(`git push origin HEAD:test-something`, or `test-all` for the shared preview) and give the preview build's link.
Either admin may also request configured asset services, including Meshy and ElevenLabs, within live existing plan
credits and API-key limits without a separate Blaine-only approval. New purchases need an explicit spending request.

## Code map (`scripts/`)

| File | Role |
|---|---|
| `game.gd` | Root node: boot, intro, zones/travel, camera, graphics presets, settings, save/load, acts and difficulty runs (`difficulty` 0/1/2 = Act I/A2/A3), input |
| `data.gd` | **Tuning**: classes (`CLASSES`), skills per class (`SKILLS`, `skills_for`), monsters, items, uniques, acts, vendors |
| `talents.gd` | Talent trees (`Talents.TREES`: three per class), row rules, the auto build for old saves (`AUTO`) |
| `world.gd` | Zone builder: terrain, roads, buildings, trees/grass (MultiMesh chunks), spawns, `burn_points` |
| `hero.gd`, `knight.gd`, `knight_rig.gd`, `anim.gd` | Player: class (`cls`, `set_class`), stats (`recalc`), combat, the shared skill flow (mana, cooldowns, cancel, animation), gear visuals, animation, co-op puppet mode |
| `class_skills.gd`, `knight_skills.gd`, `warlock_skills.gd`, `plague_skills.gd` | Every class's skills, one script per class (`ClassSkills.of(cls)`: KnightSkills, WraithSkills, DemonSkills, WarlockSkills, Archer, PlagueSkills); `hero.gd` hands each cast, impact frame, frame update, root check, clear, death and cast sound to it. Template for a new class: `tools/templates/new_class_skills.gd` |
| `wraith.gd`, `wraith_skills.gd`, `wraith_fx.gd` | Wraith class: the Meshy body on the mocap system with the spectral shader; its six skills (casts, blows, the tether, phantoms, the night); their effects (his own particles and rings: `WraithFx._spirit_burst` streaking wisps / shadow smoke, `_soul_ring` soul-mist; never the generic `Fx.burst`/`ring`) |
| `demon.gd`, `demon_mocap_rig.gd`, `demon_skills.gd`, `demon_fx.gd`, `demon_fists_fx.gd`, `demon_charge_fx.gd`, `demon_fault_fx.gd`, `demon_hurl_fx.gd`, `demon_chain_fx.gd`, `demon_crucible_fx.gd`, `demon_kit_fx.gd`, `brand_fx.gd`, `infernal_fx.gd` | Demon class: the Meshy magma brute on the mocap system with the magma shader and his own wing/tail/cloth rig (falls back to the knight body in obsidian plate + horns/wings/tail/spikes with the solid ember-edge shader); his six skills, one job each (the fists, the charge, the fault, the boulder, the chain, the Crucible) and the Brand; each skill's look in its own script |
| `pvp_status.gd` | Crowd control between players in the Battlegrounds (through the server, with diminishing returns) |
| `warlock.gd`, `warlock_fx.gd` | Warlock class: the gnome (`Warlock.GNOME`: imported model on `Goblin.imported_rig`, A-pose arms aimed down, swaying hat and beard, fel flame, floating grimoire; falls back to the robed knight body without the glb); skill effects incl. the Drain Life beam (`WarlockFx.Beam`, an ImmediateMesh ribbon redrawn each frame) |
| `plague.gd`, `plague_*_fx.gd`, `plague_fever.gd`, `pvp_status.gd`, `pvp_status_fx.gd`, `pvp_objects.gd` | Plague Doctor class: body (mocap, whole-body skill clips), his six skills (Pestilence Vial, Swarmcraft, Corpse Bloom, Fog of the Forgotten, Transfusion, The Last Experiment), poison, Blight and Fever, co-op replay; each skill's look in its own `plague_<skill>_fx.gd`; `PvpStatus` = statuses one player puts on another (slow, snare, harried, reveal, blight), `PvpStatusFx` how they look on the player; `PvpObjects` = a player's things other players can break (his bloom, vat, creature) |
| `dragon.gd`, `dragon_skills.gd` | The three dragon classes (`wyrm` Obsidian Wyrm, `serpent` Frost Serpent, `wyvern` Storm Wyvern): Meshy bodies posed in code every frame (`Dragon.pose`, handed over by `Anim.pose`); `DragonSkills`: the Storm Wyvern's Storm Arc (`storm_arc`: chain lightning from its jaws through `SharedSkills.chain`, the look `ArcFx.play_dragon`) and their attack sounds |
| `dodge.gd` | The dodge roll on Space (every class): direction, distance, i-frames, stamina, the tumble, the co-op event |
| `enemy.gd`, `projectile.gd`, `feral.gd` | Monsters/AI and missiles (host-authoritative in co-op); the Feral's baked-animation body |
| `via.gd`, `aurelia.gd`, `games.gd`, `roman.gd` | A2: the Imperial Road (wild), the city of Aurelia and its arena (lair), the arena's games (the act's boss fight), and the Roman architecture they're built from |
| `lion.gd` | The arena lion: a Meshy model on a quadruped skeleton, posed in code (no baked animations) |
| `sloth.gd` | The Hollow Sloth (Act I): three giants roaming the moor; its brain (`Sloth.new(enemy)`) and its code-posed body |
| `fort.gd` | Grubb's fort (the lair in Act I; A3 keeps the crypt): the muddy approach with the guards fighting the dead, the palisade ring, gatehouse and watchtowers (Meshy props in `assets/models/fort/`), the lived-in camp scattered round Grubb's open courtyard, and the moor's goblin trail end (`Fort.trail_end`) |
| `meshy_monster.gd` | Act I monsters from Meshy (`MeshyMonster.MODELS`, zombie/fallen/archer/goblin_guard): built on `Goblin.imported_rig` with grips and weapons; `Data.ENEMIES` `"mesh"` picks them |
| `hoard.gd` | King Grubb's fight (Act I boss): Gilded Bombs, the three burst sacks, the gold scramble (piles reaching him heal him; piles a hero takes hurt him) |
| `goblin.gd`, `sculpt.gd` | Goblin models: King Grubb is the imported mutant (`Goblin.MUTANT`: joint layout + glb, skinned onto the game's skeleton); the Gold Grabbers (and Grubb's fallback) are code-sculpted (`Sculpt` melts SDF shapes into one skinned mesh). `Goblin.after_pose` adds ears, jaw, crown wobble, belly jiggle, sacks and the goblin gaits |
| `ground_item.gd`, `inter.gd` | Loot on the ground; interactables (chests, shrines, waypoints, portals, NPCs) |
| `harvest.gd`, `wood.gd` | Woodcutting: Act I's harvestable trees (`Harvest`, `Harvest.HTree`), chopping, felling, stumps, respawns; wood made in code (logs, end grain, notches, chips and debris) |
| `furnace.gd`, `furnace_ui.gd` | Halvar's furnace in the Act I camp: the heat model and weapon tempering (`Furnace`); its window (`FurnaceUI`) |
| `items.gd` | Item rolls, `empower` (A2/A3 multipliers), enchanting, tooltips |
| `net.gd` | LAN co-op over ENet (UDP 24567, discovery 24568); RPC layer; `server` = a dedicated host with no player (Battlegrounds) |
| `coop_server.gd` | Online co-op: the story game hosted by a dedicated server (see "Online co-op") |
| `build_env.gd`, `nakama_client.gd`, `cloud_saves.gd` | Which backend a build uses; the Nakama REST client; characters kept in Nakama (see "Staging and accounts") |
| `battlegrounds.gd` | Battlegrounds prototype: the raid map, the dedicated server's raid logic (respawns, carried loot, extraction, the stash), the client's id and cached stash |
| `vigil.gd`, `flame_board.gd` | The Last Flame (zone `"vigil"`): the endless co-op horde defence under the Act I camp, its sanctum, waves, flame and HUD; its leaderboard (see "The Last Flame") |
| `content_catalog.gd`, `res_cache.gd` | Shared asset declarations, background loading and owner scopes; reuse through Game preparation and release when the owner leaves |
| `surface_materials.gd` | Surface overrides with safe instance retirement while shared meshes stay cached |
| `kpi.gd` | The official performance KPIs: scripted scenarios measured frame by frame (`--kpi`), see docs/nightly/KPIS.md |
| `shared_skills.gd`, `shared_fx.gd`, `elemental_fx.gd` | The shared skills every class can use (`"cls": "any"`): their gameplay and their effects (`ElementalFx`: Earthshatter's crack and rock spikes, Frost Nova's frost and ice crystals, War Cry's sigil and dust wave); Arc's lightning is `arc_fx.gd` `ArcFx` (jj's redo: Blender-rendered branching bolts, `tools/blender/fx/lightning_bolts.py` -> `tools/fx_bolt_atlas.py` -> `assets/textures/fx/storm/bolts.png`, stretched between the leaps with a blurred-mip halo; the Meshy plasma charge and Lichtenberg burn `lightning_scorch`; sounds `arc_zap`, `arc_hit`) |
| `skill_spec.gd` | The skill format (`SkillSpec`): a skill's timing, damage, area and damage over time read from its `Data.SKILLS` entry |
| `skill_fx.gd`, `knight_fx.gd`, `archer_fx.gd` | Co-op skill effects: `SkillFx` plays every class's skill events on the caster and on his puppet for partners (see "Co-op skill effects"); the knight's and archer's effect handlers (the Wraith's, Demon's and Warlock's are in their `*_fx.gd`) |
| `holy_fx.gd` | The knight's visual language (`HolyFx`, like `InfernalFx` for the Demon): the seal drawn on the ground, holy fire rings, the light column, the shockwave ripple, sunbursts and motes; Holy Nova, Battle Cry and Charge are built from it |
| `ui.gd`, `hud_bar.gd`, `icon_renderer.gd` | All UI built in code |
| `vendor_ui.gd` | Nameplates over the town's people and the trader's live portrait in the trade window |
| `models.gd`, `skeleton.gd`, `flora.gd`, `props.gd`, `geo.gd`, `mats.gd` | Procedural meshes and shaders |
| `grass.gd`, `grass_field.gd` | Act I's living 3D grass: species, biomes, placement and shader (`Grass`); the touch field and the wind (`GrassField`, a node of Game) |
| `fire_fx.gd` | Every fire in the game: simulated-fire flipbooks on layered particles, a preset per kind (see "Fire") |
| `weather.gd`, `fx.gd`, `sfx.gd`, `sfx_bank.gd` | Snow/ash, particles, audio (autoload `Sfx`: recorded/generated sounds from `assets/audio/sfx/` listed in the generated `sfx_bank.gd`, with the old synthesized sounds as fallback) |

## Rules and gotchas

- **Collision**: solid things are footprints (circles and rotated boxes) in `World.obstacles`. Props declare their own
  (`Props.footprint(root, radius_or_half)`) and are registered with `world.solid(node)` after placing (it reads the node's
  position, yaw and scale). Use `add_circle`/`add_box` only for things with no prop node. Movers call `world.move(pos, d, radius)`,
  which slides against the exact footprints; `blocked` (a padded 1 m grid) is only for A* and spawn spots.
- **Controls** (Path of Exile 2 style, every class; `tools/controls_test.gd`): WASD moves (`Game.wasd_dir`), left
  click attacks toward the pointer where he stands (or as the keys carry him; a foe clicked while standing still is
  walked up to and struck; items, chests and NPCs are still walked to), right mouse is a skill (a new character's
  first class skill; old saves' Block there becomes it, `binds_v`), and **Space is the dodge roll** (`scripts/dodge.gd`
  `Dodge`: the way the keys point, else toward the pointer; `DIST` 3.8 m in `DUR` 0.5 s; blows miss for the first
  `IFRAME` s, PvP included; it drops a swing not yet landed and a channel; costs `STAMINA`; holding Space on after
  it sprints, as Shift does). Partners see it through the `"roll"` fx event (`SkillFx.play` hands it to `Dodge.fx`;
  `Dodge.pose` tumbles the body, the Wraith swoops low). The pause menu's Controls button brings back
  click-to-move (`Game.click_move`, saved in settings).
- **Aiming** (Path of Exile style): **the mouse pointer is the source of truth; WASD only moves.** `Game` writes the
  pointer's point (the enemy under it, else the ground) to `Hero.cursor` every frame, and every action aims from it:
  the left click's attack (`Game._attack_aim`), the skill keys (`Game.cast_skill` → `Hero.skill_aim`) and mouse binds. Every skill in
  `Data.SKILLS` has `"aim"`: `"point"` (lands on the pointer; the skill clamps to its own range), `"facing"` (the old
  name, now meaning *directional*: from the hero toward the pointer, out to its `"range"`; the pointer itself when it's
  nearer, so a beam or tether latches on what's under it) or `"self"` (centred on him, no turn). Only short melee
  skills (range < `Hero.MELEE_RANGE` 5 m) and Space get help: a foe within `AIM_CONE_MELEE` (20°) of the pointer's
  line (`Hero._assist_pick`); ranged directional skills go exactly where the pointer says. Setting `atk_aim` also fixes
  `Hero.atk_dir` (`aim_dir()`), the direction at the moment of aiming: **skill code reads `aim_dir()` for "ahead",
  never the rig's facing** (`facing()` is the body, for blocking's "from the front" and effects), so a blow, arrow or
  lunge keeps the pointer's line while he walks on or turns. The body only shows the aim: snapped to it as an action
  starts, held on `atk_dir` while he moves mid-action, turned to the pointer while blocking, and to his walk
  otherwise. WASD's heading eases at `TURN_RATE` (28 rad/s) from the keys themselves. Skills that root him (the
  Demon's charge, slam, throw, grip, wrath) still do. `tools/aim_test.gd` (`--fixed-fps 60`). Give a new skill an `aim`.
- **Runs** (Act I, A2, A3) are `Data.RUNS` multipliers (`Game.run_mult`). `Items.empower` scales only flat stats; percentages
  (`Items.PCT_STATS`) stay as rolled. Re-run the balance sim after changing any of them.

- **Typed GDScript**: inference from Variant is treated as an error. Write `var x: Type = ...`.
- **Multiplayer development** (Blaine, 2026-11-05): do not require identical build SHAs for lobby admission. Cosmetic/client updates may connect to existing workers. RPC ids still depend on each script's RPC set: test network changes against deployed workers and update worker/co-op binaries when needed. Keep Nakama authentication, admission tickets and item consent. See `docs/multiplayer_lobbies.md`.
- **Co-op skill effects** (`scripts/skill_fx.gd` `SkillFx`): partners see a hero as a puppet (`Hero.puppet`, posed
  from `net_st`/`net_pos`/`net_yaw`), so his animation plays for them, but what a skill DRAWS has to be told: every
  skill effect is an event. Skill code never draws; wherever something is to be seen it calls
  `Hero.fx(skill_id, event, data)` (e.g. `fx("grasp", "impact", {"p": at, "x": hold})`), which plays the event at once
  on the local hero (`SkillFx.play`) and, in co-op, sends it with one RPC (`Net.pl_fx`, reliable) to every partner,
  whose game plays the same event on the caster's puppet. `Hero.use_skill` sends `(id, "cast", {"p": aim})` for
  every skill by itself, so a new class's casts reach partners before it has any effects of its own (an event no
  class claims gets `SkillFx._default`: a puff and a burst in the hero's colour). The event is a small Dictionary:
  `"s"` the skill id (`"attack"` for the weapon), `"e"` the event name, and what it needs: `"p"`/`"q"` points,
  `"d"` a direction, `"y"` a yaw, `"x"`/`"r"`/`"n"` numbers, `"ps"` a PackedVector3Array, `"t"` the enemies it
  touches (Enemy nodes; on the wire their net ids, `SkillFx.encode`/`decode`, so a partner finds the same
  monsters). `SkillFx.play` dispatches on the skill's class (`Data.SKILLS` `cls`) to `KnightFx` / `WraithFx` /
  `DemonFx` / `WarlockFx` / `ArcherFx` `play(h, ev) -> bool`. A handler draws only: it must not touch life, mana,
  cooldowns, stuns or talents (a puppet has none; send what the effect needs in the event), and it uses
  `SkillFx.snd` (flat for the caster, positional from the puppet), `SkillFx.shake`/`hitstop`/`duck` (the caster's
  screen only). Nothing is sent per frame: effects that run on (the Siphon tether, Drain Life's beams, Eternal Night,
  phantoms, arrows, bolts, snares, summoned demons and the wolf) are state in `Hero.fxs` (or the hero's own lists)
  started and ended by events and moved every frame by `SkillFx.update(h, delta)` after the pose, on the local hero
  and on the puppet alike; a partner's copy ends itself if the end is lost (the tether after its hold + 2 s, the
  beams 1.5 s after the last tick, the night 1 s after its clip stops). Drain Life's `"tick"` goes out every 0.3 s
  and `"victims"` only when the fork set changes. A summoned demon, the wolf and the Spirit Beast's commands run
  their own AI on every game (positions aren't streamed; they follow the same master and the same monsters) and
  only the master's own copy deals damage (`DemonMinion._strike`, `SpiritBeast._strike`, `Archer.update` check
  `master.puppet`). Screen-wide things stay the caster's own: the Underworld grade, and Eternal Night's edge
  darkening (a partner standing in a Wraith's night gets a fainter one, `WraithFx.NIGHT_PARTNER`). On a zone change
  `Hero.net_zone_reset` drops a puppet's lingering effects. `tools/coop_fx_test.gd` casts every skill of every class
  in `Data.SKILLS` beside a puppet and fails if a skill sends no event, the puppet shows nothing, a lingering effect
  doesn't reach it, or replaying the events on the puppet hurts a monster or changes its life or mana; the
  `mp_test` host+join pair counts the events each side receives from the other ("[H8]"/"[C7]").
- **Battlegrounds** (`scripts/battlegrounds.gd`, `Battlegrounds`): **the Hollow Crypt**, a hardcore extraction raid in
  the Dark and Darker mould on a **dedicated server** (`godot --headless --path . -- --server [--port N]`, staging systemd
  `ashen-crown-bg`, UDP 24567; `Net.server`). The map (`Battlegrounds.build`, zone `"bg"`, indoor, dark: a smaller
  hero light) is a 4x4 grid of rooms round a great central hall: corner rooms are where players arrive, one middle
  room per side holds a candidate Extraction Portal (Inter `"extract"`, hidden until open), the other is a treasure
  room and the only way into the hall from that side; a ring of corridors with one link missing; crypt rooms with
  sarcophagi, chests, few but tough monsters (`MON_LIFE`, `MON_DMG`, level `MON_LEVEL`); the hall has a pillar ring,
  three chests and a champion with bowmen. The walls come from `World.crypt_shell` (shared with the crypt). **The
  Ossuary's look** (floor 1; the floors below keep their own, see below; `scripts/crypt_props.gd` `CryptProps`): Meshy props re-baked onto clean UVs by
  `tools/blender/battlegrounds/rebake_crypt_prop.py` into `assets/models/crypt/` (sarcophagus, pillar, archway, bones,
  sconce, brazier, ossuary niche, the iron-bound chest, a row of candles; `prep_all.sh` rebuilds them from the raw
  Meshy downloads, `--solid` for props Meshy made of single sheets; `cut_flames.py` cut the candles' modelled flames
  and wrote their wicks, `CryptProps.CANDLE_WICKS`; `inspect_glb.py`, `components.py` to look at a raw model). World's shared crypt helpers (`_pillar`, `_sarcophagus`, `_bones`,
  `_wall_torch`) draw them when the files are there (A3's crypt too) with the same footprints and the same rolls on
  `rng`; in the Hollow Crypt (`theme.name == "bg"`) `crypt_shell` hands its wall blocks to `CryptProps.walls`, which
  turns cells into tomb alcoves with sarcophagi (each room's north wall), ossuary niches (candles in some), the hall's
  three statue alcoves (the knight statue in crypt stone) and wall braziers, closing the rock behind them; the walls
  (`CryptProps.wall_meshes`) and the flagstone floor (`CryptProps.lay_floor`, quads over the floor cells) use
  Meshy-drawn textures made tileable and normal-mapped in Blender (`make_tile_textures.py`, `assets/textures/crypt/`),
  both cut into `TILE` (12 m) meshes, since the OpenGL renderer lights a mesh by at most eight lights; `_chest` is the
  Meshy chest (`CryptProps.chest`, on the old chest's footprint node, a faint warm glint over it) and floor `_candles`
  the Meshy candles burning FireFx candle flames (the same rolls as before); the wall torches light a warm pool to the
  floor (`CryptProps.torch_light`, `TORCH_ENERGY`/`TORCH_RANGE`) and every other hall pillar carries one
  (`hall_torches`); the tall Meshy pieces (pillars, sarcophagi, archways) are redrawn by `CryptProps.see_through`
  (`SEE_SHADER`: their own textures plus the near-player see-through, so a pillar never hides the hero); the
  Extraction Portals stand in rune archways whose painted runes light when the portal opens
  (`Battlegrounds.sync_gates`, `CryptProps.set_runes`) with `portal_glow` inside; `dress` adds rubble, corner cobwebs,
  lit dust drifting in every room (`dust`), black beyond the rock (`void_frame`; the terrain ran on past the map's
  edge) and the hall's floor seal (a quad with `SEAL_SHADER`: its runes breathe and a wave of light runs out from the
  skull; not a Decal, which OpenGL can't draw); the dead kings in the hall's statue alcoves stand in a cold light. **Everything visual
  is on the same layout**: no footprint changes, no new interactable, no call added to `w.rng`
  (`tools/bg_layout_fingerprint.gd` prints a hash of the layout; a visual change must leave it as it was: the server
  builds the map from the same rolls). Stills: `tools/crypt_shots.gd -- outdir [quality N] [only a,b]`, a walk: `tools/crypt_clip.gd -- outdir [frames]`
  (`--fixed-fps 30`; it holds WASD keys, since the game reads the keys every frame). **Rounds**
  of `RAID_SECS` (20 min): two of the four portals open at `PORTALS_AT` (5 min), joining closes at `JOIN_CLOSE` (15 min), the
  crypt collapses at the end (everyone inside dies) and the dungeon resets (`new_round`). **Several raids** (Blaine
  2026-11-01): one server per raid, `--server --raid N` (port `RAID_PORTS[N]`), each running its rounds on the wall
  clock a third of a `PERIOD` after the last (`phase`), so one is always open; clients need no lobby: `schedule()` and
  `best_raid()` work every raid's state out from the clock (the Battlegrounds page's board, and Enter goes to the best
  one). `LIVE_RAIDS` is how many are deployed (staging: 1 until UDP 24571/24572 are open and the droplet has room;
  `BG_RAIDS=3 sh deploy/staging/deploy.sh` then starts `ashen-crown-bg-raid@1/@2`). `tools/raid_schedule_test.gd`. **A round's flow**:
  `"lobby"` (players wait in the corner rooms behind iron gates, `gate_doors`/`_gate`, each with a bell, Inter `"bell"`
  through `Net.sv_inter`) -> the first bell (or `LOBBY_MAX`) starts `"prep"` (`PREP_SECS`, `start_prep`) -> `"raid"`
  (`open_gates`: bars rise, footprints moved off) -> `"reset"`; the state reaches clients as `cl_bg_raid`
  `"lobby:<s>"`/`"prep:<s>"`/`"raid"`/`"reset"` and the HUD says what's happening. **Three floors**
  (`scripts/bg_floors.gd`, `BgFloors`): the Ossuary (floor 1, `build`), the Frozen Depths (Hrimgar the Frostbound,
  `ice_troll`) and the Overgrown Vault (Old Mossbeard, `hermit`, and the golden chest: `Game.chest_sealed` until he
  dies, wherever he is: a boss's death, `Enemy.die_visual` -> `Game.guard_fell`, unseals the chests whose `"guard"`
  it is on every peer; refused in `Net.sv_inter`; the bosses' brains are `scripts/bg_boss.gd`, `BgBoss`), one map `FLOOR_GAP` apart, rooms joined by wide ways and narrow shortcuts,
  stairways down (Inter `"descend"`, `Game._descend`), portals on every floor (two open on the Ossuary, one below),
  Meshy dressing in `assets/models/bg/`. `World.crypt_shell(themes)` colours each floor's walls.
  `tools/bg_floors_shots.gd` screenshots them. The state reaches players
  through `Net.cl_bg_raid` (the HUD clock, `Battlegrounds.hud`). **Attacks are the same as everywhere**
  (timing, damage, cooldowns: one standard, jj 2026-11-01); while `Game.bg_mode` only walking is slower (`MOVE_MULT`) and
  life doesn't regenerate. **PvP**: every other
  player is an invisible stand-in `Enemy` with `pvp_pid` on each client (`sync_proxies`), so any attack or skill
  that hits monsters hits players (and a player's breakable things are stand-ins with `pvp_obj`, `PvpObjects`); `Enemy.take_damage` sends `Net.sv_pvp_hit`, the server scales it (`PVP_MULT`) and
  deals it (`Net.hit_player`); kills are announced. **Real characters**: the Battlegrounds screen picks one of the
  player's characters (`Game.start_battlegrounds(addr, id)`); its save says `in_raid` until it extracts; what it
  extracts with stays in its inventory. **Death** costs every item worn and carried, the belt and the gold
  (`Game.bg_strip` / `strip_save`: levels, stats, talents and the camp's stash are kept; a plain class weapon is
  given back), dropped where it fell (`Net.sv_bg_died`); a character whose game closed mid-raid is stripped the next
  time the game starts (`Game._bury_lost_raiders`). **Spectating**: fallen, the player stays connected and
  watches the living (`Game.spectate_start` / `spectate_next`, `UI.spectate_panel` in the HUD layer: the camera follows
  `spectate_hero()`, Tab or the arrow keys switch; a watched player who falls is held 2.5 s, one who leaves is passed at
  once), until "Leave the Crypt" or the round's end (4 s after `bg_raid` turns "reset"). Joining uses a one-time Nakama ticket on staging (see "Staging
  and accounts"). Tests: `tools/bg_test.gd` (server `--raid-fast`: 150 s rounds) and `tools/bg_pvp_test.gd`.
  Dev cheat (non-production builds or dev tools): type `maxout` while playing (`Game.max_out`: level 99, stats,
  every talent, a million gold, potions, a bag of the best gear).
- **The Last Flame** (`scripts/vigil.gd`, `Vigil`, zone `"vigil"`; nightly mode 2026-11-01, `docs/nightly/modes/2026-11-01-last-flame/`):
  an endless co-op horde defence (Blaine, 2026-11-03: endless, harder and harder, a leaderboard on the title). The Act I camp's Vigil Gate (Inter `"vigil_gate"` at `ForestCamp.VIGIL_GATE`, `travel`, so the
  party's ready check takes everyone; the way back is `"vigil_exit"` to the camp's `from_vigil`) leads to an indoor
  sanctum (`Vigil.build`: a 32 m hall on `crypt_shell`, three breach rooms N/E/W with red portals, the altar at
  `CENTER`). Clicking the altar (Inter `"vigil"`) kindles a vigil: `WAVES` (ten; champions on 5 and 10 with a boss bar
  on every screen, the Forsaken Bear on 8 and 10) come out of the breaches (`SPAWN_GAP`, at most `MAX_ALIVE` on the
  floor), counts and the flame's life scaled by players (`PER_PLAYER`) and level (the party's average, `Net.vigil_hi`).
  Monsters go for the flame through `Enemy.taunt` (the `Vigil.Flame` node: what Enemy reads of a target) unless a hero
  is nearer; monster missiles hit it through the `"objective"` group (`projectile.gd`). A wave held mends it (`MEND`)
  and lays gold (an item every other wave) by it; all ten: a unique each. Clicking it with a log from the moor feeds it
  (`FUEL`: oak 8%, pine 5%, Ashen Heartwood 25%). The flame out = lost (the wave crumbles, no xp); either way it relights
  after `END_SECS`. Deaths rise by the altar (`Game.respawn`). Host-authoritative: state `Net.vigil_state`/`cl_vigil`
  (twice a second), events `vigil_event`/`cl_vigil_fx`, a partner's kindling `request_vigil`/`sv_vigil`, feeding
  `vigil_feed`; it runs on a player host and on the online co-op server alike. Tests: `tools/nightly_vigil_test.gd`
  (solo, in the gate), `tools/vigil_coop_test.gd` (the co-op server and two players: `-- --server --coop --port 24661
  server`, `-- a 24661`, `-- b 24661`); balance probe `tools/vigil_sim.gd -- [class] [level] [secs]`; screenshots
  `tools/vigil_shots.gd -- outdir [frames] [class]` (needs a display).
  **Endless**: after the ten authored `WAVES`, `Vigil.wave_def(n)` makes the rest (`POOL`, `BASE_COUNT` growing `GROW` a
  wave, a champion every fifth wave, more from the 20th, the Bear every fourth) and `wave_level(n)` climbs `LEVEL_PER`
  a wave past the tenth on top of +1 every three; more on the floor (`MAX_ALIVE_CAP`) and faster. Every `MILESTONE`
  waves held from the tenth: a unique each ("milestone" event). There is no win: the flame out ends it, `held` (waves
  held) is the score, sent with the "lost:<held>:<players>" event so every player's game records it
  (`FlameBoard.record`: the local best in `user://flame_best.json`, the tools' `flame_best_test.json`; and, with the
  cloud on, Nakama's authoritative `last_flame` leaderboard through `ashen.lua` `flame_submit`: one record per account,
  its best, ties to the smaller party). The title's left column shows the top ten (`TitleHome.refresh_board`,
  `FlameBoard.top` -> `flame_top`) and the player's own best.
- **Online co-op** (`scripts/coop_server.gd`, `CoopServer`): the story game hosted by a dedicated server
  (`-- --server --coop --port 24570`, staging systemd `ashen-crown-coop`), so friends co-op over the internet with no
  router setup: the title's "Online Co-op" (non-local builds) joins `BuildEnv.value("coop_server")` with the
  player's own saved character (`Game.start_join` takes `host:port`). It is the normal co-op host with `Net.server` and
  `Net.coop_server`: the server's hero hidden, parked and phased; travel, waypoints, portals and the ready check work
  (`Net.refuses_travel()` is only true on a raid server; the server always says yes to a trip); a joiner arrives
  beside a partner. `tools/coop_server_test.gd` (a server and two players, in the nightly gate).
- **Staging and accounts** (`deploy/staging/README.md`): one DigitalOcean droplet runs the staging backend (Nakama
  3.41 + its own PostgreSQL in Docker behind Caddy's HTTPS on an IP certificate, and the Battlegrounds server as a
  systemd service); production will get its own server and database. Which backend a build talks to is
  `BuildEnv` (`scripts/build_env.gd`: local by default; `tools/ci/write_build_env.sh` rewrites it for staging in CI;
  `user://env.cfg` overrides it on a dev machine; the title shows a "STAGING BUILD" badge). `NakamaClient`
  (`scripts/nakama_client.gd`) is a small REST client: device sign-in, storage, user and server RPCs. In cloud builds
  (`BuildEnv.cloud()`) **characters live in Nakama** (`CloudSaves`, `scripts/cloud_saves.gd`): the local files stay
  the working copy; the first start uploads them (the migration), later starts bring down newer copies from other
  devices (by the save's `played`), every `save_game` is pushed, deletes are removed; offline it plays from the files.
  The Battlegrounds stash is the game server's (`deploy/nakama/modules/ashen.lua`): players can read theirs, never
  write or delete it (before-hooks on WriteStorageObjects/DeleteStorageObjects for `battlegrounds` and `bg_tickets`;
  the server writes through the `bg_stash_*` RPCs with the runtime http_key). Joining a raid the client never sends
  its Nakama session over the game's unencrypted UDP: it gets a one-time 60 s ticket (`bg_ticket`, HTTPS) and the
  server redeems it (`bg_ticket_redeem`). `.github/workflows/staging.yml`: pushes to the `staging` branch build all
  three platforms against staging and upload them to Steam's password-protected `staging` beta branch
  (`tools/ci/steam_upload.sh`, refuses the default branch). Tests: `tools/nakama_check.gd`, `tools/cloud_test.gd`
  (incl. forged stashes, replayed and planted tickets), `bg_test` with `cloud`.
- **Co-op through Steam** (`scripts/steam_link.gd` `SteamLink`, `Game.steam`; Blaine, 2026-11-05): single player and
  co-op are one flow, Enter World, and friends join your world through Steam. GodotSteam 4.23.2 GDExtension
  (`addons/godotsteam`, Godot 4.4+, its `SteamMultiplayerPeer` built in). Development runs as Spacewar (App ID 480).
  The pause menu's Invite Friends (`UI.invite_btn`, only in your own world) hosts through Steam (`Net.host_with` a
  Steam peer: Net takes any MultiplayerPeer) and opens a friends-only lobby with rich presence `connect`; a friend's
  invite / "Join Game" (`join_requested`, or `+connect_lobby <id>` on a cold start) joins (`Game.start_join_steam`,
  `Net.join_with`); `LobbyClient.draw` lists friends' open worlds first. Back to the title closes the world. No
  Steam running: `ok` is false and nothing changes. `tools/steam_host_probe.gd` (host side, display + Steam),
  `-- --steam-selftest` for a build. See docs/patterns/multiplayer.md.
- **Dedicated servers are lean** (Blaine's capacity audit, 2026-11-05; measured on the 4 GB / 2 vCPU droplet with bot
  players, `tools/load_bot.gd`): a server doesn't pose bodies (`Enemy.server_nopose`, on with `--server`; `--pose`
  turns it off) and ticks at 30 fps (`Battlegrounds.server_tick`, `--tick N`); physics stays at 60. The staging CI also
  exports the **Linux Server** preset (`dedicated_server`, everything stripped to placeholders: no textures, meshes
  keep only their AABB; the release template since 4.4.1: 4.3's segfaulted on a dedicated-server pack) as
  the `AshenCrown-server` artifact, never uploaded to itch/Steam. A Battlegrounds world: 1.25 GB -> ~0.4 GB, a busy
  one (6 players fighting) 95% -> 24% of a core, an empty one 31% -> 13%. So server code must never need pixels or
  mesh surfaces (a stripped mesh has none: guard like `Flora.oak_model`'s leaves and `UI._scaled_tex`).
- **Multiplayer runs** (Blaine's overhaul, 2026-11-06; `docs/overhaul_plan.md`, retirements in `docs/cleanup.md`,
  switches in `scripts/mp_mode.gd` `MpMode`): a Battlegrounds raider is a fresh **run character** (`Hero.run`, a
  `RunBuild`; `Hero.start_run`, `Game._start_run_raid`): level 0 on its own fast curve (`RunBuild.xp_for`, attributes
  grow by themselves, `RunBuild.grow`), the primary attack on left mouse and five slots (`RunBuild.SLOTS`: right mouse,
  Q E R F; G and V unused) filled from a spellbook of acquired skills, **passives** (`RunBuild.passive_pool`: generic
  ones plus the class's talents scaled `TALENT_SCALE`, rarity by row, "needs" the skill a talent's icon names) summed
  into `Hero.tfx` instead of talents, gear only in `RunBuild.GEAR` (no belt, amulet, rings), the belt's four slots as
  its consumables, no gold and no backpack: found gear for a worn slot opens the swap window and the old piece is left
  on the ground (`Game._run_pickup_ok`, `run_swap`, `_run_receive`). Camp offers: `RunBuild.offer_for` (three
  choices rolled once per camp from the run's seed, `ODDS` by tier, at least one skill while a slot is empty),
  `RunBuild.claim` once (`Game.run_claim`). Loot in a raid is `Game._run_loot` (`RunBuild.random_gear` for the raid's
  classes). Single player never has `run`. Its windows are `RunUI` (I/K/N or a bar slot: the build; the swap; the
  camp upgrade) in the multiplayer look, `MpStyle` (palette, Cinzel and Inter in `assets/fonts`, OFL).
  `tools/run_build_test.gd`; screenshots `tools/run_ui_shots.gd -- outdir`.
  **Camps** (`scripts/camps.gd` `Camps`): a map's encounters, `Camps.add(w, id, name, tier, pos, r, foes, chest)` (tier
  1-3, 4 = boss; monsters at `Camps.MON_LEVEL[tier]` under the camp's own pack id, its chest sealed until they're all
  dead: `Game.chest_sealed`, refused by the server in `Net.sv_inter`). Every peer sees a camp fall from its own
  monsters (`Enemy.die_visual` -> `Game.camp_check`: the chest flares, a run character within `SHARE_R` gets
  `RunBuild.CAMP_XP`); the chest (`Game._camp_chest`) drops `CHEST_ROLLS` of run loot once for everyone and opens each
  run character's own upgrade (`Camps.offer_key`: camp and round). `tools/camp_test.gd`.
  **The Verdant Reach** (`scripts/bg_forest.gd` `BgForest`, `MpMode.FOREST`; the crypt is retired, docs/cleanup.md):
  the Battlegrounds map, an open lush forest 210 m across: four starting glades (a bell each), four portals at the
  edges, sixteen camps (`BgForest.CAMPS`: place, tier, region, foes; six tier I near the glades, five II, three III,
  Hrimgar's Frostfang Hollow and Old Mossbeard's Mycelial Grotto) joined by winding trails (`TRAILS`, with loops and
  shortcuts; distances baked once in `_bake_trails`), a stream with plank bridges (decks), two ridges with passes cut
  where trails cross (`relief`), and four regions (mushroom woodland, dark elf encampments, the frost hollow, ruins).
  Oaks keep `CANOPY` from open ground so crowns never hide a fight. Bright afternoon light (`Game._zone_env`).
  Screenshots: `tools/forest_shots.gd -- outdir`.
  **Survivors** (`scripts/survivors.gd` `Survivors`): a run that extracts (`Game.bg_extracted`, server-confirmed) ends
  on `RunUI.open_results` with Save Character (`Game.run_save_survivor` -> `Survivors.save`: one file per run,
  `user://survivors/sv_<RunBuild.uid>.json`, so a second save writes nothing); a fallen run's results offer none;
  Return is `Game.run_return` (title, the lobby browser). The lobby sends `run_<class>` (Battlegrounds,
  `LobbyClient.class_pick`) or a survivor's id (Arena, the roster `RunUI.open_roster`); `Game.start_join` loads a
  survivor with `Survivors.load_into`. `tools/survivor_test.gd`.
  **The multiplayer screen** (`scripts/mp_lobby_view.gd` `MpLobbyView`, drawn from `LobbyClient`'s state by
  `render`; LobbyClient keeps the requests and polling): mode tabs, the mode's Meshy art
  (`assets/textures/ui/mp_battlegrounds.jpg`, `mp_arena.jpg`), browse (Create Lobby, the list with filters and its
  loading/empty/full/failure states) and prepare (the chosen class on the title's stage: metas `frame_mid`,
  `lobby_zoom` on `TitleStage`; members, class tiles or survivor, Ready / Start / Leave). A class change in a lobby
  is the service's `pick` op. `tools/mp_lobby_shots.gd -- outdir`, `tools/lobby_ui_test.gd` (a local service:
  `python3 deploy/lobbies/service.py --dev --state <dir> --game . --godot <godot>`). What proves each spec point:
  `docs/overhaul_acceptance.md`.
- **Browser build (WebGL)** is a test build only and is fragile:
  - it is exported with **Godot 4.5.1** in CI (the desktop builds use 4.4.1): Godot 4.3's WebGL renderer
    blanks the whole 3D view in busy scenes (many objects near lights). Keep code working in both versions:
    e.g. `get_meta(key, null)` errors in 4.5, so check `has_meta` first;
  - keep graphics capped (`max_quality()` returns Medium on web); no intro video (excluded in the Web preset);
  - don't mute audio buses (`AudioServer.set_bus_mute`): it throws in Godot 4.3's web audio and aborts startup. Use `Sfx.set_muted`;
  - don't create audio buses with `AudioServer.add_bus()`: Godot 4.5.1's web sample playback files the new bus in front
    of Master and routes Master into it, so the whole game is silent in the browser. `Sfx._buses` uses `set_bus_count`;
- **The archer** (`scripts/archer.gd`, `Archer`; the bow class for Jace, its name still his to choose, "Archer" in
  `Data.CLASSES` until then): with a bow (`Hero.has_bow`; bows are `Data.BASES` with `"cls": "archer"`, only he can
  equip them) his attack shoots (`Archer.shoot` from
  `Hero.swipe_attack`/`free_attack`; `Hero.reach` is `Archer.RANGE`). His skills are fire, cold and lightning (ids kept):
  Fire Arrow (`pierce`: through a line, sets them burning, `Enemy.ignite`; its look is real simulated fire, below), Frost Volley (`volley`: a rain on the cursor,
  hits every 0.2 s and chills, `Enemy.chill`, slower on their feet; a partner's chill reaches the host through
  `Net.send_enemy_chill`; its look is jj's remake, `scripts/frost_volley_fx.gd` `FrostVolleyFx`: he leans back and
  aims high (the rig's `sky` meta, `KnightMocapRig` `SHOT_BODY["sky"]`/`SKY_TILT`) with a glacier arrow on the string,
  a fan of glacier arrows climbs out of the bow, hoarfrost spreads over the ground (the Meshy-painted
  `assets/textures/fx/frost/hoarfrost.png`, `GROUND_SHADER`), freezing fog pools (the `rime` Mantaflow book), the rain
  drops six unique Meshy ice arrows (`FrostVolleyFx.RAIN`, `assets/models/arrows/rain/`: spear, icicle, runic, shard,
  snowflake, wraith, each with its own glow, rim, streak, trail and spin) that stick in and burst in cold mist (the
  `frost` book), the frozen ground slows whatever stands in it or crosses it until it thaws (`Archer.frost_radius`,
  `_frost_ground`: full until the shatter, shrinking with the thaw; host side), Meshy ice-crystal clusters
  (`assets/models/fx/frost/crystal.glb`) burst up, foes under it frost over (`Enemy.set_frost`, rime crawling up from
  the feet; one dying frozen shatters), and at the end every crystal breaks into its Blender-fractured pieces
  (`crystal_pieces.glb`, `fracture_rock.py`) and the frost thaws; sounds `frost_loose`, `arrow_rain`, `ice_arrow_hit`,
  `frost_spread`, `ice_burst`; the books are `tools/blender/fx/smoke_flipbook.py` kinds `frost`/`rime`, packed by
  `tools/fx_smokebook.py`, listed in `DemonKitFx.BOOKS`), Thunderstep (`snare`, id kept for old saves; jj's pick in place of Storm Snare: he backflips
  `Archer.VAULT_DIST` away from the pointer (`Archer._vault`, carried by `_update_vault`, rooted meanwhile), driving the
  Meshy thunderstone (`assets/models/fx/storm/thunderstone.glb`, gold veins by `tools/blender/fx/gold_veins.py`,
  fractured into `thunderstone_pieces.glb`) into a gold storm sigil (`assets/textures/fx/storm/sigil.png`, Meshy) where
  he stood; `SIGIL_ARM` later it detonates (`_detonate`: stun and damage on it, lightning leaping into the nearest
  others beyond; Aftershock strikes again); the look is `scripts/thunderstep_fx.gd` `ThunderstepFx` (the flip on the
  rig, gold `ElementalFx.bolt`s, the sky bolt, sparks, shock ring), sounds `thunder_vault`, `sigil_charge`,
  `thunder_blast`), Spirit Beast (`beast`: commands his wolf, below). Arrows are Meshy models (`assets/models/arrows/`
  war / fire / frost, prepared by `tools/blender/prep_arrow.py`: head toward Godot -Z), `Archer._arrow_mesh(kind)`.
  Talents: Flame, Frost, Storm (`Talents.TREES["archer"]`; specials arrow_split, burn_dmg, wolf_burn, chill_pct, wolf_howl,
  frost_shatter, arc_count, snare_dur, snare_max (Aftershock), volley_size, beast_two). His **wolf** (`spirit_beast.gd`, `SpiritBeast`): JJ's dire forest wolf (Meshy, 25% larger
  than a wolf, `assets/models/monsters/wolf.glb`, rigged by `tools/blender/act1/rig_quadruped.py` on the lion's
  skeleton, so `Lion.build(glb, scale)`/`Lion.pose` run it), his companion from the start: a state machine of follow /
  engage / command / protect / investigate / return / hold (every number in `SpiritBeast.CFG`); it settles at his side,
  trots or sprints to keep up, sniffs at loot and chests, protects him, goes for the one he shoots (`Hero.mark`), keeps
  its target (`commit`), gives up on what it can't reach, follows him through zones; monsters it bites turn on it
  (`Enemy.taunt`), it rises again 18 s after falling (`Archer.keep_companions`, `Hero.beast_down_t`), and he runs 10%
  faster while it lives. F commands it (`Archer._command_beast`): on an enemy it pounces, on open ground it holds, on
  himself it comes back, each with the 12 s battle buff. `"spirit_beast"` in `Data.ENEMIES` is the wolf as a monster.
  `tools/archer_test.gd`, `tools/pet_test.gd`, `tools/pet_clip.gd`, `tools/archer_shots.gd`, `tools/wolf_sheet.gd`.
  Body: the ranger (`assets/models/archer_ranger.glb`, `Archer.build_body`): the Meshy
  northern ranger (wolf-fur cowl, dark leather, quiver) on the knight's mocap system (`Knight.build_mocap(glb, opts)`,
  `knight_mocap_rig.gd`): Meshy library clips for idle/walk/run and, with the bow out, the aimed stand and walk
  (`combat_idle`, `walk_aim`); the bow attack, Fire Arrow and Frost Volley play the `shoot` clip whole-body (`Archer.SHOT`:
  its draw squeezed in before Anim's release frame, the body turned side-on, `yaw`); Every shot draws a fresh arrow from the quiver: the standing shot plays `shoot_quick` (Meshy's "Archery Shot 1" + "Archery Shot 3" joined by `prep_ranger_mocap.py`, 1.67 s, near its own pace: reach over the shoulder, grab, arrow out, nock, draw to the cheek, a short hold, release on Anim's impact frame with the string hand flung back, back to the ready stance) along `SHOT.keys` (`KnightMocapRig.shot_time`), turned side-on (`yaw` -90, like the aiming stand's `stand_yaw`); the clip has its own loose, so `_shot_body`'s fling, recoil and follow-through only go over the aimed walk (`SHOT.body_stand`). The old 7.8 s "Draw and Shoot from Back" (`shoot_back`) stays in the glb. Compared and left out (Meshy 223, 229, 226, 234/690): near copies of 222/224, a held aim, and a "Walk Forward While Shooting" that holds a half draw and never looses. Shooting on the move: he keeps walking at `Archer.SHOOT_MOVE` (36%) of his pace (`Hero._process`; a shot at a clicked foe still plants him) in the aimed walk (`walk_clip`, timed to his speed, `w_aimwalk`), and only his right arm takes the reach to the quiver from `reach_clip` (a filtered Blend2 over `reach_bones`, weighted by `reach`). `Archer.pose_bow` shows the arrow in his hand from `GRAB` to `NOCK` (out of the quiver at `DRAWN`; `_hand_arrow`: point first into the quiver `QUIVER`, then swung onto the bow) and, while he shoots, solves the bow onto his hands: grip in his left fist, the draw line on his right fingers (`FINGERS`), limbs upright with a `CANT`, so the string always meets the hand. Colours: `Archer.COLORS` ("crimson"; also teal, verdant, royal, "" = Meshy's own) swaps the albedo for `assets/textures/ranger/ranger_<name>.jpg` (`Archer.dye`), made by `tools/archer_colors.py` (texture dumped from the glb, regions from `tools/blender/archer/region_uv.py`: the face, hands, fur and straps keep their colour). Storm Snare and Spirit Beast are
  the game's cast pose over the upper body. He holds the equipped bow in his LEFT hand (`J["grip_bow"]`,
  `Archer.BOW_HOLD` per bow kind, `Hero._weapon_hand`); bows are drawn by `Models.enemy_weapon` (`item_model`
  had none). `Archer.pose_bow` (every frame after the pose, the puppet's too) turns the bow from hanging in his
  relaxed hand to upright on the shot's line with his stance (the rig's `w_side`), swaps the straight string for two
  strands his right hand's fingers draw back to his cheek with a nocked arrow on the bow, and on the release the
  arrow (fired from the bow hand, `_loose`) is gone and the string snaps back with a damped shiver
  (`Archer.BOW_SPEC`: each bow model's tips, nock, pull, grip and hang). His bow is the Meshy carved recurve `assets/models/ranger_bow.glb` (`Models.item_model` for bow kinds, `Models.RANGER_BOW`; a longbow is it at 1.15x; `Archer.bow_key` picks the `ranger`/`ranger_long` BOW_HOLD/BOW_SPEC entries; bandit archers keep `enemy_weapon`'s bow). Rebuild: `blender -b --python tools/blender/archer/prep_bow.py -- meshy.glb assets/models/ranger_bow.glb spec.json [length] [tris]` (cuts Meshy's string, stands it limbs +y / string +z / grip on the origin, 1.45 m, ~9k tris, 1k textures) and copy spec.json's tips and rest into BOW_SPEC. Rebuild: `meshy.py rig`/`animate` (clip ids in the commit), then `blender -b --python
  tools/blender/archer/prep_ranger_mocap.py -- rigged.glb out.glb 60000 clips_a.glb clips_b.glb` (merges and renames
  the clips, cuts away the bow Meshy fused into his right hand, `bow_select.py`). Without the glb: the knight's
  procedural body dressed as a hunter (`Archer.build_placeholder`, `Archer.body_gear` kept on every gear change; its bow in `J["grip_l"]`/`J["bow_l"]`). Preview: `tools/mocap_knight_clip.gd -- outdir
  run|attack|shootwalk 34|game|side|close|closeback frames archer [longbow]`. Talent icons still to paint (`tools/talent_icons.py`).
  `tools/archer_test.gd` checks it (run it with `--fixed-fps 60`; it counts frames).
  **Arrow effects** (`scripts/arrow_fx.gd`, `ArrowFx`; the quality standard every Archer skill must meet is
  `docs/archer_vfx_standard.md`: photoreal, simulated, proved in Forward+): data-driven per arrow kind
  (`ArrowFx.PRESETS`; `"war"` is the plain arrow). Fire Arrow is the `"fire"` preset, **real fire**: Mantaflow
  sims (`tools/blender/fx/fire_sims.py`: a licking flame loop, a fireball, a smoke puff; Cycles, 256 px frames)
  packed by `tools/fx_flipbook.py` into 8x8 flipbooks `assets/textures/fx/real_*.png` (R = flame, G = flame x
  temperature; smoke as an RGB lightmap + opacity) plus a procedural scorch decal (albedo, normal, ember emission).
  `FIRE_SHADER` colours the sim's flame by a blackbody at its own temperature (`ArrowFx.blackbody`, Kelvin);
  `SMOKE_SHADER` relights the smoke in `light()` with the scene's real lights and shadows; `STREAK_SHADER` embers
  and sparks cool along the blackbody curve, sparks collide and bounce; `HAZE_SHADER` heat distortion (Forward+);
  `HEAT_SHADER` overlays the arrow (glowing head, charred shaft). The flight: sim flames wrapped round the head and
  blown back (local particles), the flame's tail as one continuous strip (`_ribbon`/`_strip`: the head's path
  every `RIBBON_STEP`, `RIBBON_FIRE_SHADER` lays two offset frames of the sim flame along it and tears it with
  noise toward the tail, `RIBBON_SMOKE_SHADER` the lit smoke strip behind rising and widening with age), lit smoke
  puffs, embers, sparks and haze emitted in the world from emitters `fly` keeps on the head (left to burn out by
  `end_flight`), a flickering light with shadows (≤ `LIGHT_CAP`). Its timers run on `ArrowFx.now()` (game
  seconds, so slow offline renders keep real motion).
  `release`, `draw_charge` (the nocked arrow burning in his hands), `pierce` (a gout of fire out of a foe's back),
  `burn` (the sim's flames rising from every joint and bone of a burning foe's skeleton, `_burn_points` re-reads
  them as he moves; sooty smoke; `Enemy.ignite(dps, t, look)`: a look other than "" keeps the Demon's ember flames
  off, and its ticks are amber with no blood or flash; the arrow's own hit is `Enemy.seared`: no blood), `finish`
  (three turned, mirrored, staggered instances of the fireball sim, a white-hot core, tongues of flame, the light
  flash dying to the glow, sparks, embers, a smoke column `_smoke_column`, a Decal scorch) and the ground's reaction
  by `ArrowFx.surface` (grass smoulders, stone sparks, dirt dust, wood catches along its grain `_plank_burn` (meta
  `wood_grain`), `"surfaces"` in the preset; a zone may answer with a `surface_fn` meta). All from the one "loose" event,
  on the caster and his puppet alike. Web / Low (`ArrowFx.cheap`): half the particles, no haze or light shadows;
  Compatibility: no soft particles or haze, the scorch as a quad. The old Phoenix look (wings of painted feathers,
  `phoenix_*.png`) is retired; its textures stay. The shot's body (`KnightMocapRig._shot_body`, on for `SHOT`
  "body"): procedural turns over the clip (the spine winding up through the full draw, a breath taken and held,
  the back set (draw shoulder back, bow shoulder down), weight on the back foot, a tremor at full draw, the bow arm's
  recoil kick, the string hand flung back past the ear, the weight rolling onto the front foot in the
  follow-through, the head steady on the mark), lighter while walking, before `pose_bow` solves the bow.
  **Proof range** (`tools/fire_range.gd` + `tools/fire_range_zone.gd`, through `World.custom_zones`): five lanes
  (grass, stone, dirt, wood, dark) at dusk with the real ranger and zombies, recorded in Forward+ on lavapipe
  (`--rendering-driver vulkan --rendering-method forward_plus`, `--fixed-fps 30`; modes game, follow, impact,
  surfaces, anim, still); the moor is too heavy for the cloud machine. `tools/fire_arrow_clip.gd` (the moor, GL)
  and `tools/arrow_fx_lab.gd` remain for quick looks.
- **The Plague Doctor** (`scripts/plague.gd`, `Plague`; class `"plague"`, one `Plague` per hero in `Hero.pd`): the Meshy
  plague doctor (concept 1 of four in the session's picks: beaked mask with green-lit goggles, buckled greatcoat split
  front and back, bandolier and belt of green/amber/violet vials, pouches, instrument roll, brass censer) on the knight's
  mocap system like the ranger: `assets/models/plague_doctor.glb` from `tools/blender/plague/prep_plague_mocap.py --
  rigged.glb out.glb 60000 clips_a.glb clips_b.glb clips_c.glb` (Meshy task ids and the 26 clip ids are at its top).
  **Whole-body clips per attack style** (new, any mocap body can use them): `Knight.build_mocap` opts `"acts"`
  `{style: {clip, keys, frac}}` adds one AnimationNodeAnimation + TimeSeek per style behind a Transition (`act_pick`) and
  a Blend2 (`act_mix`) over everything; `knight_mocap_rig.gd` seeks the clip to the attack's progress along `keys`
  (`"frac": true` = clip times as fractions of the clip's length), turns the procedural layer off and pins the hips over
  his spot (library clips step about). `Plague.ACTS`: his own cane combo (`swipe1/2/3` = `peck`, `flick`, `censer_slam`: Meshy 221, 242, 128; each blow's
  effect is `Plague.cane_blow`, called by `Hero._swipe_impact` with the foes struck: Crow's Peck poisons them for 2 s,
  Vial Flick fans drops across the arc and poisons everyone struck for 3 s, Censer Slam cracks a vial on the ground
  ahead in a 2 m cloud for 2.5 s; poison source `"cane"`, scaled by `dmg:attack`), Toxic
  Flask `pd_flask` (over-shoulder throw), Volatile Mixture `pd_volatile` (crouch charge and throw), Pestilent Trap
  `pd_trap` (crouch and place), The Last Epidemic in two stages `pd_slam` (the censer smashed) then `pd_dome` (arms
  raised; `Plague.update` starts it when the first ends), `pd_inspect` (the class stage's fidget: a vial held to the
  light). New styles are appended to `Net.STYLES` and timed in `Anim.impact_at`. Clip strips: `tools/blender/plague/clip_sheet.py`.
  Skills (the PvP kit of 2026-11-01; design in the project doc "plague kit overhaul plan"): Pestilence Vial (Q, `toxic`,
  see "Pestilence Vial"), Swarmcraft (E, `swarm`: `PlagueSwarmFx`, a GPU-particle flock of the Meshy fly (`fly.glb`,
  decimated to 900 triangles; `_model_fly_shader` draws its painting, beats whatever reaches past the body's sides as
  wings and lights its green eyes) run by a particle process shader, a haze of the vapour book, released from the
  Meshy `reliquary.glb` in his hand with the same flies pouring out; flies to its point at `SWARM_SPEED`, never
  homing, hovers `SWARM_T`, recast = sent on (`Plague.can_cast` redirects and refuses the cast, so no cost),
  `SWARM_REDIRECTS`; bites, Harried, reveal; a puppet's dodge roll through it scatters it, and so does any area blow:
  `Fx.ring` and `Fx.holy_slam` call `Fx.area_hit`, which tells `Fx.area_listeners` (the swarm listens while out,
  `Plague._area_hit`; his own bloom pulse and vat are deliberately not area blows); its cooldown is set when it goes
  home, `_swarm_end`), Corpse Bloom (R, `bloom`: `PlagueBloomFx`, the Meshy `bloom.glb` growing out of the ground
  over the Meshy root-mat painting `bloom_roots_*` inside the painted ring of roots `bloom_ring_*` at the reach's
  edge, the same ring drawing in from the edge on its own clock (`_root_shader`); the pulse is the spore simulation
  (`PlagueSmoke.spore_card` and `puffs`); pulse every `BLOOM_EVERY` after a `BLOOM_WARN` ring; a foe that moved
  less than `BLOOM_STILL` since the ring began is snared and caught by the Meshy `roots.glb` bursting up round it,
  `lash`; planted with the Meshy `syringe.glb`), Fog of the Forgotten (F, `fog`: `PlagueFogFx`, the Meshy
  `censer.glb` held (`HELD` "censer") then dashed down to lie smoking at its heart, three layers of puffs each
  playing the fog simulation from where it has rolled out (`PlagueSmoke.FOG` puffs start 35% in: its first frames
  are a tight ball that reads as bubbles), a lit ground layer from the Meshy painting `fog_base_albedo` (its wisps
  kept, alpha from their brightness, two copies turning against each other; a bright flat plate is what to avoid); the hop is
  `Hero.shove`; `Plague.speed_mult` in `Hero._process`; a puppet inside is hidden from Battlegrounds enemies beyond
  `FOG_SEE` (`hidden_from`; `_update_visibility` sets `Hero.fog_hidden`, which `_puppet_process` applies to the whole
  puppet with its name tag and map dot, and `Battlegrounds.sync_proxies` copies to its stand-in's `Enemy.pvp_hidden`
  so it can't be clicked or auto-targeted, `Game.pick_enemy`/`Hero._assist_pick`), faded for co-op partners;
  monsters (not bosses or the Sloths) lose track of him in it from beyond `FOG_SEE`, like of a Demon in the
  Underworld (`Plague.hidden_from_monster`, the `hero_dead` test in `Enemy._process`);
  striking from it sends `reveal`), Transfusion (G, `transfusion`: `PlagueTransfusionFx`, the Meshy `apparatus.glb`
  on his back, a hose drawn each frame (a camera-facing strip tiled with the Meshy painting `hose_albedo`: braided
  leather and brass with glass windows of serum), a shell of glass whose veins are the Meshy painting `glass_veins_mask`
  (triplanar, mirror-tiled, filling with serum), steam and the heal column from the vapour book; `Hero.take_hit` calls
  `Plague.absorb`; cleanse is `PvpStatus.cleanse`; the soaked damage goes to `heal_pool` capped at `TRANS_CAP`; any
  cast ends it early), The Last Experiment (V, `experiment`: `PlagueExperimentFx`, the Meshy `vat.glb` and the
  Meshy-rigged `homunculus.glb` (clips Zombie_Scream, Slow_Orc_Walk, Idle, Fall_Dead_from_Abdominal_Injury, hips
  pinned with `ForestCamp._pin_root`); the burst flings the vat's own glass (`vat_shards.glb`,
  `tools/blender/plague/vat_glass.py`: its cylinder cut into 24 curved panes) and plays the FLIP wave
  (`assets/textures/fx/vat_wave.png`, `KIND=wave splash_flipbook.py`, on a card drawn over what's near, `_wave`); each
  spew is the Meshy bile-spray painting `bile_fan_*` (keyed by colour, `ground_decal.py ... chroma`) on a
  terrain-following fan (`_ground_fan`, `_fan_shader`: a ghost filling from the mouth with a bright front over
  `SPEW_WARN`, then the wet splatter drying); stage 2 is the attack `pd_crank` with `atk_skill` "crank" whose impact
  bursts it; a stun, another move or walking `>1.5 m` bursts it small, `EXP_R_SMALL`). **Blight** (`_add_blight`):
  one stack per different skill, Fever at 3 (`PlagueFever`: the Meshy blight mark `blight_mark.png` wheeling over the
  head per stack, bursting into the Fever at 3; `stacks`/`fever` take the old node out of the tree before freeing it:
  a node only queued for freeing keeps its name, the new one would be renamed and never found again; Fever sweats the vapour book, glows, and the Meshy ring of fever `fever_ring_albedo` throbs on the
  ground round its feet; PvP: `blight` status with k 3 = heals x0.6 on
  Transfusion and reveal). **Smoke** (`scripts/plague_smoke.gd`, `PlagueSmoke`): the kit's Mantaflow flipbooks,
  `VAPOUR` (`vapour.png`, looping), `FOG` (`fog_puff.png`, 8 x 4: dust and rolls), `SPORE` (`spore_burst.png`, 6 x 4)
  and `WISP` (`fog_wisp.png`, 8 x 4: a flat bank of fog torn into wisps, the fog's body), made by
  `tools/blender/plague/smoke_flipbook.py -- spore|fog|wisp outdir` and packed by `tools/flipbook_pack.py -- frames
  out.png --cols N --cell px --level L [--alpha-gamma G] [--vignette V]` (crops round the frame's centre to what the
  smoke fills, brightens it to a base the game tints, fills out thin edges, fades cells out before their border); `puffs` (one-shot burst, `flat` = rolled out level), `vapour` (continuous, `path`/`disc` for another
  book over an area), `spore_card` (the whole sim once on a camera-facing card); materials are shared. Old binds of
  volatile/trap/epidemic become swarm/bloom/experiment (`Plague.OLD_IDS`, `PlagueSkills.migrate_binds`); talent ids
  kept, their effects now name the new skills. The Meshy sources (concept images, task ids) are listed in the plan
  doc. **PvP statuses** (`scripts/pvp_status.gd`): a skill calls `PvpStatus.send(game, enemy, kind, secs, k)`; a
  player's stand-in goes `Net.sv_pvp_status` -> `Battlegrounds.pvp_status` (distance, ceilings `MAX`/`MAX_K`,
  diminishing returns per target and kind: 100%, 50%, immune 3 s) -> `Net.cl_pvp_status` -> `PvpStatus.apply` on the
  hero (`Hero.pvs`, read in `_process` for speed and in `_start_attack` for harried); a monster gets chill / stun.
  **What they look like** (`scripts/pvp_status_fx.gd`, `PvpStatusFx`, from the kit's own Meshy and Blender assets): snare
  = the Meshy `roots.glb` bursting up round his feet (sinking when he's free), harried = a knot of the swarm's flies
  round his head and shoulders (the swarm's process shader with a hollow `core` and a narrower band, `tall`), slow = the
  vapour book clinging round his feet, reveal = the Meshy eye sigil `reveal_eye.png` bobbing 3 m over him (above the
  Blight marks), blight = `PlagueFever.stacks`/`fever`. `Hero._process` calls `PvpStatusFx.sync(h, bits_of(h),
  blight_of(h))`, which only adds what's new and ends what stopped (`Hero.pvs_shown`); the bits and stacks ride at
  the end of the hero's state packet (`Net._hero_packet`: base 15, the boat's 5, then `[bits, blight]`), so a
  player's puppet on everyone else's screen shows the same (`apply_net_state` -> `net_pvs_bits`/`net_pvs_blight`,
  `_puppet_process`); the stand-in a player strikes never shows them twice (`Plague` skips local marks on a
  `pvp_pid`). Test: `tools/plague_pvp_test.gd` (a server and two players, `-- --server --port N --raid-fast server`,
  `-- a N`, `-- b N`: the Doctor's bloom roots the patient through the server, the swarm harries and Blights him, and
  each side sees it on the right body; then the patient breaks a second bloom and the vat).
  **His things can be broken in PvP** (`scripts/pvp_objects.gd`, `PvpObjects`, the kit's designed counterplay): the
  Corpse Bloom, the vat while he cranks it (broken = the experiment fails: no blast, no quarantine, the crank stops,
  the creature spills out dead; `Plague._exp_fail`, `PlagueExperimentFx.Vat.fail`) and the creature (killed = the
  quarantine ends). Each takes `PvpObjects.HITS` blows (3 / 3 / 4), not damage, so nothing needs balancing against
  anyone's damage; the server lets each player's blows on a thing through at most once per `GAP` (0.6 s, `allow`), so
  a poison tick or burning ground counts like a slow swing. Each gets an id from its owner's game (`Plague.next_oid`,
  sent as the last field of its `bloom`/`vat`/`burst` event); every other client's ghost of him puts an unseen stand-in
  `Enemy` on it (`pvp_obj`, `pvp_owner`, not `pvp_pid`; only in the Battlegrounds, never on the server or for co-op
  partners), so any blow that hits monsters hits it and the pointer picks it, its name and blows left in the target
  bar. `Enemy.take_damage` on a stand-in -> `PvpObjects.struck` -> `Net.sv_pvp_obj_hit` -> `Battlegrounds.pvp_obj_hit`
  (alive, within `REACH` of where the server's own ghost of the owner has it, `PvpObjects.where`/`Plague.obj_pos`) ->
  `Net.cl_pvp_obj_hit` -> the owner's `Plague.obj_hit`, which sends `"obj|id|left"` to everyone (`_obj_left` on every
  game: a recoil, `Bloom.hurt`/`kill`, `Vat.hurt_vat`/`hurt_creature`, the stand-ins' count, and the break on the
  last). Statuses never land on a stand-in (`PvpStatus.send`, Blight, poison). `Battlegrounds.sync_proxies` drops the
  stand-ins of a player who left or died (`PvpObjects.prune`). The creature on another player's screen comes for him
  (`Plague._creature_foes`), as it does on its owner's game. A new class's breakable thing: give it an id, its
  `HITS`/`NAMES`/`SIZE` entry, a stand-in on the ghost and an `obj_pos`/`obj_hit` on its owner's skill object.
  Other classes' crowd control still only reaches monsters (moving them onto `PvpStatus` is a balance decision).
  Every number is a const at the top of plague.gd;
  talent keys (`cloud_size`, `poison_dmg`, `swarm_size`, `bloom_size`, `fog_dur`, `trans_cap`, `exp_size` ...) are
  read where the skill is. **Co-op**: the first class whose effects partners see: `Plague._send` → `Net.hero_fx` (the
  host relays; `sv_hero_fx`/`cl_hero_fx`) → `Plague.remote` on the puppet, whose `Plague` is a `ghost()` (builds the same
  vials, pools, swarm, bloom, fog, apparatus and experiment, deals nothing). His leather is dyed (`Plague.COLORS`, default "oxblood2": an oxblood coat and cape with a black hat,
  gloves and boots; also "oxblood", "plague", "plague2", "ash2", "" = Meshy's black): `Plague.dye` swaps the albedo for
  `assets/textures/plague/coat_<scheme>.jpg`, made by `tools/plague_colors.py` from the albedo and metal maps that
  `tools/blender/plague/dump_textures.py` saves out of the glb and the regions `tools/blender/plague/region_uv.py` finds
  (head and hat above the collar, gloves by the hand bones, boots below the coat's hem): only the dark, grey, non-metal
  leather is tinted. His cane: `Data.BASES` `physician_cane`/`crow_cane` (kind `"cane"`,
  `"cls": "plague"`, `Plague.cane_model`: the Meshy crow-skull cane `assets/models/plague/cane.glb`, `prep_cane.py`).
  Props: `assets/models/plague/` vial and vial_shards (Blender, code), vat_shards (Blender, `vat_glass.py`), bloom,
  apparatus, vat, fly, reliquary, roots, syringe, censer (Meshy image-to-3D, `tools/blender/prep_prop.py`; the
  censer's ash slab cut off first with `tools/blender/trim_below.py`), homunculus (Meshy rig + animate,
  `tools/blender/prep_npc.py`); flask, volatile and trap are the retired skills' props, kept unused. Ground paintings
  in `assets/textures/plague/` (`*_albedo` + `*_normal` from `ground_decal.py`, mipmapped). Talents: Toxicology,
  Vermin and Rot, The Experiment (icons `p_*.png`, `plague_tree*.png`, painted with Meshy by `tools/talent_icons.py`; the last two trees' grids were repainted for the new kit). Tests: `tools/plague_test.gd` (`--fixed-fps 60`),
  `tools/plague_mp_test.gd` (host + join); screenshots `tools/plague_shots.gd` (`--fixed-fps 10`); the six skills in a
  row for video: `tools/plague_kit_clip.gd -- outdir [skills|all] [game|close] [quality]` (`fever`, `pvp` and `break`
  are extra segments: Blight and Fever on a foe, his statuses on another player, that player breaking his bloom and
  vat; xvfb, `--fixed-fps 30`;
  ~1.9 s a frame at 640x360 and ~5-6 s at 1280x720 on the cloud's llvmpipe, ~3-5 GB of memory: render one at a time,
  and split a 720p run of all six into two, each under the 2 h limit of a background job).
- **Pestilence Vial** (the Plague Doctor's Q, id kept as `toxic`; 2026-11-01, branch `test-plague-kit`, first skill of
  the Plague kit overhaul in the project doc "plague kit overhaul plan"): look in `scripts/plague_vial_fx.gd`
  (`PlagueVialFx`), gameplay in `Plague` (`_launch`/`_update_vials`/`_shatter`; pool 2.6 m for 3.5 s as a `clouds`
  entry whose node is a `PlagueVialFx.Pool`, poison lingers `VIAL_LINGER` 2 s, cooldown 1.6 s). The vial is
  `assets/models/plague/vial.glb` and its fractured glass `vial_shards.glb`, both built in code by
  `tools/blender/plague/vial_build.py -- assets/models/plague` (objects glass/liquid/cork/wax/twine/collar; materials
  are assigned by name in `PlagueVialFx.vial`). The liquid is a full inner volume cut by a world-space plane in its
  shader (`plane_n`/`plane_d`, back faces = the surface) that `PlagueVialFx.Slosh` leans against the vial's
  acceleration on a spring; in his hand (`HELD` "vial", `held_slosh`) and in the air (`Flight`, its own light). Three
  mixtures rotate (`RECIPES`, `Plague.recipe`, sent as the 6th field of the "throw" event). Everyone sees a landing
  ring for the flight (`landing_ring`); the shatter flings the real shards and the cork (`Debris`), a splash crown,
  droplets and mist; the pool creeps out, bubbles, glows in its veins and dries to a stain (`_pool_shader`).
  **Rebuilt on Meshy and Blender (2026-11-01, evening)**: the pool is a Meshy top-down painting
  (`assets/textures/plague/puddle_albedo.png` + `puddle_normal.png`) made into a decal by
  `tools/blender/plague/ground_decal.py -- painting.png out_prefix [px] [relief]` (alpha keyed off black, a normal map
  baked in Blender from a displaced copy), revealed from the impact out and retinted per mixture (`_pool_shader`);
  the splash is a Blender FLIP liquid simulation (`tools/blender/plague/splash_flipbook.py -- outdir res frames px`:
  a core and a ring of thrown gobbets, per-object velocities since per-normal velocity is ignored in a background
  bake; the first 20 frames packed 5 x 4 into `assets/textures/fx/vial_splash.png`) on an upright camera-facing card
  (`_splash`, `_flip_shader`); the pool's vapour is a Mantaflow smoke flipbook (`tools/blender/plague/vapour_flipbook.py`,
  36 frames 6 x 6 in `assets/textures/fx/vapour.png`) on the particles; the landing mark is the splash's ghost (the
  puddle's alpha) and the vial's shadow (`landing_ring`). The Last Experiment's ground uses the same decals:
  `blight_*` (the flood) and `ring_*` (its boundary, its band remapped thin along the edge) in `_zone_shader`.
  His skills draw no weapon trail (`Hero._update_trail`). Frames: `tools/plague_vial_clip.gd -- outdir
  close|hand|game|fight [secs] [throws] [quality]` (xvfb, `--fixed-fps 30`; ~5-7 s a frame on the cloud).
- **Doug** (`scripts/doug.gd`, `doug_skills.gd` `DougSkills`, `doug_fx.gd` `DougFx`; design `docs/characters/doug.md`;
  Blaine's tier-1 character and the pilot of the character workflow, `docs/character_workflow.md`): the stubby circus
  brawler. Body: Meshy concept edited from Blaine's reference, image-to-3D, Meshy auto-rig + library clips merged by
  `tools/blender/doug/prep_doug_mocap.py` into `assets/models/doug.glb` on the knight's mocap system (`Doug.ACTS`:
  his drumstick combo and each skill's whole-body clip); props (pie, banana, pin, trampoline, car, drumstick) are
  Meshy in `assets/models/doug/` (checked with `tools/blender/prop_sheet.py`; the car's jester rider cut away by
  `tools/blender/cut_above.py`). Sounds: `doug_*` (ElevenLabs: splat, slip, honk, slide whistle, boing, pop, klaxon,
  belly-flop; auto-ranked takes until someone picks on the Sound Picks page). Seven skills (his first, Cream Pie, on the right mouse button: a class with
  seven puts `own[0]` on RMB and the rest on Q-V, `Hero.default_binds`): Cream Pie (lobbed; Pied: monsters stunned
  and slowed, a player creamed, `UI.pie_face`, and no aim assist, `Hero.pied_t`; once per target per 6 s), Banana
  Peels (slip: `Hero.take_hit "slip"`), Pratfall Slide, Doppel-Doug (`Hero.hidden_t`: monsters lose him, partners
  see him fade; a balloon double runs off and pops), Pin Juggle (pins ricochet), Big Top Bounce (an arc to the
  cursor, a launching belly-flop), Clown Car (5 s, `DougSkills.car_mult`, unstoppable: `driving`; six mini clowns pie
  the nearest foes). PvP crowd control goes through `Net.send_pvp_effect` (server-checked, a zero-damage hit of
  that kind). Talents: Slapstick, Showmanship, Big Top (icons `d_*`, `doug_tree*`, painted with Meshy). Tests:
  `tools/doug_test.gd` (`--fixed-fps 60`), `tools/bg_pvp_test.gd` with `doug` on the players' lines (the pie Pies
  another player through the server).
- **Adding a class** (nothing in `hero.gd` names a class's skills; `ClassSkills` hands them to the class's script):
  1. `Data.CLASSES`: name, starting stats, `desc`, optional `weapon`, `voice` (hurt/death sound suffix), `attack_pace`, `hud`.
  2. `Data.SKILLS`: four (up to six: Q E R F G V) entries with its `cls`, each with an `aim`.
  3. Skills: copy `tools/templates/new_class_skills.gd` to `scripts/<class>_skills.gd` (uncomment its `class_name`)
     and add it to `ClassSkills.of` and `ClassSkills.all`. Its static `can_cast`/`cast`/`impact`/`update`/`rooted`/
     `clear`/`died`/`sound` are the whole contract; skill state goes on the hero in one dictionary (like `Hero.wr`,
     `Hero.dm`) or one object (like `Hero.pd`), so hero.gd doesn't grow. Start motions with
     `h._start_attack(style, id, seconds)`; "ahead" is `h.aim_dir()`. Weapon-trail colour: `ClassSkills.trail_color`.
     Run `godot --headless --editor --quit` after adding the class_name.
  4. Effects: a `<Class>Fx.play(h, ev)` handler (add the class to the `match` in `SkillFx.play`). Keep the gameplay
     and the effects apart: the skill code deals the damage and calls `Hero.fx(id, event, data)` for everything seen;
     the cast's event comes for free, and `tools/coop_fx_test.gd` fails any skill that shows partners nothing (see
     "Co-op skill effects").
  5. Look: build it the way `wraith.gd` does (reuse `Knight.build` for the skeleton so animation and co-op keep
     working), `Hero._build_rig`. Glyphs in `ui.gd` `SkillGlyph`, talents (`Talents.TREES`/`AUTO`), the class
     picker (`ClassStage.CLASSES`/`ACCENTS`/`EMBLEMS`/`SIGNATURE`/`SKILL_SHOW`, `_fidget`).
- **The dragons** (`scripts/dragon.gd` `Dragon`, classes `wyrm` / `serpent` / `wyvern`; added 2026-11-01 on
  `test-dragons`): the Obsidian Wyrm (four legs, wings), the Frost Serpent (long, wingless, four short legs) and the
  Storm Wyvern (two legs, wings as forelimbs). Models: Meshy 7.1 (text-to-3D for the wyrm and serpent, a Meshy concept
  image then image-to-3D for the wyvern so it has four limbs, not six), remeshed to ~31k triangles, rigged in Blender
  with a chain skeleton (`spine_*`, `neck_*`, `head_0/1`, `jaw_0`, `tail_*`, `leg_<FL|FR|HL|HR|L|R>_0..2`, winged:
  `arm_<L|R>_0/1`, `fing<N>_<L|R>_0/1`; `_L` at the model's -x) heat-skinned through a voxel proxy, 2K JPEG
  textures plus a glow map, real-world metres (wyrm 10 m long, serpent 12 m, wyvern 6.3 m tall; `Dragon.KINDS`
  `"scale"` shrinks them to ~4.6 / 5 / 2.8 m in play). `assets/models/dragons/*.glb` also carry baked Idle /
  Flap(Swim) / Roar clips that the game ignores; full 4K FBX/GLB and the source sculpts are outside the repo.
  **No baked animation in play**: like the lion, `Dragon.pose` turns every bone from its rest each frame from the
  hero's state (`Anim.pose` hands it any rig with the `"dragon"` meta, local hero and co-op puppet alike): breathing
  and looking about; a diagonal trot (quad, serpent) or striding run (biped) on the hero's `phase` (the rig's
  `stride` meta slows it for long legs), bob/sway/lean, the serpent undulating head to tail; wings folded at rest,
  half open and beating at a sprint (`_wing(P, bone, lower, back)`); the **tail** always moving and more than the
  Demon's (a wag down the chain into an S, speed and size drifting on slow noise, lifted at a run, swinging with
  the stride, a flick or curl every `FLICK_EVERY` s, a lash when hit). The **basic attack** is the hero's three-swipe
  combo: `swipe1` a foreclaw rake (the wyvern's wing claw), `swipe2` a lunging bite (jaw snaps on the impact frame),
  `swipe3` a full spin sweeping the tail round (the finisher's 181° arc); any other attack style plays a roar with
  wings flared, so a future skill animates before it has a pose. Block = hunkered behind the wings (the serpent
  coils), death = it rolls onto its side (`own_death` meta). Footfalls `<kind>_step` and the wyvern's `wyvern_flap`
  play where the body is. The hero side: `Hero.is_dragon()`; no starting weapon, damage from `Data.CLASSES`
  `"claws"`/`"claw_speed"` (`Data.unarmed`) when nothing is equipped (a found weapon still counts, unseen: grips,
  shield mount and amulet hang off a hidden node in `J`), `Hero.reach` = `Dragon.reach`, `radius` from `KINDS`, no
  sword trail. **Adding skills**: Data.SKILLS entries with `"cls": "wyrm"` (etc.) and an `aim`, then handle them in
  `DragonSkills` (`cast`/`impact`/...), effects in a `DragonFx` added to `SkillFx.play`, a pose per new style in
  `Dragon.pose`'s attack `match`, `SKILL_SHOW` entries for the picker. Class picker: `ClassStage.CLASSES` spreads
  the three round the ring (never side by side, wrap included), `Dragon.stage_scale`/`stage_yaw` shrink and turn
  them on their plinths (and on the title's Continue dais), banner emblem 7 (claw marks), signature "Tail Spin".
  Sounds: `tools/audio/dragon_sfx.py` derives `<kind>_roar/step/claw/bite/tail`, `death_<kind>` and `wyvern_flap`
  from the game's own recordings (replace any with an ElevenLabs take later under the same name). Test:
  `tools/dragon_test.gd` (`--fixed-fps 60`).
  **The Frost Serpent** (jj, 2026-11-04) is re-rigged (`tools/blender/dragons/rechain_serpent.py`: 12 tail, 6 spine
  and 7 neck vertebrae down the body's measured centreline, the old body weights handed to them) and posed by its own
  `scripts/serpent_body.gd` `SerpentBody` (Dragon.pose hands it over): a lizard's diagonal gait with each foot planted
  and swept back in a straight line (`STANCE`; its `stride` 2.3 runs the phase at its short legs' pace), the body
  swimming with the gait and curving into turns, the head held on course, a spring-chain tail (`TAIL_K`) that lags,
  drags in turns, flicks and lashes, breathing, looking about, weight shifts and cold breaths from its nostrils. Its
  skill **Frost Breath** (`frost_breath`, style `"breath"`: the neck lowered, head thrust out, jaws wide; damage ticks
  in `DragonSkills.update` through SkillSpec's cone and chill) and its **block** (coiled round itself inside a clear
  Meshy ice shell, `assets/models/fx/frost/ice_shell.glb`, that grows as the guard rises and shatters into its
  fractured pieces when it drops) are `scripts/serpent_fx.gd` `SerpentFx`. **The Storm Wyvern** (jj): Storm Arc (see
  ArcFx), its dodge a flight (`Dodge.pose`: crouch, a climb of `Dodge.FLY_H` on beating wings by the rig's `fly`
  meta, a landing with a gust of dust), its block the wings wrapped round it like a cloak, the wings swaying with the
  stride and roused now and then at rest, a bigger tail swinging wide in turns. Previews: `RANGE_CLASS=serpent|wyvern
  ... tools/fire_range.gd -- out game|anim grass frost_breath|storm_arc|block|roll` (`Game.test_block` holds the guard).
- **The Wraith's body**: the Meshy horned, chained wraith (concept D) on the shared mocap system
  (`Wraith.build_mocap`, `assets/models/wraith_mocap.glb`; falls back to the code-built robe without it). He has no
  legs and never walks: `tools/blender/wraith/prep_wraith_mocap.py` cuts the skeletal legs and feet out of the mesh
  (what sat within reach of the leg bones, plus the scraps), hangs the robe below the hips on six cloth panels of
  three bones (hA..hF, from the hips only, no leg weights) and the wrist shackle chains on two more (hG, hH, from the
  hands), rebinds the sleeve rags and chain links Meshy had tied to the legs onto the arms (weights diffused edge by
  edge from the arm-bound vertices), and writes vertex colour R = down the robe. Clips: Meshy's idle, punches, casts,
  scream, hit, dodge (root motion taken out) plus clips the script makes from the idle: `combat_idle` (the claws
  raised and forward; Meshy's boxer's stance is dropped), `float` / `float_combat` (the arms eased back, trailing)
  and `death` (rears up, arms flung wide and head back, then the head drops and the arms sag). Rebuild: `blender -b
  --python tools/blender/wraith/prep_wraith_mocap.py -- rigged.glb out.glb 45000 clips_a.glb clips_b.glb`, then
  `godot --headless --import`. The glide is `KnightMocapRig`'s **float mode** (`float_mode`, set by `Wraith.build_mocap`
  with `hover` = `Wraith.HOVER`): the blend spaces go idle -> float by ground speed (`Wraith.FLOAT_SPEED`, clips never
  retimed), and `_float` leans the body into its travel (`FLOAT_LEAN`, more while accelerating, pivoting at the hips
  `FLOAT_PIVOT`), banks into turns (`FLOAT_BANK`), lifts it a little at speed and bobs it. `_sway_robe` (in place of
  the hair sim) swings the panels toward the push of the air he moves through (the ones behind stream out and back,
  the front ones press in a little, a turn drags them round, gusts drift them at rest, a hit kicks them, lower bones
  looser so a panel curves instead of turning like a board) and the wrist chains as pendulums that always hang from
  the hands. Death: the clip's rear-up, then the rig sinks him into the ground (`death_t`) while the spectral
  materials dissolve (`phase_amt`, meta `spectral_mats`), the eyes flare and go out (`eye_light`) and the hem mist
  stops (`hem_mist`); all reset on revive. `Hero._hover` and the hero's death tilt leave the mocap wraith alone
  (`Hero._floats`). `scripts/wraith_mocap.gdshader`: matte Meshy textures, the cyan light in the tears, a rim, the
  hem fraying into mist (R + noise, cut away with a glowing edge), the robe's inside a dark hollow (back faces).
  Preview: `tools/mocap_knight_clip.gd -- outdir idle|run|turn|tour|attack|block 34|side|front|close|game frames wraith
  [relaxed]`.
- **The Wraith's skills** (`scripts/wraith_skills.gd` `WraithSkills`, effects `scripts/wraith_fx.gd`, tuning in
  `Data.SKILLS`; six on Q E R F G V): Spectral Rend (Q: lunges at the foe ahead, two claw rakes, souls heal), Soul
  Siphon (E: a tether into one foe for 2.5 s that drains, heals and slows; it holds while he fights on), Shadowstep (R:
  mist to the cursor, a spinning strike on landing, `Hero.veil_t` = mist for a moment, blows pass through; the shade
  left behind collapses), Haunting Grasp (F: spectral hands out of the ground at the cursor, pull in and hold),
  Phantom Assault (G, level 14: three afterimages streak through the foes ahead in a fan, then his own strike) and
  Eternal Night (V, level 18, the ultimate: rise, scream, hang in the dark, fall; four attacks chained by
  `_update_night`, +40% damage after). Each skill is a whole-body clip of his (`Wraith.SHOTS`: style -> clip and the
  attack progress -> clip seconds keys; `Knight.build_mocap` opts `"shots"` and `KnightMocapRig.shots` hand the rig's
  one shot node whichever style is playing; the blow lands on `Anim.impact_at` of its style): claw2 for the rend,
  cast2's reach for the tether, the dodge's spin for the step, the slam for the grasp and the night's fall, claw1 for
  the phantoms, cast and scream for the night. Skill state lives in `Hero.wr` (the tether's victim and ticks, the
  night's stage; `WraithSkills.clear`); what is seen is fx events (`Hero.fx`) that `WraithFx.play` draws and
  `WraithFx.update` keeps going (`Hero.fxs`: the tether node following its victim, the phantoms' flight, the night's
  dark ramping with the rise, the ghosts wheeling, the claws), on his puppet for partners too. Afterimages are `WraithFx.afterimage`: the body's armature duplicated with
  its bone poses, under copies of the spectral materials with `ghost` on. The spectral claws (`WraithFx.claws`) sit
  on the hand bones (BoneAttachment3D, in the armature's centimetres) and grow out for the rakes. Soul Siphon's slow
  is `Enemy.slow` (rides the stun RPC as a negative time). Old saves' bindings of reap/wail/shade/host become
  rend/siphon/step/grasp (`WraithSkills.OLD_IDS`, `migrate_binds` in `Hero.from_save`); the talent ids (and their
  painted icons) were kept, their effects now name the new skills. `tools/wraith_test.gd` exercises every skill;
  `tools/wraith_skills_clip.gd -- outdir [skill|all] [close|game]` renders frames of each (needs xvfb and
  `--fixed-fps 30`; the Low preset and no shadows, since software GL is slow).
- **The Demon's body**: the Meshy "Magma Brute" (concept A: cracked charcoal skin with lava in the cracks, swept
  horns, bat wings, a spiked tail, a loincloth, hooves; 2.2 m as modelled, `Demon.SCALE` 1.08 on top) on the shared
  mocap system (`Demon.build_mocap`, `assets/models/demon_mocap.glb`; without it the old knight-based fiend,
  `Demon.body_gear`). `tools/blender/demon/prep_demon_mocap.py` merges and renames the Meshy library clips (ids in
  the commit: Idle, Slow Orc Walk, Run 2, Combat Idle, Male Head-down Charge, Punch Forward with Both Fists, Charged
  Ground Slam, Charged Axe Chop, Grip and Throw Down, Crouch Charge and Throw, Charged Spell Cast, Zombie Scream, Angry
  Ground Stomp, Hit Reaction, Falling Down -> idle, walk, run, combat_idle, charge, claw, slam, smash, grab_throw,
  hurl, cast, roar, stomp, hit, death), trims the long ones to their useful part, takes the root motion out (as the
  Wraith's), welds and decimates to 50k, and re-bones what Meshy had tied to the arms and legs: each wing on its own
  chain from Spine01 (`wL1`/`wR1` the root on the back, `w?2` the arm up to the top joint, `w?3` the leading finger
  out to the outer tip, `w?4` the lower finger; the membrane skinned to the nearest finger bones, blending into
  the spine along the flank so the join never tears; the thread Meshy left under each bottom tip is cut), the tail
  on `tail1..tail7` along its own centreline (geodesic from the root, so the curl is followed; the root blends into
  the hips), the loincloth's front flap on the cloth panel `hA1..3` from the hips (a back flap would be `hB`).
  Vertex colour R = along the tail, G = wing membrane. Rebuild: `blender -b --python
  tools/blender/demon/prep_demon_mocap.py -- rigged.glb assets/models/demon_mocap.glb 50000 clips_a.glb clips_b.glb
  [--debug prefix]` (the debug renders colour the regions), then `godot --headless --import`; it prints the clips'
  ground speeds (`Demon.WALK_SPEED`/`RUN_SPEED`/`CHARGE_SPEED` are the blend points; the charge clip is his sprint).
  Meshy's Slow Orc Walk is bow-legged and hunched, so it only shows at a crawl: the run is in the blend again at
  `Demon.WALK_BLEND` (2.6 m/s), and `DemonMocapRig._rate` plays the run at his real ground speed (0.77x at 4.8 m/s,
  heavy, no sliding). The rig eases the speed the clips are blended by over ~0.3 s when he sets off (`ease_speed`:
  standing crossfades into the stride; it drops at once when he stops) and lags the hero's snap turn on the body
  (`_vis_yaw`, visual only, up to 0.6 rad; none while he attacks or casts, so the body shows the aim at once), so a start is a heavy push-off rather than a snap.
  `scripts/demon_mocap_rig.gd` (`Knight.build_mocap` opts `"script"`, `"scale"`) lays the moving parts over the clips
  every frame, all springs: the wings fold and breathe at rest, half open and flex with the walk, spread and sweep back
  at a run, fly wide for a cast or a roar, beat on the slams and stomps, sag in death (`_wings`: fold / lift / sweep
  per side, turns in the rig frame through the bones' rest conj like the hair locks); the tail is a heavy chain
  (`_tail`: it hangs low (`TAIL_LIFT`, the outer half just over the ground) and wags the whole time: a wag
  oscillator (`wag_ph`) whose speed, size and axis drift on slow noise, the root swaying moderately and the swing
  growing and lagging down the chain into an S at the tip, its vertical part only ever lifting from the hang;
  every few seconds the tip curls or flicks (`flick_t`); moving, the stride's sway (phased to the detected
  footfalls: `_gait` is pulled to the foot that lands) joins the wag, the modelled curl straightens out behind him
  (measured in `setup`, `tail_bend_y/p`, undone by `straight`) and the whole tail springs up on an underdamped
  lift (`tail_up`, overshooting as he sets off, `LIFT_W` sharing it down the chain; the charge highest), bouncing
  on footfalls; it swings out opposite a turn, lashes when an attack starts, never pitches below its rest hang nor
  swings its root between the legs, and goes limp dead); the flap is kicked by the stride and
  never swings into the legs (`_cloth`); `_footfalls` counts each foot landing (`thump`, which `Demon.animate`
  turns into a small `add_shake` for the local hero). His moves are whole-body clips through `Demon.SHOTS` (style -> clip and
  progress keys: the combo swipe1/2/3 = claw / smash / slam, Space's over / back / thrust = smash / claw / hurl, and
  his skills' styles, see "The Demon's skills"). The death is the
  clip's fall (meta `own_death`: `Hero._own_death` skips the death tilt), then the rig cools the lava (shader
  `cool`, meta `demon_mats`) and lights the embers (meta `death_embers`); revive resets. `scripts/demon_mocap.gdshader`:
  Meshy's textures matte (roughness 0.9, no metal), the hot orange texels found as the cracks and lit as magma that
  breathes, `glow` from `Demon.animate` (flares through attacks and casts, pulses with `hit_t`, more under the wrath's
  buff), `wrath` = the white heat of Wrath of the Pit, `phase_amt` = a dithered shadow (unused now). The weapon grips sit lower in his big fists and are scaled 1.35x (`Demon.build_mocap`).
  Preview: `tools/mocap_knight_clip.gd -- outdir demontour close|closeback|game|side|back 1020 demon` (idle, walk,
  run, a turn, every clip, a hit, death; `--fixed-fps 30`); `demontail tail|game 750 demon` is the tail alone (8 s
  standing, walk, run, charge, a turn, a swing; the `tail` view is a rear three-quarter); `demonsteps 34 270 demon`
  is the first steps (stand, run, stop, run into a turn, stop).
- **The Demon's skills** (`scripts/demon_skills.gd` `DemonSkills`, tuning in `Data.SKILLS` with a `"pvp"` dict per
  skill and a `"role"`; overhauled Nov 2026 so each has one job, PvP first; plan doc "demon kit overhaul"; merged
  with jj's Path of Exile skill rule: Molten Fists, Fault of the Pit and Brimstone Hurl are main skills with no
  cooldown, their `"use"` time the limit; the charge, the grip and the wrath keep cooldowns as utility): Molten
  Fists (Q, burst finisher: jj's heavy blow on the skill format, 2 s with the blow at 1.5 s, dodge cancels it,
  `DemonSkills._fists` through `SkillSpec.targets` and `_strike`; a **Branded** foe takes +30% (PvP +20%, the
  strike's `"mult"`) and loses the Brand), Infernal
  Charge (E, engage/mobility: stages `icharge_wind` (paws; the exact path burns on the ground for everyone) ->
  `icharge` (the run, `CHARGE_SPEED`, up to `CHARGE_RANGE`, walls cut it) -> `icharge_skid` (the punishable stop);
  bowls lesser monsters aside, **stops on the first champion, boss or player**: staggered and Branded; no lava trail
  now), Fault of the Pit (R, id `cslam`, area control, no cooldown: `"use"` 2.2 s, `"power"` 0.95 = 1.2x Molten Fists'
  damage per second as a heavy skill, `tools/skill_dps.gd` over 12 casts at level 20; the slam
  splits a line `FAULT_LEN` across the aim
  `FAULT_AHEAD` out; after `FAULT_WARN` it erupts (damage, thrown up, Branded) and stays molten `FAULT_LIFE` s
  burning and slowing; no hard wall), Brimstone Hurl (F, ranged pressure, no cooldown: `"use"` 1.6 s, `"power"` 0.43
  = 0.9x the fists' as an area skill; the descriptions give the tuned numbers; throws alternate `hurl`/`hurl2`;
  landing after `HURL_FLIGHT` + `HURL_PER_M`/m under a mark everyone sees; core `HURL_CORE` full + Brand, edge
  `HURL_R` half, `SHARDS` burning shards; no pool), Hellgrip (G, pick/pull: `grip_throw` flings a chain skillshot
  `CHAIN_LEN` at `CHAIN_SPEED`, the first body in its line is hooked (monsters block it) -> `grip_haul` drags it to
  `HOLD_IN` in front of him (bosses, Sloths and monsters a partner's game doesn't own drag him instead) -> `grip`
  hoists and smashes; a miss hauls back empty; Branded = `CHAIN_REFUND` of the cooldown back), Wrath of the Pit (V,
  defensive counter: `crucible` (the kneel clip, up to `CRUCIBLE_MAX` s, V again after `CRUCIBLE_MIN` ends it,
  `DemonSkills.recast` from `Hero.use_skill`): `Hero.take_hit` asks `DemonSkills.absorb` (takes `CRUCIBLE_DR`,
  stores what gets through as heat), nothing stuns or moves him (`PvpStatus.unstoppable` too) -> `wrath_roar`, the
  eruption: damage + `HEAT_SHARE` of the heat (capped `HEAT_CAP` of his life), terror -> `PIT_DUR` s of Pit-born:
  +40% (PvP +20%) and meteors; in PvP at most `"meteors"` fall on players, slower, under a mark). Stages chain
  through `DemonSkills.stage_done` (called by `Hero._update_attack` when a Demon attack ends) and `next_style`.
  Every blow goes through `DemonSkills._hit` (the PvP share on a player's stand-in; a skill on the skill format
  through `_strike`: `SkillSpec.strike` on a monster, `_hit` and a server-capped burn on a player), statuses through `_cc`
  (monsters: stun/slow; players: `PvpStatus.send`). The Brand: `DemonSkills.brand/branded` (`h.dm["brand"]`), seen
  through the fx event `("fists", "brand")` -> `BrandFx` (`scripts/brand_fx.gd`: the sigil under the feet, a brand
  over the head, motes, a light; on a player through `"pid"`). Clips through `Demon.SHOTS` (the new styles above use
  the clips `stomp`, `skid`, `hurl2`, `chain`, `kneel`, added to `demon_mocap.glb` by `prep_demon_mocap.py` from
  Meshy clips 531/239/421/365); `Anim.impact_at` has their frames (0.99 = no blow), `Net.STYLES` the styles;
  `DemonMocapRig._wings` poses the wings per stage (the Crucible's cocoon, the skid's brake, the eruption) and
  `_cooling` takes the Crucible's crust (rig meta `crust`). Old saves' bindings of hellclaw/summon/phase/pact become
  fists/icharge/cslam/hurl (`DemonSkills.OLD_IDS`); the talent ids were kept (`trail_dur` = the fault lasts longer,
  `hurl_twin` = Twin Boulders, a second boulder `TWIN_GAP` beside the first). `tools/demon_test.gd` exercises
  every skill (`--fixed-fps 60`; jj's wind-up and dodge cancel too);
  `tools/demon_pvp_test.gd` (server + Demon + target) checks every status reaches a player through the server and
  the diminishing returns; `tools/demon_skills_clip.gd -- outdir [skill|all] [close|game]` renders frames of each.
- **The Demon's skill looks** (each skill its own script, none of it Molten Fists' hellfire; built from `DemonKitFx`
  (`demon_kit_fx.gd`); `DemonFx` routes the events and keeps the grip's hoist, Pit-born's white heat and the meteors):
  **Hellrunner** `DemonChargeFx` (the ground crushed where he paws, a scorched furrow burning along the exact path,
  the Meshy ram's skull as a flickering ghost of fire leading him, ash and sparks at every hoofstrike, a shock on the
  champion that stops him, a ploughed skid), `DemonFaultFx` (the slam's crush, a gouge pulsing hotter through the
  warning, then the Meshy lava fissure rising along the line with the Meshy obsidian plates tilting up beside it, dust,
  simulated steam boiling off it while it stays molten, everything sinking back at the end), **Shatterstone**
  `DemonHurlFx` (the ground torn up, the Meshy boulder tumbling on its arc dragging the comet sim and leaving soot in
  the air, its landing mark closing in; the landing: the same rock cut into Voronoi pieces with molten faces, the
  impact sim, a Meshy-painted crater, shards skittering out; `DemonHurlFx.impact` is the wrath's meteors' landing too,
  with the Meshy meteorite), **Chain of the Pit** `DemonChainFx` (the Meshy forged chain laid section by section, hot
  near his arm, the Meshy iron claw, sparks grinding off it, the smash into the ground in dust), **Crucible**
  `DemonCrucibleFx` (the Meshy obsidian cocoon growing up round him, its veins and the ground under him glowing with
  every blow stored, then bursting outward in its Voronoi pieces with the blast sim, a crater and a shock ring).
  The pieces (`DemonKitFx`): **simulated smoke** (`smoke(root, pos, kind, size, dur, loop, tint, axis)`, size = the
  cloud's width in metres): Mantaflow sims rendered in Cycles by `tools/blender/fx/smoke_flipbook.py`
  (`SMOKE_KIND=impact|comet|steam|ash|blast blender -b --python ... -- outdir res frames px samples`; `ONLY_FRAMES=1,5,9`
  renders just those for a quick look) as premultiplied EXR (fire is light added on top, even with no smoke) and packed
  by `python3 tools/fx_smokebook.py outdir assets/textures/fx/demon/smoke_<kind>.png <cell px>` (rolls the light off,
  fades every frame out at its edges, cross-fades a loop's extra frames into its start, prints the `BOOKS` line); the
  books import lossless (`compress/mode=0`: lossy WebP rewrites the colour under clear pixels in 16 px blocks, which
  premultiplied blending adds to the scene as pale boxes) with `fix_alpha_border` off and mipmaps on. Impact, ash and blast were rendered from the game camera's
  own 44 degrees and are held facing the camera (`SMOKE_SHADER` mode 1, anchored where the sim's origin sits in the
  frame and drawn nearer the camera so the cloud's near half doesn't sink into the ground); steam stands upright
  (mode 0); the comet lies along the rock's flight (mode 2, `aim_smoke`). Preview one in-engine:
  `tools/smoke_book_shot.gd -- outprefix kind [size] [secs]` (xvfb, `--fixed-fps 30`, through `_late.gd`). Flow
  particles' size is in simulation cells (below 1 they leave speckles); the Principled Volume multiplies Density by
  the density grid itself, and its colour grid comes weighted by density, so the script feeds a constant density and
  colour per kind; too fast a dissolve or turbulence on the flame's source puts a fire out. Any premultiplied or
  additive card needs `fog_disabled`: Godot's fog paints its clear pixels too (a milky sheet over the card). The
  books were lit like daylight, so in the shader whatever is brighter than lit smoke can be counts as fire: the smoke
  takes `SMOKE_LIGHT[kind]` of it (the dusk), the fire `FIRE_GAIN[kind]`; camera-facing cards are pushed toward the
  camera far enough to clear the ground for cameras down to 30 degrees, upright ones fade at their sides. The
  Fault's Meshy fissure is a square tile cut per pixel to a jagged band round its crack (`DemonFaultFx.CRACK_SHADER`);
  shock rings show only as heat haze (High and up, Forward+), never as a coloured band. Captures: the Compatibility
  renderer is what `--rendering-driver opengl3` shows (as the web build does); Forward+ in the cloud workspace needs
  `apt-get install mesa-vulkan-drivers` (lavapipe) and `--rendering-driver vulkan`. `tools/demon_skills_clip.gd` takes
  a skill, `all` or a list (`hurl,wrath`) and `close|game` (the game view at zoom 0.9). **Ground marks**
  (`decal`: Meshy-painted crater / furrow / crush with glow masks made by `tools/fx_glow_mask.py`, on a mesh laid
  over the terrain, since the Compatibility renderer (web, OpenGL fallback) draws no Decals; `set_mark_glow`), **real pieces**
  (`pieces`: Meshy models cut into Voronoi chunks by `tools/blender/fx/fracture_rock.py`, thrown, bouncing, cooling),
  `sparks`, `clods`, landing marks, shock rings, lights; the Meshy props in `assets/models/fx/demon/`.
- **PvP crowd control** (`scripts/pvp_status.gd` `PvpStatus`): the caster's game sends a status for a player's
  stand-in (`PvpStatus.send` -> `Net.sv_pvp_status`), the server checks it like damage (`Battlegrounds.pvp_status`:
  raid on, both alive, within 30 m; it sets the drag's end point and the fear's source itself, caps burns and scales
  them like a hit: `PVP_MULT` and Blaine's class against class `Data.pvp_scale`) and
  applies **diminishing returns** to hard kinds (`HARD`: stagger, knockup, pull, fear; within `DR_WINDOW` the second
  lasts half, the third is refused and opens `DR_IMMUNE` s of immunity; `MAX_SECS` cap; soft kinds `SOFT_MAX`), then
  `Net.cl_pvp_status` to the victim only; `PvpStatus.apply` / `update` (from `Hero._process`, `Hero.cc`) do it on
  his game (a roll's i-frames, mist and the Crucible ignore hard kinds; tenacity, `Hero.cc_k`, shortens the hard kinds
  and slows). Only the Demon's skills send it so far
  (Doug's slips and pies take their own path, `Net.send_pvp_effect`: a zero-damage hit, no diminishing returns);
  another class's crowd control stays PvE-only until reviewed for PvP. A tool script that hits "Identifier not found:
  Sfx" in a fresh container runs through `tools/_late.gd -- res://tools/<script>.gd [args]` (loads it after the
  autoloads).
- **Molten Fists' look, "Hellbrand"** (`scripts/demon_fists_fx.gd` `DemonFistsFx`, on the Demon's Q; the gameplay in
  `DemonSkills` is unchanged): the "cast" event starts the gather (hellfire gauntlets on both fists, the body shader's
  `brand` running the magma down his arms, a light between his hands, crimson motes pulled in, his sigil drawing
  itself under him), the "impact" event the release (a flash at the fists, the rift tearing open in a wedge with a
  light sweeping along it, a crescent of fire with heat haze from High, obsidian fangs bursting up near to far and
  shattering into burning fragments, fires out of the fissures, smoke, embers, earth; each foe struck gets a molten
  flash, a splash, fire on its body and a visual stagger, `fists_stag`). State in `h.fxs["fists"]`. The clip is
  re-timed in `Demon.SHOTS` "fists" (snaps into the chamber and holds it; the impact frame unchanged) and
  `DemonMocapRig._fists_pose` rears him back and drives him down over it. Built from **`InfernalFx`**
  (`scripts/infernal_fx.gd`): the Demon's reusable visual language (palette OBSIDIAN/CRIMSON/MOLTEN/WHITEHOT, the
  sigil, rift, obsidian shard, wave, smoke, glow and haze shaders, noise textures made in code, `particles(...)` from
  a dictionary, budgets by `tier(game)`; `force_tier` for previews). Preview: `tools/demon_fists_clip.gd -- outdir
  close|front|game|fight|fire [tier] [secs] [casts]` (xvfb, `--fixed-fps 30`).
- **Fire** (`scripts/fire_fx.gd` `FireFx`): every fire in the game is simulated fire. `Props.fire(..., kind)` builds
  it (the old particle fire is `Props.fire_legacy`; `Props.use_legacy_fire` switches back for comparisons). Kinds
  (`FireFx.PRESETS`): torch, candle, campfire, bonfire, brazier, building, ground, magic, weapon, burning; each a
  flipbook book, flame rate and life, size, back / main / core layers, embers, sparks, smoke, haze and light. Flames
  are particles playing a flipbook of a Blender Mantaflow fire (`InfernalFx` `FLIPFIRE_SHADER`), each starting on
  its own frame and mirrored at random, so nothing loops visibly; overlapping flames share their brightness so a fire
  never sums to white. Books in `assets/textures/fx/`: `fire_body.png` (8 x 8), `fire_tongue.png` and
  `fire_spread.png` (6 x 6). Fire lights carry meta `fire` and flicker like real fire in `Game`'s flicker loop; they
  fade out past ~40 m. The bonfire window plays the body book too (`UI.FIRE_FLIP_SHADER`). Make a book:
  `FIRE_KIND=body|tongue|spread blender -b --python tools/blender/fx/fire_flipbook.py -- outdir res frames px`
  (Blender 4.5; ~2 min a 3-frame test, 20-60 min a full book on the cloud's 2 cores; `RENDER_ONLY=1` reuses the
  bake), then `bash tools/fx_flipbook.sh outdir assets/textures/fx/fire_<kind>.png first cell tile`. Settings that
  worked and mistakes to avoid are in the project doc "fire pipeline". Comparison: `tools/fire_compare.gd -- outdir
  new|old close|wide|game frames`.
- **Drain Life** (Warlock Q) is a channel, not an attack: `hero.drain_t` runs while Q is held (minimum 1 s), ticks every 0.3 s in `WarlockSkills.update_drain` (all of Drain Life is in `warlock_skills.gd`), and the beams are drawn after `Anim.pose` in `_draw_drain`. Any move, target click or other skill calls `end_drain()`, which also clears the victims' green rim (`Enemy.set_drained`), the ground sigil and the looping hum (`Sfx.start_loop`). Drain ticks set `Enemy.dmg_tint` around `take_damage` for green numbers and no blood. The beams, sigil, hand light and hum are the `"drain"` fx events' effect (`WarlockFx.play`, state in `Hero.fxs["drain"]`, drawn by `WarlockFx.update` after the pose on the caster and on his puppet; `"start"`, `"victims"` when the fork set changes, `"tick"`, `"end"`), so partners see the beam on him too.
- **King Grubb** (Act I boss, `hoard.gd`) is host-authoritative. Every visible part of the fight (piles, bombs, burst
  sacks, shouts, a grabber's `carry_on`/`carry_off`) is an Enemy fx event string handled in `Hoard.fx`, so partners see it;
  damage, healing and gold happen only on the host. Grabbers reach the fight through `Enemy.hoard` (`Hoard.steer`).
- **Sculpted bodies** (`Sculpt`): a monster with `"model"` in `Data.ENEMIES` is built by `Goblin.build`. The body is one
  skinned mesh made once per kind (about 0.5 s) and cached; each limb is its own group so it doesn't melt into the torso.
  Its shader textures in rest space from UV/UV2 (skinned VERTEX moves). Rigid bits (teeth, claws, gold, cloth) stay
  per-joint meshes. `knight_rig.gd` copies the joints onto the bones (position, rotation and scale).
- **Blender assets** (King Grubb): the model was generated with Meshy (a Meshy concept image, then image-to-3D),
  decimated to ~80k triangles and rigged by `tools/blender/grubb_mutant.py` (bones on his anatomy named like the
  game's joints; distance weights plus fixed regions for the crowns, belly, the three gold sacks and the key). The
  `.blend` source (with the full-detail mesh) is `~/Documents/Blender/Game Factory/sources/grubb.blend`, exports go
  to `exports/`; never put a `.blend` inside the project (Godot 4.3 imports `.blend` files by launching Blender, which
  hangs headless imports). The joint layout in the script must match `Goblin.MUTANT["layout"]` (Godot axes: x, z, -y).
  `Goblin._imported` re-binds the glb's skin onto the game's skeleton by bone name, so `Anim.pose` and
  `Goblin.after_pose` drive it; the `held` meta damps his shoulder swings (his gut and arms tear the skin otherwise).
  Burst sacks are hidden by scaling their bones to ~0. Without the file he falls back to the code-sculpted king.
  The gnome Warlock works the same way (`tools/blender/gnome_warlock.py`, `Warlock.GNOME`, source
  `sources/gnome_warlock.blend`): `Goblin.imported_rig` builds the skeleton from a layout, and its `aim` turns an A-pose
  limb's rest down the limb so the hero's animation hangs it naturally. A player model also needs `grip_r`/`grip_l`/
  `mount_l`/`chest` anchors (weapons, shields, amulets; scaled for his size) and a `stride` meta (short legs step faster).
  `tools/gnome_anim.gd` renders a contact sheet of his motion.
  His look extras live in `warlock.gd`: purple cloak and green glowing hat horns (`cloak_mat`, a vertex mask on the hat),
  horn-tip smoke (`_horn_smoke`), the pixie-dust trail while moving (`_dust_trail`, world-space GPU particles),
  the hopping hat and the weapon held high when running (`_gnome_sway`). `tools/gnome_run.gd` and
  `tools/gnome_clip.gd` (movie writer) preview them.
  `tools/model_preview.gd` stages any candidate .glb in the vault for screenshots; `tools/goblin_anim.gd` renders a
  contact sheet of his motion. `tools/blender/grubb.py` (+ `grubb_gear.py`) is the earlier fully scripted Blender
  build, kept as a reference; its export isn't used. Godot's `.import` files and extracted textures under
  `assets/models/` are git-ignored (regenerated on import); run `godot --headless --editor --quit` after re-exporting.
  Since those `.import` files are made fresh, the textures take `project.godot`'s `[importer_defaults] texture`:
  **lossy WebP at quality 0.9, 3D detection off, full size** (the default was lossless, 490 MB of the old 618 MB pack;
  q0.9 is ~41 dB against the source JPGs, which are lossy already). The nightly of 2026-11-03 capped them at 1024 px
  and q0.75 (541 -> 409 MiB); jj undid it the same day: "when playing on ultra there should be full everything", and
  an import can't differ by preset, so every preset gets the full textures. A checkout imported before keeps its old
  `.import` files until they're remade; deleting only the
  `.import` files is wrong (the textures come back without mipmaps: only the glTF importer's own extraction turns them
  on), so re-extract: `git clean -fX assets/models && godot --headless --import`. Give a new texture with a committed
  `.import` the same settings when it
  is a JPG-sourced 3D texture (like `assets/textures/plague/coat_*.jpg`); keep UI and cut-out PNGs lossless.
- **Knight (no armour)** is a Meshy model (white shirt with a red crusader cross, shorts, leather sandals,
  long hair): `assets/models/knight_meshy.glb`, built by `Knight.build_meshy` on `Knight.MESHY_LAYOUT`. The hero
  wears it while the armour slot is empty (`Hero._wants_meshy`); `refresh_gear` swaps to the procedural armoured
  body when armour goes on. To rebuild it: `blender -b --python tools/blender/knight/rig_meshy_knight.py --
  <meshy.glb> <out.glb> layout.json --cross` (re-poses the A-pose to arms-down, skins by distance, splits the hair
  into five locks hA..hE of three bones, paints the cross, adds the sandals), then
  `python3 tools/blender/knight/layout_to_gd.py layout.json` rewrites the layout block in `knight.gd`. The hair
  locks are simulated in `knight_rig.gd` `_sway_hair` (springs per bone; run, footfall jolt, turning, wind).
  The knight's run is `Anim` with the `gait` meta `"knight"` (front-to-back arm pump). Preview tools:
  `tools/knight_clip.gd` (`-- outdir [side|back|close] [armored] [helm]`), `tools/gait_preview.gd`; test `tools/meshy_knight_test.gd`.
- **Knight (armour on)** is the Meshy crusader (enclosed great helm, spiked plate over mail, dark surcoat with a
  faded red cross, sword in its scabbard on the left hip, long tattered cloak): `assets/models/knight_armored.glb`,
  `Knight.build_meshy(true)` on `Knight.ARMORED_LAYOUT`. `Hero._knight_body()` picks "plain" (no armour), "armored"
  (any body armour) or "" (the procedural body, only without the glb files); the rig's `meshy` meta holds which.
  He always wears his own helm: helm items keep their stats but aren't drawn on him (`Hero.refresh_gear`), and there
  is no show/hide helm button. Rebuild from the Meshy glb: `blender -b --python tools/blender/knight/prep_crusader.py
  -- meshy.glb dec.glb --tris 70000 [--grid prefix]` (decimate, 1.8 m, feet on the ground; the grid renders are for
  placing joints), then `blender -b --python tools/blender/knight/rig_crusader_knight.py -- dec.glb out.glb layout.json
  [--debug prefix]` and `python3 tools/blender/knight/layout_to_gd.py layout.json armored`. The rig script heat-skins a
  voxel-remeshed watertight proxy (Meshy's mesh isn't watertight) and transfers the weights; the helm rides the head,
  the sword and the cloth between the legs ride the hips, the arms (and their spikes) only their own arm; the cloak
  (found by the metallic map and where it hangs) hangs on three panels of three bones (hA..hC) that `knight_rig.gd`
  `_sway_hair` swings; faces Meshy fused between parts that move apart (cloak/leg, cloak/arm, arm/hips) are cut, and
  cloak shreds left beside the A-pose arms are dropped. `--debug` renders the A-pose coloured by main bone.
  The earlier armoured knight (bare head, red tabard) is kept as `knight_statue.glb` for the arena statues.
  **Shield arm** (any mocap body): with a shield on (`Hero.refresh_gear` sets the rig's `shield` meta) the left arm
  (`KnightMocapRig.SHIELD_ARM`) always takes Anim's pose (`w_shield`): the shield at his side, up across the chest at a
  run, raised to block. The motion capture's empty-handed arm swing left it hanging by his knee and flapping about.
- **Act I trees and grass** (`World.oak_forest`, set by `game.gd` when `difficulty == 0`; A2/A3 keep the old mix): three
  Meshy oaks `assets/models/trees/oakN.glb` (prepared by `tools/blender/prep_tree.py`: trunk on the origin, ~6 m, 1k
  textures) built by `Flora.oak_model(k)` with `MESHY_TREE_SHADER` (wind sway by height, snow/ash, see-through near the
  player) plus the game's leaf clusters (`OAK_LEAVES`); the moor is ~40% oaks with groves off the road. Grass is
  the **living 3D grass** (`scripts/grass.gd` `Grass`, `scripts/grass_field.gd` `GrassField`; Act I's camp, moor and
  fort, i.e. whenever `oak_forest`; since the visual overhaul A2 and A3 too, `World.living_grass`, in the zone's own
  colours, A3's charred by the shader's `ash_amt`; the old blade clumps remain only as the fallback): seven species built in code (`Grass.SPECIES`:
  meadow, tall seed-head grass, tussock, dry straw, moss with clover, broad-leaved weeds, sparse verge grass)
  **modelled in Blender on Meshy textures**: four Meshy botanical sheets (green blades, dry straw, seed heads and
  wildflowers, broad leaves; `meshy.py draw "... laid flat side by side ..." --cutout`, ~6 credits each, the prompts
  are in the commit) are cut by `tools/grass_atlas.py <dir> assets/textures/grass` into `atlas.png` (2048x1024, 32
  cells of 128x512: blades unrolled to the full cell width so they stay opaque, heads/flowers/leaves kept as
  cut-outs; mipmaps on) and `atlas.json`; `blender -b --python tools/blender/grass/build_clumps.py --
  assets/textures/grass/atlas.json assets/models/grass` models each species' clumps (folded blades with a raised
  midrib, sheaths, twists, snapped straw, crossed seed-head cards, leaf rosettes; two variants, two LODs; objects
  `<species>_<variant>_<lod>`) into `assets/models/grass/<species>.glb`. Per vertex: UV = atlas, UV2 = (flex, height
  along the plant), COLOR = (dry, sway phase, lush, 1 blade / 0.5 card). `Grass.glb_mesh` loads them (stripping the
  importer's automatic LODs and tangents, since the `.import` files are git-ignored) and the shader's `textured`
  mode draws them; species without a glb fall back to the code-built clumps (`Grass.mesh`, curved tapered blades).
  `tools/grass_closeup.gd -- out.png [lod] [dist]` renders every species side by side. Mixed by biomes (`Grass.BIOMES`: meadow,
  woodland, dry, verge, trampled, ruins). A zone answers `grass_ground(x, z)` (0 bare .. 1), `grass_height` and
  `grass_biome` (weights; World's: verges by the road, undergrowth near `tree_pts`, dry patches and round the
  Sloths' clearings, trodden in the fort and camp), and `Grass.scatter` fills MultiMesh chunks (`CHUNK` m, per
  instance custom data: shade, dryness, random) in about a second. Colours: `Grass.ACT1` (matched to the painted
  clumps it replaced). The shader bends each blade from its root by the **wind** (global `wind_dir`,
  `wind_strength`, `wind_gust`, `wind_phase`: gust fronts rolling along the wind, sway per clump, flutter;
  `GrassField.WIND` profiles per zone set in `Game._grass_zone`, blended by `set_wind(profile, secs)`, drifting
  on their own) and by **touch**: `GrassField` is a GPU spring simulation following the camera (two ping-pong
  SubViewports, 256 px over 64 m, RG bend / BA velocity in 8 bits; its texture goes to the grass materials,
  `Grass.set_field`, and where it lies is the global `grass_field_rect`);
  every mover from `Game._grass_movers` (hero, partners, monsters, pets, demons) presses a capsule along its real
  path (size from its `radius`, harder when sprinting or dashing, a slow flattening when standing), an attack's
  impact frame (`Anim.impact_at`, so every peer sees it) throws an arc in front (`GrassField.swing`; slams and
  mauls add a ring), and `Fx.ring`/`Fx.holy_slam` (any nova, slam or spell ring) shove a ring
  (`GrassField.impulse(pos, radius, strength)`). Local and cosmetic: no network traffic. Far grass thins by
  shrinking clumps by their random value and LOD0/LOD1 cross-fade per clump (`Grass.FADE`, `LOD_BAND` per
  preset, using the global `grass_cam` so shadow passes agree); density per preset `QUALITY_DENSITY`; grass
  casts shadows only on Ultra, from a shadows-only twin of each near (LOD0) chunk drawn with the LOD1 clump
  (`Grass._shadow_twin`, `SHADOW_STYLE`; made on switching to Ultra, freed below it; nightly 2026-11-03: 14 -> 6 ms). `Grass.apply_quality` updates distances (`Game.apply_quality` skips the 3D grass's
  nodes, meta `grass3d`). Tests: `tools/grass_test.gd` (headless: species, LODs, no painted clumps, field on/off,
  movers, swings, rings, wind); `tools/grass_lab.gd -- outdir [quality] [zoomin]` (needs a display: biome bands,
  scripted walkers that walk, sprint, stop, turn and dash, a big beast, swings, a slam, wind changes; saves frames
  and checks the field lines up and returns fully to rest; Mesa's llvmpipe software renderer, the only one in the
  cloud workspace, tints some clumps in rainbow colours there, so judge colours on a real GPU). Performance from any build:
  `AshenCrown -- --shot out.png --zone wild --god --perf 12 --quality 2 --grassspot` writes `out.txt` (fps, 1% low,
  draw calls, primitives, GPU). The painted clumps (`Flora.GRASS_TOP`, `_camera_card`) are no longer placed;
  `Flora.flower_card` still uses `_camera_card` for the Sunstar Blooms.
  **Sunstar Blooms** (`World._rare_flowers`, Act I only, 3 per moor, 14-34 m off the road, own seed): a glowing
  painted card (`Flora.flower_card`) and a breathing light; picking one (`Game._interact` "flower") gives +50%
  experience for 5 minutes (`Game.xp_bonus_t`, shared with the Experience Shrine; the XP bar counts it down) and is
  synced like shrines. `tools/flower_test.gd` checks the grass kinds and the blooms.
  Previews: `tools/tree_lineup.gd`, `tools/tree_shot.gd`. Meshy 2D: `meshy.py draw --cutout`.
- **Act I monsters** (Meshy): concept image, image-to-3D, decimate to ~20k triangles in `sources/act1_enemies.blend`,
  then `blender -b --python tools/blender/act1/rig_monster.py -- <decimated.glb> <out.glb> layout.json [tex px] [hints]`
  (measures the joints; hints `{"sh_z", "sh_x"}` when a hood or helmet spike fools the neck finder, `"crotch"` (a
  fraction of the height) when a loincloth or skirt hangs between the legs) and
  `python3 tools/blender/act1/layout_to_gd.py <kind> layout.json`. They keep their A-pose (arms aimed down like the
  gnome). Previews: `tools/monster_lineup.gd -- out.png kind...`, `tools/monster_shot.gd` (staged on the moor).
- **The Feral** (`feral.gd`, Act I forest): a Meshy model rigged and animated in Blender (`sources/feral.blend`:
  17 bones, skinned by distance along the body's surface because the forearms touch the knees, IK on the four
  limbs). Unlike the other monsters it plays baked, in-place animations ("crawl", "lunge", "swipe", exported as NLA
  tracks to `assets/models/monsters/feralN.glb`, five models with different rags and skin on the same rig, picked by
  where each spawns, `Feral.variant_at`), timed by `Feral.pose` from the enemy state: the crawl from `phase`,
  the attacks from their progress. Packs of 3-4 cling head-down to oak trunks well off the road
  (`World._feral_packs`, spawn entries with `"perch"`; `Enemy.perch_on`); come within ~10 m and the pack
  skitters down (`_feral_perch`, styles "perch"/"descend" carry it to co-op partners), circles about 4.5 m out,
  and one at a time lunges (`special` "feral_lunge", flying over other monsters), backs off, darts in to claw,
  backs out (`_feral_combat`, `f_state`); the lunge has a 5 s cooldown, and outrun for 6 s (beyond 9 m) the pack
  gives up and goes home, ignoring you for 8 s unless hit (`f_chase`, `f_calm`). `tools/feral_test.gd` checks it.
- **The three Fallen** (Act I's foes; reusable in any act by adding the id to its `"foes"`): `fallen_skirmisher`
  (fast, Savage Lunge), `fallen_reaver` (heavy, Brutal Cleave with a ground wedge warning, `Fx.arc_telegraph`),
  `fallen_stalker` (circles and weaves, Hooking Slash from an angle). Meshy models from JJ (`exports/fallen/` on
  jj-models), prepared by `tools/blender/act1/prep_monster.py -- in.glb out.glb height [tris] [cut]` (base cut,
  decimated, scaled) and rigged by `rig_monster.py` like the other Act I monsters. Each has its own run (Anim's
  `"gait"` from the look: skirm / reaver / stalk, plus a `"stride"`), its own attack style (`Anim.pose`, `Net.STYLES`),
  its own AI (`Enemy._skirm_combat`/`_reaver_combat`/`_stalk_combat`); the attacks move the body along a path
  (`Enemy.atk_path`, `_fallen_path`), land once in their window and leave a recovery (`f_state` "recover"/"rest").
  The old `"fallen"` entry is kept, unused. `tools/fallen_test.gd`, `tools/fallen_sheet.gd -- out.png [side|34]`.
- **The Forsaken Bear** (`bear.gd`, Act I moor): JJ's Meshy model (concept 2, "corrupted ancient"), cleaned and rigged by
  `tools/blender/act1/rig_bear.py` (cuts the slab, 25k tris, 21 lion-named bones + jaw and antlers, surface-distance
  skin) into `assets/models/monsters/bear.glb`, posed in code like the lion (`Bear.pose`: the walk, `bear_roar` rear-up,
  `bear_maul` double-paw slam). Two lone wanderers per moor, 20-40 m off the road (`World._bear_dens`, own seed); the AI
  (`Enemy._bear_idle`/`_bear_combat`) wanders its ground, rears and roars now and then, roars once on noticing you,
  charges and mauls (a 3 m arc, `"maul"` hits knock the hero back: `Hero.knock_v`), gives up 30 m from home. Its sounds
  borrow `lion_roar` (pitched down) and `slam` until `bear_roar`/`bear_maul` exist (`Bear.sound`; either admin may request
  ElevenLabs generation within existing plan credits). `tools/bear_test.gd`, `tools/bear_sheet.gd -- out.png [side|34]`.
- **The Hollow Sloths** (`sloth.gd`, Act I, `World._sloths`): three elemental giants, `Data.ENEMIES` `sloth_fire`
  (Cinderhide), `sloth_ice` (Rimeclaw), `sloth_storm` (Thundermaw), each with `"element"` (fire/cold/lightning),
  `"variant"` (its model) and `"drop"` (its material). Each lives in its own lair (`sloth_lair.gd`, `SlothLair`:
  Cinder Hollow, Rimefrost Glade, Stormcall Ring), a clearing `SlothLair.pick` places 20-32 m off the road on the
  side with room, far apart, before the trees (which, grass and ferns keep out: `World._in_lair`); dressed with a
  Decal of procedural ground (lava cracks, frost, violet fissures), Meshy props `assets/models/lairs/<kind>.glb`
  (modelled 1 m tall, scaled; solid), a light, its element's particles, and bolts striking the storm's rune stones.
  Brain: `Sloth.new(enemy)` (Enemy's 50 m cut-off skips it); it walks on all fours, sniffs, rises to look about,
  only inside `SlothLair.TERRITORY` of its home; a hero across `SlothLair.BOUNDARY` or a blow wakes it: it rises,
  stares, roars and hunts (its run building from 2.2 to 5.6 m/s) the hero who struck it last (`on_hit`, 8 s), else
  the closest, follows anywhere and never gives up or flees; its prey dead, it walks home (`"home"`). Skills (each with its element, `Sloth._land`): the
  Rending Sweep (arc in front; `take_hit` kind `"sweep"` throws the hero back, `Hero.shove`; cold: `"chill"`, slowed,
  `Hero.chill_t`; fire leaves burning ground; lightning chains to heroes near the one struck), the Earthshaker slam
  (ring 5 m ahead; `"quake"` stuns, `Hero.daze_t`; cold `"freeze"`; fire leaves a ring of burning ground; lightning
  calls six bolts down round it, `strikes`), the Hollow Pounce (5.5-11 m; cold shatters ice, fire lands in flame,
  lightning is a quicker dash that shocks, `"shock"`). Burning ground and bolts are host-side lists ticked in
  `_tick_hazards`; everything seen is a `sloth_*` fx event (place-carrying ones like `sloth_burn:x,z,r,dur` go
  through `_elem_fx`). Each timed move is an `atk_t`/`atk_dur`/`atk_style` (`sloth_*`, in `Net.STYLES`), so
  `Sloth.pose` shows the same on every peer; posture holds between moves. The slam has a casting motion per element
  (rig meta `element`: fire heaves and flings its arms wide, cold crosses its claws and shivers, lightning raises
  both arms to the sky) with `_elem_charge` effects. `Sloth.dress` lights the body in its colour with its element's
  particles; `Sloth.presence`/`idle_fx` (every peer) do footfalls, groans, shake, flicker and the storm's arcs.
  Killing one drops a unique, gold and its material; the corner map marks one within 40 m (group `"sloth"`).
  Models: `assets/models/monsters/hollow_sloth_<fire|ice|storm>.glb` (Meshy, from concepts in `exports/act1/`;
  decimated to 42k and rigged by `tools/blender/act1/rig_sloth.py`, skinned by distance to the bones since Blender's
  heat skinning fails on the fur shells; source `sources/hollow_sloth.blend`), `Sloth.MODEL_SCALE` 1.4; without
  them a capsule stand-in on the same skeleton (`Sloth.BONES`). Previews: `tools/sloth_sheet.gd -- out.png [front]
  [fire|ice|storm]`, `tools/sloth_shots.gd`, `tools/sloth_clip.gd` (frames of one fighting; `--fixed-fps 30`).
  Load sloth.gd at run time in a `-s` tool (`load(...)`), like aurelia.gd.
- **Materials** (`Data.BASES` slot `"material"`: `cinderheart`, `everfrost`, `stormglass`): one inventory space,
  never worn or drunk (`Items.is_material`), for crafting later. Each has `"color"`, `"lore"`, a painted `"icon"`
  (`assets/textures/items/`, cut out of Meshy art by `tools/icon_cutout.py`; `IconRenderer.get_icon` uses it) and a
  Meshy `"model"` (`assets/models/items/`, `Models.material`). On the ground they glow (`GroundItem._material_glow`:
  beam, pulsing light, their element rising off them, `Fx.aura`); picking one up is `Game.claim_material` (burst,
  pillar, the `relic_ting` sound, an announcement).
- **Factions** (`"faction"` in `Data.ENEMIES`: goblin, undead): a monster fights the nearest other-faction monster when
  it is closer than the hero (`Enemy.rival`, `Enemy.take_hit` so the attack code works on both); rival kills give no
  xp or loot (`killed_by_rival`). Host-side like all AI.
- **A2 is its own act** (`World.run == 1`; `Data.RUN_ACTS[1]` overrides Act I's names, boss and foes, read with
  `Data.act_info(act, run)` / `World.act_name(key)`; use those, never `Data.ACTS[...]` directly). Warm late-afternoon
  light, no snow (`Game._zone_env`; `is_snowy()` is false now). The camp is still Act I's.
  - **The Imperial Road** (`via.gd`, wild, 110 x 334 m): the road changes along its length (`Via.AMBUSH/ROMAN/
    OUTSKIRTS` are fractions of `path_poly`; `Via.at/dir_at/beside(w, t, off)` place things along it): the moor (dirt
    trail, farmstead ruin, graveyard, the waypoint), a rocky pass with an overturned wagon where bandits wait, the
    Roman road (paving patchy where it sank, then whole with kerbs, milestones, tombs along both verges, toppled
    columns, cypresses, the aqueduct striding across it with one bay always standing over the road), then
    Aurelia's outskirts (ruined colonnades, statues, a villa, a fountain, bandits holding the road) to the triumphal
    arch, the exit to the lair.
  - **Ambushes** (`World.ambushes`, `Game._check_ambushes`/`_spring_ambush`, host only): nothing is spawned until a
    hero comes within `radius` of `pos`; then the entries spawn and leap from cover onto the road
    (`Enemy.leap_from`, `leap_t`), bowmen stay on the crests. A spawn entry may carry `"name"` (the champion's).
  - **Aurelia** (`aurelia.gd`, lair, outdoors; ground levelled by a `ground_fn` that cancels the noise inside the
    zone): the city gate, the colonnaded main street with shops and apartment blocks (`_building`: shop,
    apartment or ruin), districts behind with alleys, the crossroads fountain, the temple (west) and market (east),
    the arena plaza with Varro the lanista (out in the open on the way up to the entrance) (`Inter` kind "lanista", `Game._interact`; he and his two guards are the Meshy
    bandit, the guards are non-clickable `Inter`s with `data.still`; he offers the games again after they're won, and a
    hero at the barred Gate of Life before the deal is told to find him), and the colosseum: the sand
    (`FLOOR_RX/RZ`, `floor_t`), the podium wall (solid), stepped stands, the outer arcade three storeys high on the
    north and fallen to one storey and rubble on the south so the camera sees in, the passage to the Gate of Life,
    beast/side/champion gates (`GATES`), the patron's box.
  - **The games** (`games.gd`, a node in the lair, `world.get_meta("games")`): Varro's deal calls `begin()` (a
    partner's goes through `Net.request_games`); the Gate of Life opens (its bars are an obstacle whose centre is
    moved far away while open: World's obstacles can't be removed); a hero on the sand shuts it (partners outside
    are placed in, `Net.place_player`) and the `STAGES` run: the lions, the gladiators, the beasts of the pit (with a
    champion pit lion), then the champion (`Data.ENEMIES["champion"]`, a boss: his death ends the act through
    `Game.on_enemy_killed`), who calls lions at 60% life and gladiators at 30%. Host-authoritative; everything seen
    (gates, announcements, the crowd's excitement, sounds) is an event string through `fx` / `Net.games_event`.
    In the pit stage and the champion's bout the spike traps fire (`_spike_traps`: glowing warnings, some under
    the heroes, then iron spikes 1.3 s later; they hurt beasts too, never the champion); each kill makes the crowd
    cheer (`kill`). The crowd is the game's own monsters (`Games._crowd_cards`): every kind in `Data.ENEMIES` with a finished Meshy model (`Games.finished_model`) is drawn once
    (idle and cheering, front and three-quarter, `Enemy.build_rig`/`pose_rig` in a little studio) into an atlas, and
    the stands hold camera-facing cards of them (`CARD_SHADER`, jumping and cheering with `excite`); bosses sit in the
    patron's box. A new monster joins by itself. `tools/crowd_shot.gd` screenshots it. Aurelius's shield charge (`_charge`): a red streak on the sand toward the nearest hero, a
    brace, then a dash at 15 m/s smashing each hero in the way once; Games drives him meanwhile (`Enemy.scripted`
    skips his own AI). If no living hero is near the sand for 8 s the games reset. The crowd is one MultiMesh of figures on the
    standing stands, bobbing and jumping by a shader uniform (`excite`). Sounds: `arena_horn`, `crowd_roar` (loop),
    `crowd_cheer`, `portcullis`, `lion_roar`.
  - **Roman architecture** (`roman.gd`): materials (marble, tuff, brick, tile, bronze), `arch_mesh` (an extruded
    wall with a round opening, used by the aqueduct, the colosseum's arcade, gates), columns, colonnades, tombs,
    milestones, statues (a Meshy Roman emperor in marble, `assets/models/roman/statue.glb`; the earlier Meshy knight `knight_statue.glb` carved in marble, `Roman.STATUE_GLB`, is the fallback), fountains, the triumphal arch, cypresses (the Meshy cypress in `World.mm_chunked` chunks)
    (MultiMesh), ruined walls. Repeating pieces go through `Props.multimesh` with their own mesh copy
    (`Roman._own`: Geo's meshes are cached and shared, never set a material on them).
  - **Monsters**: bandits (`bandit`, `bandit_archer`: the Meshy bandit on `MeshyMonster`, faction "bandit"),
    the arena lion (`lion.gd`: Meshy model, a 20-bone skeleton from `sources/lion.blend` skinned by surface
    distance like the Feral, posed every frame in code by `Lion.pose`, the Feral's pack AI with its lunge as the
    pounce and its swipe as the maul; `tools/lion_sheet.gd`), the gladiator and Aurelius the champion: Meshy models
    (2026-11-02, the visual overhaul: concept → image-to-3D → `act1/prep_monster.py` → `act1/rig_monster.py` with
    the `crotch` hint, since a loincloth or skirt fools the leg scan → `MeshyMonster.MODELS`; the gladiator 20k
    triangles and 1K textures, Aurelius 30k and 2K: lion cuirass, crimson crest and pteruges, no cape). They join the
    arena's crowd cards by themselves; Aurelius is kept out of the patron's box (`Games.crowd_bosses`).
  - Tests and previews: `tools/a2_arena_test.gd` (road, ambush, Aurelia, the whole games), `tools/via_shots.gd`,
    `tools/aurelia_shots.gd` (`overview` for a top view). Load `aurelia.gd` at run time in a `-s` tool script
    (`load(...)`): a static reference compiles it, and games.gd's `Sfx`, before the autoload exists.
- **Grubb's fort** (`fort.gd`, `World.fort` = Act I only): an outdoor zone still called "lair" (`Game.indoor()` is
  false there, so it gets the sky, snow in A2 and the outdoor light). Big pieces are Meshy props prepared by
  `tools/blender/act1/prep_prop.py` (`-- in.glb out.glb x=5|h=8|w=11 triangles [yaw] [tex]`; keep ~12k triangles for
  the palisade, which repeats ~44 times); without the glbs simple log stand-ins are built. The camp is placed by
  rejection sampling round the courtyard (`Fort._camp`), Grubb's courtyard reuses `World._hoard_room`.
  Outer works: the palisade stands on a rampart with a water-logged ditch round it (`Fort.ground`, set as
  `World.ground_fn`, the generic hook for shaping a zone's ground; the fort's slopes are coloured mud, not rock),
  a causeway and plank bridge at the gate, stakes on the ditch's lip (`_ditch`); a second, lower stockade round
  the south (`OUTER_RX/RZ`, `_outer_wall`, its own gatehouse where the track comes in; the gate battle is there
  now) enclosing the outer yard (`_outer_yard`: stables, pens, wagons of plunder, the camp's Meshy forge and
  tents, storehouses on stilts, haystacks, lantern posts, guards). Behind the throne, Grubb's great hall (Meshy,
  `assets/models/fort/hall.glb`, `HALL_YAW` turns its door toward the courtyard; source concept and raw model in
  `exports/fort/`), with braziers, banners and a treasury hut each side. Outside: stumps where the forest was
  felled, a lumber yard and a crop field (`_outskirts`). `tools/fort_shots.gd` screenshots it from the game camera.
  `tools/fort_test.gd` checks it; `tools/zone_overview.gd -- out.png --fort` renders it from above.
- **Sound**: effects are real recordings (Kenney, CC0) and ElevenLabs Sound Effects generations, picked by ear; the
  old numpy synthesis (`tools/audio/make_sfx.py`) was rejected as cheap-sounding and is kept only as a fallback.
  Pipeline (`tools/audio/`, the heavy steps run in the venv at `~/Documents/Game Factory Audio/venv`):
  `spec.py` lists every sound (source, prompt, duration, `hit` = seconds to the payoff, loop); `eleven.py [names]`
  generates candidates into `~/Documents/Game Factory Audio/candidates/<name>/` (key in `~/.config/elevenlabs/key`,
  about 10 credits per second of audio, `--dry` estimates, `--credits` shows what's left; never buy more);
  `score.py --rank` scores them (CLAP: real sound vs synth/beep, audiobox quality) so the obviously bad ones sink;
  a human picks (the Sound Picks artifact); `build_sfx.py picks.json` (`{name: [files]}`) trims each take, puts
  its payoff `hit` s in, matches loudness by category, writes `assets/audio/sfx/<name>_<take>.wav` (32 kHz, imported
  as QOA), `scripts/sfx_bank.gd` (`[takes, bus, hit]`) and `assets/audio/CREDITS.md` (source and license of every
  file). Run `godot --headless --editor --quit` after a build. `Sfx.play(name)` is heard flat (the hero's own skills, UI), `Sfx.play_at(name, pos)` is positional
  (hits, monsters; AudioStreamPlayer3D, full volume at the camera's distance). Takes rotate, pitch is nudged, at most
  three of one sound per 50 ms, buses SFX/UI/Music/Ambience with a limiter on Master, `Sfx.duck()` under big spells.
  A cast's sound starts with the cast (`Hero._attack_sound`) and `Sfx.play_synced` lands its payoff on the impact
  frame at any attack speed; monster impacts, crit stings and kill sounds come from `Enemy._hit_sound`/`die_visual`
  by `Enemy.material()`. King Grubb's voice is deep (the `cackle`/`roar` takes, never pitched up), and before his fight
  his muttering (`grubb_mutter`) carries through the fort from him, faint from ~75 m and clear in sight
  (`Hoard.murmur`, every peer locally; stops at the "intro" event). `tools/sound_test.gd` checks every skill fires its
  sounds (`Sfx.counts`) and the fort voice. The camp's song is `music_town` (jj's pick: a dark forest sanctuary, harp over a low
  string drone with a wooden flute; candidate take 13). Ambience: wind, drips in the crypt, and in Act I outside the camp (moor and fort) `forest`, soft
  trees in a breeze (`Sfx.play_music(kind, amb)`, picked in `Game.load_zone`).
- **The Mournwater Coast and its islands** (Act I, west of the camp through its west gate; on `staging` since 2026-11-01). `coast.gd` (`Coast`, zone `"coast"`): a headland with the open sea on
  three sides (the mainland's shore is a parabola round its tip, `shore_x`), the pier at the tip (`DOCK` = the origin,
  the boat's mooring), the shipwright's shed (`SHED`), the path back to the camp (`EXIT`). The islands are data in
  `isles.gd` (`Isles.ISLANDS`: id, name, bearing from the dock, `sail` = metres of open water from the dock to the end of
  its jetty, radius, beach/cliff, colours, and empty `foes`/`loot`/`quests`/`dungeon` for later), each with its own
  builder script `isle_<id>.gd` (`relief` = its inland shape, `pads` = flat spots, `dress` = trees, landmark, props,
  named spots `poi_*`); a new island is a table entry, a script and a line in `ISLE_SCRIPTS`. Landmarks are Meshy props in `assets/models/isles/`
  (`Isles.prop(name)`, null without the file, so each builder keeps its procedural stand-in; prepared by
  `tools/blender/prep_prop.py`): `store` (the Merchant's Reach storehouses), `beacon` (its tower; the game lights the
  brazier), `wreck` (the Bleak Isle), `mono` (the Lost Isle's Monolith, runes lit by `MONO_SHADER` in `isle_lost.gd` from its
  own texture), `temple` (the Forgotten Ruins: columns `TEMPLE_COLS` solid, floor and top step are decks).
  `tools/isle_props_shot.gd -- outprefix [q] [isle]` screenshots them. An island may carry a `"mood"` (the Bleak Isle's): its own
  water colour (`Ocean.set_tint`), fog, sky, sun and grade in its zone (`Game._isle_mood`, called from `_sea_env`); the
  Bleak Isle also lies under a FogVolume (`_fog_bank` in `isle_bleak.gd`, seen from the coast too, High/Ultra only). Sea cliffs
  are layered rock in the terrain shader's `sea` mode (strata bands, sparse joints, rain streaks, lichen, ledges in
  the normal), with talus stones under them (`Isles.shore_rocks`). At sea `Birds` are gulls (`sea`: pale, long black-
  tipped wings, gliding, some wheeling over the hero) and fish leap with a splash (`Birds._fish`). The coast's corner map
  is a painted sea chart of the whole sea (`Game._sea_chart`, cached; `Minimap.chart`: no fog, a wider view while
  sailing). `tools/sea_life_shot.gd -- outprefix [q]` screenshots the chart, gulls, a fish and the Bleak Isle. **Sounds** (made in code by
  `tools/audio/make_sea.py`, built by `build_sfx.py` like any take; replace them under the same names later): `surf`
  is the sea zones' ambience bed, loudest on the beach and fading inland and out at sea (`Game._sea_sounds`); under
  sail `BoatRide._sounds` plays the `sea` loop (louder with speed), `hull_creak` (more as she pitches and rolls) and
  `hull_slap` at speed; gulls cry (`gull`, `Birds._gull_calls`), a fish lands with `splash`; Osric's hammer knocks
  with `mallet` (his clips' `"strike"`, `"sparks": false`). `tools/sea_sound_test.gd`. **Co-op**: a sailing player's
  boat rides at the end of his state packet (`Net._boat_packet`: aboard, x, z, yaw, speed; no new RPC), and each
  partner draws it under his puppet with him at the tiller (`BoatRide.puppet_update`, a BoatRide with `puppet` on:
  glides to the sent place, rides the local waves, wake and creaks, no sea loop, no docking); it goes when he steps
  ashore. Each game moors its own boat at the docks. Boarding at an island takes the party out to sea with every
  owner aboard his own boat, 9 m apart by peer id (`Game._party_rank`); a partner with no boat is set down on the
  pier. `tools/sail_mp_test.gd` (host + join). The five are 250 m across,
  164 m of water (~22 s at the boat's 8 m/s) from the dock, 14.5 m channels apart. Out at sea (the coast zone) every
  island is drawn at full size (`Isles.dress(..., full = false)`: ground at 2 m, trees, landmark, jetty); stepping off at
  its jetty loads its own zone `"isle_<id>"` (`Isles.build_zone`: the island at the origin, same ground at 1 m, grass,
  ferns, props, the far shores from `Coast.distant`). Ground: `Coast.ground(p)` (sea floor, mainland, islands) baked into
  `HeightGrid`s (`height_grid.gd`; cached for the session) and read through `World.height_fn`. Sea zones (`World.sea`):
  walkers stop where the water is deeper than `World.WADE` and at cliffs steeper than `World.steep`; piers and jetties are
  `World.add_deck` (`height_at` includes decks, `ground_h` is the bare ground the terrain, sea map and grass read).
  Terrain: `World.terrain_patch(rect, step, colours, name, floor, own)` (the zone's own ground plus coarser patches; the
  terrain shader's `sea` mode adds sand, wet sand and the seabed with caustics). The water is `ocean.gd` (`Ocean`, added
  by `Game._add_ocean`): Gerstner waves on a camera-following ring mesh (the same sum on the CPU, `surface_y`, for
  floating), a baked depth/shore map (`bake`: turquoise shallows, calm water inshore, surf rolling onto every beach,
  foam at rocks and posts), Forward+ refraction and depth (Medium+), the `LITE` variant on Low and OpenGL; global
  `ocean_t`. Light: `Game._sea_env` (golden evening, low sun over the sea, clear air). `World.get_meta("sea_rocks")`
  lists rocks in the water for boats. **The shipwright**: Osric Saltmarrow (`Data.VENDORS[0]["shipwright"]`, the Meshy
  `assets/models/npc/osric.glb`: concept, image-to-3D, Meshy rig and library clips Idle_4 / Heavy_Hammer_Swing /
  Long_Breathe_and_Look_Around / Talk_Passionately / Wave_One_Hand, cleaned by `prep_npc.py`; a camp keeper through
  `ForestCamp._keeper` loaded at run time, hammering the hull on its trestles, `Coast.HULL_AT`; the procedural
  humanoid without the glb) at his boathouse (`Coast._boatyard`), an `Inter` "vendor" with role "shipwright": `Game._shipwright_talk`
  (dialogue) opens `BoatShop` (`boat_shop.gd`, `ui.boat_panel`: portrait, the boat turning on the water, name, price, text,
  how to sail, Buy). Boats are `Data.BOATS` (`gull`: 400 gold, speed 8; `sloop`, the Ember Sloop: 1500 gold, speed 9, a
  14 m Meshy model); owning one is `Hero.boats` (saved), bought with `Game.buy_boat`; Osric offers every boat, cheapest
  first, and the docks hold the dearest one owned (`Hero.best_boat`, swapped at once on a purchase). **Imported boats**:
  an entry with `"glb"` (a model prepared by `tools/blender/prep_boat.py -- in.glb out.glb <length m> --draft m --bow
  +x|-x|+y|-y [--tris N] [--tex px] [--shot png]`: bow to Godot -z, waterline y = 0; it prints the numbers) plus
  `"length"`, `"beam"`, `"sheer"`, `"draft"`, `"deck"` (the helm spot) and `"lamps"`; `Boat.model` loads it (the Gull
  built in code if the file is missing, so a better model is a one-path swap), `Boat.dims(id)` gives the size, and
  `BoatRide` scales by length and beam against the Gull (`kl`, `kb`): the shallow-water probes, helm, wake, spray,
  click area, docking reach and the sailing camera; a longer boat eases out from the Gull-sized moorings until she can
  swing round clear of the pier or jetty (`_swing_clear`). In co-op the boat's index in `Data.BOATS` rides at the end
  of `Net._boat_packet` (`Hero.net_boat_id`), so partners draw the right boat. `tools/sloop_test.gd`. The boat's model is `Boat.model(id)` (`boat.gd`: lofted clinker hull with its own plank shader, deck,
  mast, gaff main and jib in the cloth shader, rigging, rudder, lantern).
  `tools/boat_shop_test.gd`, `tools/boat_shop_shot.gd`. **Sailing** (`boat_ride.gd`, `BoatRide`; Game: `_add_boat`,
  `_boat_clicked`, `_sail_input`, `try_land`/`land_boat`, `_sail_camera`): every sea zone has a boat, moored off the
  coast's pier end (`Coast.MOOR`) or at the island's jetty (`Game.isle_mooring`), an `Inter` "boat" (bigger pick area via
  metas `pick`/`pick_y`). Clicking her aboard (`Hero.aboard`: his own moving stops, she places him at the tiller,
  `BoatRide.DECK`) on the coast; on an island it loads the coast with spawn `sail_from_<id>` (she's off that jetty with him
  at the tiller). Controls: W builds speed and holds it (cruise control), S eases off then backs, Space heaves to, A/D
  steer, the held left mouse sails toward the point on the water (`Game.water_pt`); skills, Space's swing, exits and
  right mouse are off while sailing; E (or the `UI.sail_prompt` button) steps ashore when `dock_near()` (within
  `DOCK_REACH`, slower than `DOCK_SPEED`): at the pier she moors and he's on the deck, at an island its zone loads
  (spawn `jetty`). She rides `Ocean.surface_y` (bow/stern/sides: height, pitch, roll, heel in turns), can't ground
  (`_clearance`: probes vs the sea map's depth, sea rocks and decks as graded obstacles; she only moves to deeper water
  from where she is, sliding along shores), the sea's edge (`sea_rect`) turns her back, wake and bow spray are
  GPUParticles. The camera eases to a view over her port quarter looking past the bow (`_sail_camera`, `sail_blend`).
  First time aboard, a controls guide (`Hero.sailed`, saved). `tools/sail_test.gd` (sails every route with her own
  physics: 21-23 s each; grounding, unsticking, the sea's edge, waves, landing, boarding at an island, back to the
  pier), `tools/sail_shots.gd -- outprefix [q] [isle] [boat id]`. Tests: `tools/ocean_test.gd`; screenshots `tools/ocean_shots.gd -- outprefix [q] [only]`
  (Forward+ screenshots need a Vulkan driver: `apt-get install mesa-vulkan-drivers` gives lavapipe, slow but correct).
  Note: a first import of the project needs `godot --headless --editor --quit-after 2000` (plain `--quit` can abort the
  scan before the class cache is written).
- **The shared stash** (`scripts/shared_stash.gd` `SharedStash`, `Game.stash`; jj 2026-11-02): one stash for every
  character on the PC, `TABS` (5) tabs of `SLOTS` (60), in its own file (`user://stash.json`; a tool script's
  `TEST_PATH`), backed up to Nakama (collection `"stash"`, key `"shared"`, the higher `rev` wins in `CloudSaves.sync`).
  **No duplicates**: an item going in gets a fresh `"uid"` and the character is saved with it stamped, then the stash,
  then the character without it (`Game.stash_deposit`); coming out, the character first, then the stash
  (`stash_withdraw`); `SharedStash.reconcile` takes out of a character anything whose uid is in the stash (every
  character file at start, `Game._stash_start`, and the one loaded, `_stash_fix_hero`), so a crash between the saves
  always leaves the stash's copy and nothing else. Every change re-reads the file first when its `rev` moved (`fresh`:
  a second copy of the game). Old per-character stashes (`Hero.stash`) are stamped, moved in and reconciled away the
  same way. `Items.upgrade` keeps `uid` and `boost`. Opens at the camp's chest and, in a raid, only before the gates
  rise (`Game.stash_allowed`). The window (`UI._build_stash`, `UI.StashTab`): the inventory's iron frame, tabs as
  bronze plaques with their counts (`stash_style` "plaques"; "ribbons" and "gems" kept), click to move.
  `tools/stash_test.gd`, `tools/stash_shot.gd`.
- **The raid's antechamber** (jj): the countdown (`PREP_SECS` 20) starts by itself at `RAID_MIN` (2) players; the matchup
  (`Battlegrounds.roster` -> `Net.cl_bg_roster`, `BgMatchup`: each other raider's class crest, name and level, never a
  player name) shows under the clock while it runs. Each corner room has the raid's **stash chest** on its **dais**.
  jj's chests are numbered (`StashChests`, `scripts/stash_chests.gd`; for people `assets/models/stash/chest/CHESTS.md`
  with renders in `previews/`): each names its model and dais in `assets/models/stash/chest/`, its fire
  (`Battlegrounds.STASH_THEMES`: `ember` red, `spirit` blue, every light, flame, spark and glow of the chest, its dais
  and its opening) and the maps that use it (`StashChests.for_map`; the Hollow Crypt has #2, the blue Spirit Chest; #1,
  the red Ember Chest, is saved for the next map; `--stash-chest N` previews another). The chest
  (`chest_01.glb`, built from seven Meshy pieces by
  `tools/blender/camp/assemble_chest.py`: body, `lid` hinged at the back, `lock` with its Blender-made `shackle`,
  `coals`) and the dais (`StashDais`, `scripts/stash_dais.gd`: the grand waypoint's build at 2/5 size,
  `tools/blender/camp/build_stash_dais.py`, its wet stone, its rune lettering in the chest's fire, the waypoint's fire bowls (`dais_01.glb`);
  wakes as a hero comes, `burst()` on opening). The raid server hands the chest to the first who asks
  (`Battlegrounds.stash_opened`, one player at a time, `stash_user`); the opener is 15% slower for the rest of the
  raid (`Hero.stash_slow`, `stash_slowed`, sent as bit 10 of the state; its mark only on the opener's own screen),
  and every game plays the opening (`Game.chest_lid`: the padlock springs, the lid heaves, a shadow-casting glow;
  `Battlegrounds.stash_fx`: InfernalFx fire spray, smoke, `chest_raid_open` and the `chest_raid_loop` that sinks to
  20% over 10 s); it stays open and burning until the gates rise (`close_stashes`). `tools/chest_open_clip.gd`
  renders it frame by frame; `tools/bg_admin_test.gd` covers the server side.
- **The camp's bonfire** (`Inter` kind `"bonfire"`, `UI.open_burn`): clicking it roars up (`bonfire_open`) and opens the fire
  window in the inventory's iron frame (a shader fire in a stone hearth, `UI.Flames`/`FIRE_SHADER`) with its options below
  in the bar's sockets (`UI.BONFIRE_OPTIONS`: Burn, Enchant; empty sockets wait for more) beside the
  inventory; drag an item onto the flames or right-click it to burn it for good (`UI.burn_request`, `Game.burned`: the
  `burn_item` sound and a flare); rare, unique and material items ask first. A click on an inventory item plays
  `inv_click`. `tools/bonfire_test.gd`, `tools/bonfire_shot.gd`.
- **Woodcutting** (`scripts/harvest.gd` `Harvest`, visuals `scripts/wood.gd` `Wood`; Act I's moor): `Harvest.pick`
  takes up to `CAP` (24) trees out of `World._build_wild`'s MultiMesh groups on its own seed (the same on every peer;
  8-42 m off the road, `SPACING` apart, never by the arrival point; Ferals never perch on them since they're gone from
  the groups before `_feral_packs`), `HEARTWOODS` of them Ashen Heartwood from the dead trees; the rest stay scenery.
  `Harvest.build` makes each a `Harvest.HTree` (an `Inter`, kind `"tree"`, in `world.interactables`, so hovering,
  clicking and walking up are the usual interaction; `Game._interact` -> `Hero.start_chop`), keeps the footprint World
  already had for it (`World.obstacle_at`; a stump shrinks it, regrowth restores it) and cuts its mesh in two at the
  cut (`Harvest.split_mesh`) for the stump and the falling trunk. Kinds and numbers: `Harvest.KINDS` (Moor Oak 7
  blows / 3-4 logs / 8 min, Old Pine 4 / 2-3 / 6 min, Ashen Heartwood 14 / 1-2 / 25 min). Chopping (`Hero.chop_*`):
  the hero needs an axe (`Hero.chop_axe`: the `woodsman_axe` tool every hero gets in the last bag cell, sold by the
  smith, or a combat axe, `Data.CHOP_POWER`), puts his weapon away and swings style `"chop"` (an attack with
  `atk_skill` `"chop"`; Anim's procedural chop for every body, whole-body clips where a body has them: the Demon's
  Charged Axe Chop, the Wraith's slam with a spectral axe, the Plague Doctor's censer slam; per class
  `Data.CHOP_PROFILES`, a missing class gets `DEFAULT_CHOP`), one blow per swing on its impact frame
  (`Harvest.strike_from`); moving, a skill, a target or a blow taken stops him (`stop_chop`). **The host owns the
  trees**: a partner's blow is `Net.request_chop` -> `sv_chop`, and `Harvest.strike` refuses it beyond `REACH`, faster
  than `STRIKE_GAP` or at a felled tree; what happens goes to everyone as `Net.cl_tree` events (`hit`, `fell`,
  `heal`, `regrow`; `play_event`), joiners get `cl_trees` in the snapshot; the logs are ordinary host ground items
  (`Game.drop_item`, one pickup each). Wounds heal after `HEAL_AFTER`; stumps regrow on the host character's played
  time (`Game.played_s`, saved) after the kind's respawn, only with no hero within `REGROW_CLEAR`; stumps are saved
  with the character (`Game.harvest_saved`, `"harvest"` in the save, keyed `run:act:zone`). Off in the Battlegrounds.
  Sounds: `Harvest.snd` uses `axe_chop`, `bark_crack`, `tree_creak`, `tree_fall`, `tree_thud`, `leaves_rustle`,
  `log_pickup` when they're in the bank and existing sounds pitched to fit until then (`SOUND_STAND_IN`).
  Resources: `Data.BASES` slot `"resource"` (`oak_log`, `pine_log`, `heartwood`: `"stack"`, `"fuel"`), stacked by
  `Hero.add_to_inventory` (`Items.stack_cap`), counted and taken with `Hero.count_of`/`take_items`; slot `"tool"`
  for the axe. New resources (ore, coal) are BASES entries. Tests: `tools/woodcut_test.gd` (`--fixed-fps 60`),
  `tools/woodcut_mp_test.gd` (host + join); screenshots `tools/woodcut_shots.gd -- outdir [class]` (xvfb).
- **Weapon tempering** (`scripts/furnace.gd` `Furnace`, window `scripts/furnace_ui.gd` `FurnaceUI`): Halvar's furnace
  stands beside his forge in the Act I camp (`Furnace.place` from `ForestCamp.build`; Inter kind `"furnace"` ->
  `UI.open_furnace`, shop_mode `"furnace"`: right-click a weapon in the bag to put it before the fire, a log to load
  it, Shift for five). **Weapons only** (armour keeps the gold enchanting), `Items.TEMPER_MAX` (+5) levels, each
  +`TEMPER_ED`% (6) enhanced damage and +1 damage (`Items.stat_sum`'s `"temper"`). The heat model (`Furnace.step`):
  `dT/dt = (P - LOSS (T - AMBIENT)) / MASS`, at most `SLOTS` (3) logs burning, in the order loaded, each for its
  `"burn"`; the fire can't pass the best fuel's `"max_temp"` (pine 1040, oak 1240, Heartwood 1400 = `MAX_T`); the
  bellows (held) give `BELLOWS_HEAT` more heat and burn twice as fast; it cools once the wood is gone. A level
  (`Items.temper_cost`): its band (`TEMPER_BANDS` 600/850/1050/1250/1350 °C), a charge of logs (from +4 with Ashen
  Heartwood, so oak first to raise the fire, then the Heartwood), the smith's fee, and a soak that only runs while
  the fire is at the band; Quench after the soak = the level, before it = nothing (the weapon is safe, the charge is
  spent and burns on in `spent`). Closing the window mid-temper is a quench before time. Each player's own (nothing
  crosses the network). Visuals: flame cards and coals shaded by the heat (`FLAME_SHADER`, `COALS_SHADER`,
  `heat_color`), the weapon glowing in the mouth (`HOT_METAL_SHADER`), embers, sparks, chimney smoke, heat haze
  (screen texture; not on the web), the bellows working; the roar is `furnace_roar` when it exists (the wind pitched
  down until then). Test: `tools/temper_test.gd`.
- **Birds** (`scripts/birds.gd`, Act I outdoors, added by `Game.load_zone`): flocks of dark swept-wing silhouettes cross
  the sky round the hero (flapping, gliding, banking, shadows), and every 25-50 s a flock bursts out of the trees near
  him with `birds_flutter`. Cosmetic and local (not synced). Screenshot: `tools/birds_shot.gd`.
- **The party's ready check** (`Net.ask_trip`, called by `Game.travel` whenever the party has more than one player):
  the host runs a vote (`Net.vote`), every peer sees `UI.party_vote` (a small iron-and-bronze window, Join / Not yet;
  the one who asked sees "Waiting for …" and Cancel), and the host's `Game.travel_now` takes the whole party once
  everyone has said Join. A member leaving mid-vote is dropped from it (theirs is called off). The host is the party
  leader (♛ on the party list) and can remove a member (✕, `UI.confirm_kick`, `Net.kick`). `tools/mp_test.gd`
  (host + join) checks it; `tools/vote_shot.gd` screenshots the window.
- **New Character screen** (`UI._build_class_picker`, `scripts/class_stage.gd` `ClassStage`): a **focused carousel** in a
  ruined cathedral (`scripts/class_cathedral.gd` `ClassCathedral`, all in code; concept `concepts/class_screen/arrows_b_focus.png`; the stage fills the whole screen behind the title and the panel, its camera's frustum shifted and widened by `ClassStage._frame` so the heroes sit in the band between them (`band`), with soft fades over it, `UI.STAGE_FADE_SHADER`):
  the chosen hero stands large in the middle, front and close, on the biggest plinth with its shaft blazing; the ones
  either side stand back, smaller and dimmer; the outer ones further back, fading into the gloom; the rest wait unseen.
  `ClassCathedral.build_hall` is the still set (floor, back wall with pointed windows, pillars, rubble, candelabras,
  ash); each class gets a **stand** (`build_stand` under one Node3D in `ClassStage.stands`: hexagonal plinth with runes
  glowing in the class colour, the coloured light shaft, a tattered banner with its emblem, candles, its spot and rim
  lights), and the carousel moves the stand with its hero, so any number of classes in `ClassStage.CLASSES` works and
  the ring wraps round. Slots are by distance from the middle (`SLOT_X/Z/SCALE/LIGHT`, interpolated across the glide;
  `VISIBLE` = where a slot fades out; the hero node is scaled with its stand, so every lift and effect in a move is
  multiplied by `_k(cls)`). Turning: the two arrows at the stage's edges (`UI.ClassArrow`: Meshy-painted iron chevron
  `assets/textures/ui/arrow_left.png`, flipped for the right one, with the gem's glow `arrow_gem.png` added on hover;
  hover brightens and grows it, pressed dips it, a key press flashes it; it `accept_event`s), the mouse wheel over the
  stage, Left/Right or A/D (`UI._class_key`, not while the name field has focus), or a click on a side hero: `turn(dir)`
  / `go_to(cls)` glide the ring one slot (`TURN_T`, eased; rapid turns queue into one longer glide from where the ring is,
  never a snap; `snap_to` opens on the knight), the hero that will arrive is `chosen` at once (`picked`, its `PICK_SOUND`,
  the panel follows) and its signature move starts once it has arrived. Nameplates follow the feet (`feet_at`) and fade
  with the slot (`plate_alpha`); `class_at` picks only the visible heroes at their scale. Hidden slots' heroes and lights
  are off (WebGL's light budget). Idle they breathe and look about (`_idle`), under the mouse the front three fidget
  (`_fidget`), the chosen one does its signature move every 4.5 s with its effects (`SIGNATURE`, `_signature`). Choosing
  a hero plays its own sound (`ClassStage.PICK_SOUND`, `pick_sound`), and the screen has its own theme, `music_select`
  (`Game.zone_music()` brings the zone's song back when it closes). Below, in the inventory's iron frame: name, story,
  stats, skills in the bar's sockets, the name and Play. The stage is built when the picker opens and freed when it
  closes. A new class needs only a `ClassStage.CLASSES`/`ACCENTS`/`EMBLEMS`/`SIGNATURE` entry and its `_fidget` case (it
  gets its own stand automatically) and a `SKILL_SHOW` entry per skill (hover a skill in the panel: the centred hero
  performs it on the stage, `show_skill`). Tests: `tools/class_carousel_test.gd` (`--fixed-fps 60`: turning, wrapping,
  queued turns, clicks, keys, wheel, feet on plinths, skill previews); `tools/class_shot.gd -- outdir [frames]`.
- **Home screen and the Battlegrounds page** (Blaine 2026-11-01, "no plain boxes"): over the title's gate, `TitleHome`
  (`scripts/title_home.gd`): the character sidebar (class colour on each card, delete on the card, Create New
  Character), the modes Story / Online Co-op / LAN as iron tabs and one big Play, a Battlegrounds card with its key art
  (`assets/textures/ui/bg_crypt.jpg`, Meshy) and Quit Game. The card opens `BgPage` (`scripts/bg_page.gd`, `UI.bg_page`,
  `UI.open_battlegrounds`): the art full screen, Fight / Loot / Extract, the death rule, the champion (arrows cycle the
  characters; what they'd risk), the live raid board, Enter the Crypt (asks first), Back / Esc. Every panel is
  `UI._ornate(panel, k, pad)` (the inventory's iron and gold frame at scale k) and every button `UI._iron_button`;
  `open_dialog` is an ornate panel over a vignette. `tools/screen_test.gd` checks it.
- **Deploys never kick players** (Blaine 2026-11-02): `deploy/staging/deploy.sh` puts each deploy in its own
  `/opt/ashen-crown/staging/releases/<rev>-<time>` and switches the `game` link; the services start the release the
  link points at, resolved (`ExecStart` via `readlink -f`), and `ServerUpdate` (`scripts/server_update.gd`, every 20 s)
  moves a running server to a new live release only when nobody would be hurt (raid: empty or between rounds; co-op:
  empty), telling its players once (`Net.cl_bg_note`, no new RPC). `deploy.sh --now` restarts at once (emergencies;
  announce it). `tools/server_update_test.sh` (a co-op server, two players, the link moved under them).
- **Stamina out of combat** (jj 2026-11-02): `Hero.calm()` is 1 in a fight (a blow struck or taken, or an awake
  monster within 14 m, `_engaged`) and for `COMBAT_SECS` after, then rises to `CALM_MAX` (5) over `CALM_RAMP`;
  sprinting drains that many times slower and stamina refills that many times faster ("Rested ×N" on the bar).
  `tools/stamina_test.gd`.
- **The Codex standards audit** (Blaine 2026-11-01, `tools/audit/`): a read-only run of ChatGPT's Codex CLI on a clean
  worktree of `origin/staging` (`~/dev/ashen-crown-audit`) with the admins' Discord requests since the last audit;
  it checks requests vs delivered, asset quality, architecture, performance, tests and process against
  `audit_prompt.md` and posts the findings to the channel. launchd `com.gamefactory.ashen-audit` (install.sh):
  19:40, 23:30, 2:30, 7:30, 12:50, 16:20. It never edits or runs the game; log `~/Library/Logs/ashen-nightly/audit.log`.
- **Title screen** (`UI._build_title`, `scripts/title_stage.gd` `TitleStage`): the Gate of the Ashen Crown at dusk in
  its own World3D: a ruined cathedral gate with the dusk showing through its arch (`BACKDROP_SHADER`), broken arcades,
  the fallen stone king and a giant crown in the ash, fog banks, falling ash, embers, braziers and torches, heat
  lightning now and then. Models are Meshy (concept image, then image-to-3D, 144 credits) in `assets/models/title/`
  (`gate` 18 m, `arcade` 8 m, `colossus` 10 m, `crown` 1 m, prepared by `tools/blender/prep_prop.py`; the colossus cut
  at the ash line by `tools/blender/trim_below.py`), darkened to the game's palette in code (`SOOT`); without them
  procedural stand-ins are built. The chosen character (the sidebar's choice, `TitleHome.select`) stands alone before
  the arch between two braziers, no dais (Blaine, 2026-11-05), as a co-op puppet in their saved gear
  (`Game.character_gear(id)`, read-only), idle, doing their class's `ClassStage.SIGNATURE` move when hovered; hover
  leans the camera in and lights them (`set_focus`), a click plays the move in (`enter`) and enters their world. The
  picture is centred in the room left of the character sidebar by shifting the camera's frustum (`TitleStage._frame`,
  `TitleHome.mid`), so the hero stays in line with the arch. The controls (`TitleHome`): the sidebar of characters with
  Create New Character, and at the bottom **Enter World** (your own game; friends join it), **Multiplayer** (straight
  to the lobby browser, `LobbyClient`: Battlegrounds, Endless Waves, Arena) and a small Quit. No left column any more
  (the Last Flame board's code is kept for the Waves lobby). LAN has no menu of its own: the lobby browser's "Local
  network" row (`LobbyClient.lan_row`, hidden in game) hosts or joins (`TitleHome.lan_host`/`lan_join`). While the title is up the main
  viewport's 3D is off (`disable_3d`; the camp still builds behind), the stage stops drawing under the class picker or
  the list (`covered`), and the music is `music_select` (`Game.zone_music`). Sharpness: MSAA only (no FXAA/TAA), no
  mesh LOD, anisotropic filtering on the models, light bloom and a contrast-adaptive sharpen (`SHARPEN_SHADER`). Screens
  narrower than 16:9 keep 16:9's width of view (`H_FOV`). `tools/title_test.gd` (the flow), `tools/title_shot.gd --
  outprefix [class]` (screenshots with and without a save), `tools/title_clip.gd -- outdir` (frames of the hover and
  the move in; `--fixed-fps 30`).
- **Quests** (`scripts/quests.gd`, `Quests`, `Game.quests`; the log is J, `UI._build_quests`): every quest is data in
  `Quests.LINES` by run (0 = Act I; other runs have none yet): its giver (a camp role, `Data.VENDORS`), texts (`offer`,
  `busy`, `done`), goals (`kill` with Data.ENEMIES ids, `pick` with item bases, `flower`), `after` (a quest that comes
  first), `auto` (the act's main quest, on from the start) and reward (gold, xp, items: a base, or "weapon" = his own
  kind, "armor", "unique"). Talking to a giver (`Game._interact` "vendor") goes through `Quests.talk`: a quest to hand
  in or on offer comes before their trade (`Game._vendor_talk`). Counters move from `Game.on_enemy_killed`,
  `Game.claim_material` and the Sunstar Bloom; partners count the host's kills through `Net.cl_enemy_die` (no new
  RPCs). The gold "!" / "?" over a giver is `VendorUI.Plates._mark`; the tracker under the corner map is
  `UI._fill_tracker`. State is per character and run in the save (`"quests"`). Act I's line is a first draft for jj
  and Blaine to rewrite. `tools/quest_test.gd`.
- **Characters** (save slots): each character is its own save, `user://characters/<id>.json` (`Game.char_id`,
  `char_name`; the save holds `name` and `played`). `Game.list_characters()` reads them (last played first) for the
  title's Continue card and the Characters list (Play / Delete); New Character asks for a name on the class picker.
  The pre-characters save `user://ashen_crown_save.json` is adopted once as the first character and left in place.
  The pause menu's "Save and Exit to Title" is `Game.exit_to_title()`. Co-op uses the last played character and its
  name. Tools still save to the test file; `tools/char_test.gd` moves `char_dir`/`old_save` to test the real thing,
  `tools/char_shot.gd` screenshots the screens.
- **Act I camp in the forest** (`scripts/forest_camp.gd`, `ForestCamp.build`, used by `World._build_town` when
  `oak_forest` and act 0; A2/A3 keep the old camp): a ring palisade with a gatehouse, rune stones outside
  (`RUNE_SHADER` glows their runes), a grand waypoint, tents and lantern-hung oaks inside, the old forest beyond, and a
  dusk/mist mood (`Game._zone_env`, `theme.forest_camp`). The grand waypoint now replaces the central
  bonfire at (3.5, -5), with an open forecourt, paths around its back wall, and the forge moved outward
  (jj, 2026-11-03). The two guardian statues stand wider apart outside the waypoint wall, with just two
  flags set farther back (18 m between statues; 11 m between flags, 6 m behind the statues);
  their collision positions share the placement constants in `WaypointGrand`.
  New characters enter at (0, 17) on a clear southern approach to walk into the square;
  the `new_player` spawn is separate from Continue, portals and waypoint arrivals.
  The small cooking fire at the southern edge retains item burning. `scripts/vendor_court.gd` rebuilds the
  four shop frontages around their detailed workshop models: braced timber, iron fittings, trade signs,
  paired hanging lanterns and terrain-following stone forecourts. A soft warm key light makes each keeper
  readable against the cool blue waypoint; forge/alchemy colours stay local to their work areas. Captain
  Roth also gets a warm key. Frontage posts register their collision at the same transformed positions as
  the models; the centre stays open. Paving uses one MultiMesh per shop, shared materials/meshes, and the
  new lights do not cast shadows or flood the square's fog. Shop positions, inventories and interaction
  rules remain in `ForestCamp`/`Data`.
  The workshop cores and other detailed props are Meshy assets (concept image, then image-to-3D),
  prepared in Blender: props by `tools/blender/prep_prop.py` into `assets/models/camp/`, trees by `prep_tree.py`. The
  lantern and the palisade section were re-made in the visual overhaul (2026-11-02: new Meshy models re-baked onto
  clean UVs by `tools/blender/camp/rebake_prop.py`, so the importer can make LODs; the palisade is 4.2 m tall).
  The shopkeepers are Meshy characters rigged by Meshy and animated from its clip library (`meshy.py rig` /
  `animate` / `library`), cleaned by `tools/blender/prep_npc.py` into `assets/models/npc/`; `Inter._animate`
  plays their work clips, turns them to face the hero and has them talk when he comes near (clips listed in
  `ForestCamp.SHOPS`). Their library clips walk the hips about (Catching_Breath strode 4.6 m out of the forge),
  so `ForestCamp._pin_root` pins every clip's hips over the keeper's spot. The camp is "The Forsaken Wilds"
  (`Data.ACTS[0]["town"]`); its smith Halvar Emberhammer works inside his forge behind the anvil (a SHOPS entry's
  `"inside"`: his spot in the stall's frame; `"stay"` in its clips: he never turns from his work and greets once a
  visit; his `radius` reaches the stall's front, since the stall is solid). His hammer rings the anvil on each blow (`anvil`: five layered Kenney takes; `Inter._strikes` hears the
  hand bone stop falling; a SHOPS entry's `"strike"`), `tools/anvil_test.gd`. Screenshots: `tools/camp_shots.gd`.
- **The camp's guards** (`scripts/camp_guard.gd`, `CampGuard`, jj 2026-11-04; notes and what's to come in
  `docs/guards.md`): Warden Bram, Sentry Kell and Ironfist Varg, armoured hand-to-hand fighters on their rounds in the
  Act I camp (`CampGuard.GUARDS`: posts, three attack slots each, `"skill"` empty until their skills are made). Meshy
  bodies on the playable 24-bone rig with 26 library clips each, merged and measured by
  `tools/blender/guards/prep_guard.py` into `assets/models/guards/<id>.glb` + `<id>.json` (clip lengths, ground motion,
  turn angles baked out of the turn clips, strike landing moments). They patrol by `World.find_path`, scan at posts
  (turns in place, looks, alert, warm-ups), stop and watch a hero coming near (head tracking: `CampGuard.HeadLook`, a
  SkeletonModifier3D), and fight a monster in the ring (circling, strafing, stepping back, the slots' strikes; host-only
  damage via `Enemy.take_hit`). Bodies move by the clips' measured motion through `World.move` (no foot sliding).
  Rim light and a soft fill keep them readable at dusk. `--guard-fight` (zombies in the camp), `tools/guard_test.gd`
  (via `_late.gd`), `tools/guard_shots.gd -- outdir`.
- **Day and night** (`scripts/day_night.gd`, `DayNight`, `Game.day_night`; jj 2026-11-04): Act I's camp runs through
  a day every `DAY_LEN` (30 min) by the wall clock, so co-op partners share the hour with nothing on the network. The
  one shadowed light (`Game.sun`) is the sun (east to south to west, up to `SUN_ELEV`) or the moon (the night's arc),
  whichever is up, so shadows swing and lengthen; `KEYS` is the camp's look by the hour (sky, ambient, exposure, mist
  and volumetric fog, saturation, bloom, the hero's light; night is the tuned forest-camp dusk), blended between keys.
  Lights in the `flicker` group are scaled by `Game.lamp_mul` (lanterns, candles: out by day) or `fire_mul` (meta
  `fire`: low by day); candle cores in `DayNight.LAMP_GROUP` are hidden by day. Fireflies after dark; a message at
  dusk and dawn, when the camp's bed turns to `night_forest` after dark and back to the wind by day: five unique nights
  in turn (jj), takes 0..4 = far wolves (jj's pick), deep woods and an owl, a summer cricket chorus, frogs in a bog, a
  gale (ElevenLabs, prompts `night_*` in `tools/audio/spec.py`), one a night by `DayNight.night_take` (nights counted
  on the wall clock from sunset, so a party hears the same; `Sfx.play_music`'s `amb_take`), all `Sfx.LOOPS` beds;
  the HUD clock (`DayClock`, `UI.day_clock`: a dial on the corner map's ring with the sky, sun or moon and the time,
  shown while the cycle runs); the admin column's time of day (`DayNight.set_hour(h, pace)`, `live()`, Dawn / Noon /
  Dusk / Midnight, a slider, Hold / Run / Fast 30x / Live clock, Next night's sounds; this game only; `DayNight`
  runs with the tree paused so it shows behind the menu); the guards' rim and fill grow at night and the sentry carries a lantern (`CampGuard._night`).
  `Game._zone_env` enables it in the camp only (`enable(false)` puts the sun back). `-- --time 13.5` holds the hour,
  `--day-len 120` speeds it up. `tools/daynight_shots.gd -- outdir` (contact sheets through the day, and checks);
  `tools/daynight_test.gd` (headless, via `_late.gd`: lanterns, moon, the night beds and their turn, the admin
  controls, the HUD clock).
- **The World-Tree Island** (`scripts/camp_island.gd` `CampIsland`; jj's pick, concept 2 of three, 2026-11-04): Act I's
  camp adrift in space (`ForestCamp.ISLAND`). The ground ends `ForestCamp.ISLAND_R` from the middle at a gently
  ragged edge (`World.island_r`/`island_edge`/`off_island`; `terrain_patch`'s `clip` draws edge vertices onto it, so
  the ground ends in a smooth line); nothing grows or stands past it (trees, rocks, grass `grass_ground`, ferns). The
  north (moor) and west (coast) gates are barred (`CampIsland.bar_gate`, no exits): the waypoint is the way out, and
  the moor's waypoint is always known in Act I (`Game.waypoint_known`). Round it: the Meshy underside
  (`assets/models/island/underside.glb`: prep_prop, then `tools/blender/island/level_top.py` levels its top, cuts
  its middle and the coarse rim bushes out; scaled so its rim sits at the edge), the World-Tree's roots hanging off
  the cliff (`roots.glb`), four waterfalls out of the cliff into the void (`FALL_SHADER`), rocks drifting by the edge
  and asteroids tumbling round it (Meshy `asteroid1..3.glb` and NASA's Bennu `bennu.glb`, its own dark stone; fog
  off on them), comets streaking past (a Meshy-painted card along the path, `COMET_SHADER`), and the coast and the
  moor as small far islands (`isle_coast.glb`, `isle_moor.glb`, dimmed). The sky is `CampIsland.space_sky()`
  (Game.`space_sky`, set by `_zone_env`; ambient from a colour, fog thinner: DayNight's `thin`): ESO's real 360°
  Milky Way panorama in galactic coordinates (`band_n`, `core_dir`), a few crisp stars, faint aurora, and Saturn
  drawn analytically in the sky shader (its real surface and rings, `planet_dir`, `planet_r`). Textures and their
  licences: `assets/textures/space/` (`CREDITS.md`; `tools/space_textures.py` makes them). The scroll wheel zooms
  out further there (`Game.zoom_max` 2.2; past 1.3 the view drifts to the island's middle), and zoomed out the
  **orbit camera** turns: middle-mouse (or Alt + left) drag (`Game._orbit_input`, `orbit_yaw`/`orbit_pitch`,
  `_orbit_offset`), down past the edge to the underside; zoomed back in it eases home. Any zone raising `zoom_max`
  gets it. Previews: `tools/camp_aerial.gd -- out.png [height] [hour] [edge|game|at:x,z] [nounder]`.
- **The living camp** (jj, 2026-11-04): every trader has thirty moves (`ForestCamp.ACTS`: Meshy library clips
  animated once on the auctioneer's rig and moved onto each keeper by `tools/blender/npc_add_clips.py`, their hips
  pinned) and the strollers a round (`ForestCamp.lively`: their spot, along their stall, the waypoint's square; walk
  clips `STROLL`). `CampSocial` (`scripts/camp_social.gd`, a node in the camp) pairs people who are free and close
  (a guard idling at his post, a keeper at their stall; group `camp_walker`), turns them to each other and plays a
  conversation in turns (talk clips for one, listening/nodding for the other), then a wave or a bow; a strolling
  trader now and then walks over to visit another's stall (`Inter.walk_to`), and traders wave to guards walking
  by. The guards have the same talk clips (`npc_add_clips.py ... --keep`, which keeps their meshes and 2k
  textures), and their post idles swapped the warm-up stretches for a hand on the hip, a look round, a drink.
  **The smith forges** (`scripts/smith_forge.gd` `SmithForge`): while he works (`Inter` clips `"forge"`), his body
  stands in its idle and his arms are placed by a one-pass two-bone IK (`_reach`, `_wrist`) after the animation
  (his AnimationPlayer is advanced by hand): the war hammer (taken off the hand bone, `top_level`, placed by
  `_hammer_basis`) swings over his shoulder and its face lands on the forge's anvil (`ANVIL`, in the forge model's
  frame) with a ring, sparks and a flash; his left fist holds the Meshy tongs with the glowing bar
  (`assets/models/camp/props/tongs.glb`) on the anvil, turned now and then, and every `QUENCH_EVERY` blows plunged
  into the bucket in steam (`quench`). Fists: `tools/blender/npc/fist_keys.py` adds `fist_R`/`fist_L` shape keys
  (Meshy's rigs have no finger bones), set by `ForestCamp.fist` wherever a keeper holds something. **Ravens**
  (`scripts/raven.gd` `Raven`, `scripts/camp_ravens.gd` `CampRavens`): the Meshy raven rigged by
  `tools/blender/npc/rig_raven.py` (perch cut by its colour, bones by region) and posed in code: perched acts (look,
  peck, preen, shake, stretch, caw, hop, settle), take-off, flapping and gliding flight that banks, a flared landing;
  roosts found on the roofs themselves (`_measure`: the highest surface under points along each building, ForestCamp
  `roost`), and on the ground round the square; a hero (or a walker) near puts them up (`raven_wings`, `raven_caw`).
  **Smoke**: a Mantaflow chimney plume (`smoke_flipbook.py` kind `chimney`, DemonKitFx BOOKS) loops out of the
  forge's chimney, off the alchemist's cauldron and the cookfire (`ForestCamp._smokes`). `tools/camp_life_test.gd`
  (in the gate) checks all of it; previews `tools/forge_clip.gd`, `tools/raven_sheet.gd`, `tools/guard_clip.gd`.
- **Nameplates and the trade window** (`scripts/vendor_ui.gd`): `VendorUI.Plates` (in `ui.plates`, under every
  window) floats a gold-trimmed plate with the name and trade (`VendorUI.ROLE_TITLES`) over each vendor and Varro,
  click-through, fading with distance, lit when hovered. The trade window (`UI._build_shop`, `open_shop(mode,
  title, items, who, greet)`) is headed by the trader: a live portrait (`VendorUI.Portrait`, their model in its
  own little world, from the keeper's `npc_file` meta or the humanoid's `look`, greeting then idling), name, trade,
  greeting and your gold; tabs by kind (`UI.SHOP_KINDS`; `shop_view` maps cells to `shop_items`) and a price on
  each cell, red when you can't afford it. `UI.trade_with` is the NPC whose window is open: walking more than 3 m
  past their `radius` closes it (`UI._walked_off`, the stash too). `tools/vendor_test.gd` checks all of it with
  the smith; `tools/vendor_shots.gd -- outdir [role]` screenshots a trader.
- **Progression and the Battlegrounds' gear rules** (Blaine's progression overhaul, `docs/queue_progression_overhaul.md`):
  skills unlock by level (`Data.skill_locked`, each skill's `"lvl"`; `Data.SKILLS_UNLOCKED = true` opens all again):
  a class's skills Q 1, E 3, R 5, F 9, G 14, every ultimate at 20 (Eternal Night, Wrath of the Pit, The Last Epidemic,
  Clown Car); the shared ones War Cry 6, Frost Nova 8, Arc 11, Earthshatter 16. A locked skill waits on the bar greyed
  with "Lv N", can't be bound (`Hero.bind` refuses it; one already on the bar may move) or cast, and is announced when
  reached (`Hero._announce_unlocks`); the Admin column's Unlock all skills opens everything. In a raid
  (`Hero.pvp_scaled`: on while `Game.bg_mode`, whose setter recalcs the hero) the act multipliers are ignored and the
  stricter `Data.PVP_GEAR_CAP` applies (the items rule everywhere else, below). The class uniques (`Data.UNIQUES` with `"cls"`, level
  20, boss_only: Hrimgar, Mossbeard and the golden chest drop one for a class near, `Game._drop_class_unique`) carry
  the raid's item effects: `"roll"` (a free dodge roll every N s, `Hero.free_roll`) or `"ward"` (a % of life that
  soaks blows and refills out of combat, `Hero.ward`). `tools/pvp_sim.gd` (classes at levels 1/5/10/20, fresh vs
  geared, Monte Carlo duels), `tools/skill_unlock_test.gd`, `tools/pvp_items_test.gd`.
- **Items** (the items rework, `docs/queue_items_rework.md`; Blaine: level and skills carry a character, gear helps,
  in PvE and PvP alike): every affix rolls `Data.AFFIXES` times `Data.AFFIX_SCALE` (`Items.roll_affix`; Gold and
  Magic Find unscaled), rares roll `Data.RARE_AFFIXES` (2-3), base defence counts for `Data.GEAR_ARMOR`
  (`Items.defense_of`), percentages are capped across all gear (`Data.GEAR_CAP`: +5% run speed, 25% attack speed and
  resist, 4% life steal), and a weapon hits for the level's damage times its quality 0.9-1.05, then its Enhanced
  Damage and +Damage (`Data.weapon_damage`, `Hero.recalc`; tooltips show "Weapon damage at level N"). Acts II-III
  make items `Data.RUNS` `"power"` stronger (x1.6, x2.4; `Items.empower`, `Game.power_mult`), with modest monster
  multipliers to match. Items carry `"gen"` (`Data.ITEM_GEN`); an older one is rebuilt once on load
  (`Items.upgrade` from `Hero.from_save`: affixes rescaled, rares trimmed to their best three, uniques remade from
  `Data.UNIQUES` keeping enchant and temper, A2/A3 strengths moved by `Data.OLD_POWER`; uniques are remade on every
  generation bump, so bump `ITEM_GEN` when a unique's numbers change). Enchanting and tempering are
  scaled to match (`Items.ENCHANT_DEF`, `TEMPER_ED`). Level-20 gear is worth about x1.6 over none (damage x life).
  **Utility affixes** (`Data.UTILITY`, at most one per item): run speed, `stam` (dodge stamina, `Hero.roll_cost`),
  `cdr` (`skill_cd`), `pot` (`drink`), `ten` (stuns and slows, `Hero.cc_k`). **Unique effects** (`Data.ITEM_EFFECTS`,
  one per unique, everywhere, the strongest of each counts): roll, ward, burn, chill, kill_heal, dash
  (`Hero._item_effects`, `dash_t`). **Rewards**: random uniques are rare (`Items.random_drop`); each boss has its own
  (`Data.BOSS_LOOT`, `Game._boss_loot`: the first kill drops one, then `BOSS_LOOT_CHANCE` + `BOSS_LOOT_LUCK` a dry
  kill, `Hero.boss_luck` saved); the bonfire's Reforge (`UI.reforge_request`, `Items.reforge`) rerolls a magic or rare
  item's weakest affix for one Sloth material. **Invisibility**: the Veilmother's Locket (`"phial"`) gives a Shadow
  Phial each raid (`Game.give_raid_phials`); drunk, `Hero.invis_t` (6 s): monsters lose him (`hidden_t`), partners
  see a shimmer within 4 m (bit 2 of the state's 15th number, `Hero._show_invis`), any blow or cast ends it
  (`break_invis`); on a host or the raid server a partner's unseen bit (`Hero.net_invis`) hides him from monsters too
  (`Enemy` and `Game.target_for` pick a hero they can see), and the Compatibility renderer (no `transparency`) hides
  his body instead. PvP burns and chills reach other players (`Net.sv_pvp_dot`, the "chill" effect; `Hero.burn_t`).
  **Every player-on-player message** (a blow, crowd control, a burn) passes `Battlegrounds.pvp_pair` on the server (a
  raid on, both alive, within `PVP_RANGE`); the same control from one player on another lands at most every
  `PVP_EFFECT_GAP` s (`pvp_effect`); a burn is scaled like a blow and counts for the kill (`pvp_burn`).
  `tools/items_rework_test.gd`, `tools/pvp_server_test.gd`; re-run `tools/balance.sh` after changing any of it.
- **The Battlegrounds sandbox** (`scripts/sandbox.gd` `Sandbox`, zone `"sandbox"` "The Proving Crypt";
  `scripts/bot_brain.gd` `BotBrain`): the admins' testing arena, opened from the Escape menu's Admin column
  (`Game.open_sandbox` / `close_sandbox`; the character is saved and set aside, `char_id` cleared so nothing inside is
  saved, and loaded back on leaving). Local and offline: the admin becomes any class at level 1/5/10/20, fresh or
  geared (`Sandbox.outfit`), spawns bots (`Hero.bot`: a full hero played by a `BotBrain` through the same calls as
  the mouse: `use_skill`, `cmd_target`, `free_attack`, `Dodge.start`, `drink`; `bot_hold` is its held button) and
  monster packs. PvP is the raid's: each hero has an invisible stand-in (`Enemy.sandbox_hero`) that takes every
  skill and blow and deals it to the hero at `Battlegrounds.PVP_MULT` through `take_hit`, forwards stuns and slows,
  and never takes its own hero's blows (`Hero.striker`, set at the top of each hero's `_process` and by a summon
  before it strikes). Monsters go for the nearest hero (`Game.target_for`, `all_heroes`). A bot's screen effects,
  messages and the testing switches are the player's only (`Hero._mine`). The panel's meters (`note_hit`) give
  damage a second over 5 s, totals and kill times. `tools/sandbox_test.gd` (`--fixed-fps 60`), `tools/sandbox_shot.gd`.
- **Skill bar and bindings** (every class, including new ones): the bar has a big slot for each mouse button and six
  hotkeys (Q E R F G V); any skill can go on any of them (`Hero.binds`, saved per character; `Hero.default_binds`:
  left mouse `attack`, right mouse the class's first skill, the class's first four skills on Q-F). `attack` and `block` are
  `Data.COMMON_SKILLS` (`Data.skills_known(cls)` = class skills + common). Input goes through `Game._use_bind`
  (held buttons recast when ready; `Game.skill_held(id)` for Block and Drain Life's channel). Click a bar slot or
  open the skills window (K) to rebind, or drag: a skill from the skills window onto a slot, one slot onto another
  (they swap), or off the bar (cleared; left mouse never empties). Drag uses Godot's `set_drag_forwarding`
  (`UI._skill_drag`, `UI.drop_skill`, the clear in `UI._notification`); a click without a drag opens the slot's menu.
  Block: 80% less damage from the front (missiles stopped with a shield).
  Art: Meshy-painted frame and sockets in `assets/textures/ui/`. A new class needs nothing extra. Painted skill
  icons: `SkillGlyph.painted(id)` draws `assets/textures/skills/<id>.png` over the whole socket when it exists (greyed
  when the skill can't be used) and the drawn glyph otherwise; the Plague Doctor's seven (his six and his cane attack,
  `plague_attack`, picked by `_icon_id`) are a Meshy 3x3 grid cut by `tools/skill_icons.py` (`prompt`, `meshy.py
  draw`, `cut`; the same palette and cutter as `talent_icons.py`; lossless import). Another class gets them by adding
  a `CELLS` entry and painting its grid.
- **Talents** (`scripts/talents.gd`, the window is N; `tools/talent_test.gd`, `tools/talent_shot.gd`): three trees per
  class of seven talents in four rows (2, 2, 2, then a capstone); a row opens with 0/3/6/10 points spent above it in
  that tree (`Talents.ROW_REQ`), and a rank can't be taken back if a deeper talent would lose its row. One point a
  level from level 2: `Hero.free_talent_points()` = level - 1 - spent (nothing stored but `talents` {id: ranks} in
  the save). Reset is free; Auto-assign spends free points along `Talents.AUTO[cls]`. A save without `talents` gets
  that build for its level (`Hero.from_save`); a bad one is cleaned (`Talents.clean`). Effects are data: each
  talent's `fx` adds up into `Hero.tfx`, read with `Hero.talent(key)` (the key list is at the top of talents.gd):
  flat stats join the gear's in `recalc`; `dmg`/`dmg:<skill>` through `Hero.dmg_mult` (pass the skill as
  `_hit_enemy`'s `src` when it isn't the attack in progress), `cost:`/`cd:` through `Hero.skill_cost`/`skill_cd`
  (use those, not the raw `Data.SKILLS` numbers), the battle buffs through `Hero.buff_mult`, and each class special
  where its skill is. Icons are painted with Meshy, a 3x3 grid per tree (7 talents, the tree's emblem, a spare),
  cut into `assets/textures/talents/<id>.png` and `<cls>_tree<N>.png` (128 px, mipmaps) by `tools/talent_icons.py`
  (the prompts are in it; `prompt`, then `meshy.py draw`, then `cut`); greyed by a shader until a point can go in.
  A new class needs a `TREES` and an `AUTO` entry and its four grids; without a painted icon a talent falls back to
  its `icon` glyph (a skill id or a `t_*` in `SkillGlyph._talent_icon`). The balance sim gives its bots the auto build.
- **Globes** (`scripts/globe.gd`, `Globe`): liquid that surges after a hit, ripples on a heal, pulses and shakes
  when low, darkens when critical, swirls after a cast, rises slowly with regeneration, sends a wave up on a big
  restore, and grows with maximum life/mana. Meshy frame `globe_frame.png`, Blender glass `globe_glass.png`
  (`tools/blender/ui_glass_orb.py`, added over the liquid). Standard for every class; a special character can
  override with a `"hud"` entry in `Data.CLASSES` (see `Globe.set_style`). Preview: `tools/globe_demo.gd`.
- **Waypoints** (`Data.WAYPOINT_ACTS`, `WaypointPanel` in `scripts/waypoint_panel.gd`, `Game.waypoint_go`): one entry
  per act (its `run`, tab numeral, Meshy banner `wp_actN.png`, boss, and its waypoints: `id`, `zone`, `kind`). An act
  opens once the act before it falls (`Game.act_unlocked`, from `max_run`); a waypoint opens once the player touches
  its stone (`Game.waypoint_known`, per act in `run_progress`). The window has a tab per act, the act's banner and
  route (lit waypoints travel, across acts too via `switch_run(run, zone)`); it closes when you walk off the stone
  or click outside it. Add an act: a `Data.RUNS` entry, its zones, an entry here (its `group`, e.g. "acts" or "ancient"; groups are `Data.WAYPOINT_GROUPS`, and a group's heading appears once it has an entry; the tab row scrolls when it overflows). Add a waypoint: a point here + one
  line in that zone's builder, `add_waypoint("<id>", Vector3(x, 0, z))` (stone, colliders, its own arrival spot;
  a zone can hold several). The camp's stone is the grand dais (`WaypointGrand`, `scripts/waypoint_grand.gd`): models in
  `assets/models/waypoint/` (`dais.glb` modelled by `tools/blender/waypoint/build_dais.py`, its floor rings' gaps are the carved
  rune channels the glow sits in; Meshy crystal, brazier, guardian, banner, torch, pillar re-baked by `camp/rebake_prop.py`, the crystal
  split and the modelled flames cut by `waypoint/split_parts.py`; each missing model falls back to its code blockout); wakes as a
  hero nears, flares on arrival and when the window opens; `add_waypoint(id, p, cobble, true)`, colliders in `SOLIDS`; `-- --old-waypoint` shows the old
  stone). Its look is jj's concept picture made real (2026-11-01): **the rune lettering** on the flagstones is
  `assets/textures/waypoint/rune_rings.png`, drawn by `tools/waypoint_runes.py` (an Elder-Futhark-like alphabet, ring
  lines, an octagram and sigils laid in rings at the dais's radii, one band per channel: R the outer rim ring and the
  inner ring, G the great ring, B the ornate band; lossless, mipmaps) on a plane over the floor with
  `WaypointGrand.RUNE_FLOOR_SHADER` (each stroke lit from its heart out through a halo from the mask's blurred mips, the
  groove round it darkened, bands lit outer to inner with the wake, pulse rings running out from the socket, the outer
  and inner rings turning slowly); **the crystal** is a second Meshy model made for the picture (`crystal_rune.glb`:
  a Meshy concept of a sapphire hexagonal bipyramid with carved glowing runes, image-to-3D, then
  `tools/blender/waypoint/prep_crystal.py` (planar decimate keeps the facets sharp, one UV island a facet, the
  colour, normal, roughness and metal baked onto it, origin at its centre, 3 m tall); the first model's socket and
  orbiting shards stay, its crystal piece is the fallback) at `CRY_Y` 3.35, wearing `CRYSTAL_SHADER` on its texture
  (dark faceted glass, its cracks and rune the light inside, energy crawling along cell borders, a cold rim) with `ARCS`
  arc quads (`ARC_SHADER`: a bolt that strikes, holds a moment, moves on) and hangs in **the column of light**
  (`COLUMN_SHADER` core and sheath on capless cylinders to `COLUMN_TOP`, dimmed where the crystal hangs, `BOLTS_SHADER`
  lightning wandering up; FogVolumes for the shaft in the air on High/Ultra, Forward+ only); **the stone is wet**
  (`wet_stone`: `Mats.PROP_SHADER` plus puddles and damp, whose mirrors are faked from the column's axis and the
  fires in `mirrors`, `_set_mirrors` in `_ready`, so the paving catches the blue and the orange on every preset); a low
  cold light (`light_low`) rakes the steps, the statues and the hero; two fire bowls (`FIRE_BOWLS`: `firebowl.glb`,
  Meshy's iron bowl of coals on a rune-carved stone pedestal, `camp/rebake_prop.py h=1.25`, with a real "brazier"
  fire and a bonfire-sized light; the brazier model without it) flank the approach, two torches stand in the back wall's gap (`TORCH_AT`), four
  banners (`BANNERS`), the guardians (`GUARDIAN_AT`) in the wall's breaks; mist (InfernalFx's smoke shader, pale)
  creeps over the steps, sparks rise in the column, motes drift. The four braziers' blue fire (`FireFx` "spirit") and
  the bowls' coals (below) are their own work. `tools/waypoint_lab.gd -- outdir [frames] [step]
  [game|ref|close|high] [quality]` renders it alone on a slab under the camp's dusk from the game's camera in a few
  minutes (`--fixed-fps 30`; `--rendering-driver vulkan --rendering-method forward_plus` with lavapipe shows the
  High look: glow, volumetric fog). The window's **Battlegrounds tab** shows `Data.WAYPOINT_BATTLEGROUNDS` (the Hollow Crypt: its Meshy painting
  `wp_bg_crypt.png` on the banner, a card laid out like a route stop with the round's numbers from `Battlegrounds`'
  constants, the stakes in plain words, who goes down with what at stake, the server and whether it answers: an
  ENet probe dropped on the handshake, `WaypointPanel._probe_*`). Descend -> `Game.waypoint_battleground`: a last word
  on the stakes (dialog), then `_waypoint_descend` (the dais flares, `WaypointGrand.pulse`) and `start_battlegrounds` with the
  character playing against `Game.bg_server_address()` (the address last used, else the build's), the crypt's
  painting behind the loading words (`set_loading_art`). `bg_from_waypoint`: extracted, fallen or cut off, the raid
  ends back on this dais (`_leave_battlegrounds` -> `_bg_home_camp`) instead of the title's Battlegrounds window (a
  raid from the title still ends there); not from co-op. Tests: `tools/waypoint_grand_test.gd`
  (it loads WaypointGrand at run time), `tools/waypoint_test.gd` (rules), `tools/waypoint_shot.gd -- out.png [run | bg]` (screenshot; `bg` the Battlegrounds tab).
  **The braziers' coals** (`scripts/brazier_coals.gd`, `BrazierCoals`, one line in WaypointGrand's brazier loop):
  what burns in each bowl is a pile of fractured dark basalt stones, fragments and sapphire crystals on an ember bed,
  from `assets/models/waypoint/coals.glb`: a library of unique pieces (`lib/rock_NN|frag_NN|cry_NN` with `_l0`/`_l1`
  LODs, one baked atlas for the stones and one for the crystals: albedo, normal, AO + roughness, and the crack /
  vein mask in the emissive map) and four piles settled with rigid-body physics in the real bowl (`arr_K`, Empties
  whose transforms are the instances, in the brazier node's frame). Built by `tools/blender/waypoint/rock_library.py`
  from three Meshy models (concepts in `concepts/waypoint_rocks/`): stage 1 bakes Meshy's textures onto watertight
  solids, stage 2 Voronoi-fractures them (every cut capped with a procedural fresh-break material and roughened),
  makes the LODs, atlases and bakes, stage 3 (`--stage3`, from `<workdir>/library.blend`) settles the piles and
  exports. The brazier model itself was cleaned by `tools/blender/waypoint/clean_bowl.py` (Meshy's flame blob cut
  out of the bowl, the dish closed; the old one is `concepts/waypoint_rocks/backup/brazier_v1.glb`). In the game
  each pile is merged into one mesh per material and LOD (the LOD1 copy the only shadow caster); the shaders read
  the flame's own flicker from the fire's `FireLight` every frame, so the energy in the cracks (vertex COLOR.r = a
  stone's glow weight, most 0; g = phase), the crystal veins and the bed breathe with the flame; sparks and motes
  from Medium, heat shimmer (`InfernalFx.haze_mat`) on Forward+ High/Ultra. Without the glb a primitive pile stands
  in. Tests and previews: `tools/coals_test.gd`, `tools/coals_shot.gd -- outdir [frames] [step] [bowl|close|pair|top] [quality]`,
  `tools/blender/waypoint/coals_preview.py` (the piles in Eevee, no Godot).
- **Inventory (I)** (`UI._build_inventory`, jj's "Classic"): Meshy art in the action bar's iron and bronze
  (`assets/textures/ui/inv_*.png`, cut and cleaned from Meshy concepts in `exports/ui/inventory/`): a NinePatchRect
  frame (`INV_SCALE`, corners `INV_PATCH` texture px, the middle bands mirror-symmetric so they tile seamlessly,
  `draw_center` off over a tiled iron inside), the equipment in a recessed alcove with a knight's silhouette
  (`INV_EQUIP` rects and `Caption` labels), the bag's 40 sockets (`_slot(..., iron = true)`: the action bar's
  socket on a 9-patch, a rarity line inside) and the gold on a bronze plate. Every piece keeps clear of the frame's
  corner spikes and trim: `tools/inv_geometry_test.gd` samples each socket, label, the alcove and the plate against
  the frame's ornament as the 9-patch draws it. Screenshot: `tools/inventory_shot.gd`.
- **Character sheet (C)** (`UI._build_character`): Meshy frame `sheet_panel.png` (texture margin 100 so the corner
  pieces never stretch; content margins keep everything inside the gold trim), live portrait (a SubViewport on the
  shared world) in `sheet_portrait.png`, Meshy medallions `sheet_str/dex/vit/ene.png` and `sheet_plus.png`. Hover a
  stat for what each point adds (`_stat_tip`, from `Hero.recalc`); combat stats sit in a dark inset (`_combat_tip`).
  Same for every class. Screenshot: `tools/sheet_shot.gd`.
- **Skill picker** (`UI._choose_skill`, click a bar slot): the bar's own iron frame and sockets, one card per skill
  (`_picker_card`: equipped glow, the key it's on now, mana, locked level). Esc / click outside closes
  (`close_skill_picker`). Screenshot: `tools/picker_shot.gd`.
- **Skill design: the Path of Exile way** (jj, 2026-11-01; the base for every new skill, so they all play alike):
  a main skill has **no cooldown**; what limits it is its **use time** (its `DUR`/`atk_dur`, times `Data.ATTACK_PACE`,
  shortened by attack speed) and its mana. A heavy skill gets a long, readable **wind-up** (the impact late in the
  swing, `Anim.impact_at`, with its tell drawn through the cast's fx event) and hits harder to pay for the wait (about
  the damage per second of a quick skill); the dodge roll cancels a swing that hasn't landed (`Dodge.start`). Cooldowns
  are for utility (movement, warcries, summons, ultimates). Attacks follow the same rules in every scenario: the
  story game, co-op and the Battlegrounds (no crypt-only attack timing, damage or cooldowns). The model: Molten
  Fists (2 s, the blow at 1.5 s, 300% weapon damage). **Every skill follows it** (2026-11-01): Holy Nova, Phantom
  Assault, Cataclysm Slam (now Fault of the Pit, the Demon kit's R), Brimstone Hurl, Blight Bolt, Frost Volley and
  Volatile Mixture lost their cooldowns for a
  `"use"` time and a `"power"` (a multiplier on all the skill deals, `Hero.dmg_mult`) set from measurements so their
  damage per second matches their class's quick skill (heavy ones 1.2x, area ones 0.9x): `tools/skill_dps.gd -- out.json
  [level] [class ...]` casts every skill at a durable dummy and reports damage per cast and per second of its cycle. A
  cooldown is allowed only with a utility tag (`"tags"`: movement, warcry, buff, cc, trap, summon, command, ultimate,
  sustain; `skill_spec_test` refuses one without): the charges and steps, the cries and buffs, the holds and tethers
  (Soul Siphon, Haunting Grasp, Hellgrip, Soul Shackles, Storm Snare: no lock-spam in PvP), traps, Spirit Beast, the
  ultimates. **The format** (`scripts/skill_spec.gd`, `SkillSpec`; every
  field is optional and listed at its top): a skill's entry in `Data.SKILLS` carries `"style"` (its animation),
  `"use"` (seconds, final: no `ATTACK_PACE` on top), `"hit"` (0..1 of use: the impact frame, `Anim.impact_at` reads it),
  `"speed"` ("attack"/"cast"), `"lock"`, `"cancel"` (false: no dodging out), `"power"` (all its damage x), `"dmg"` (% weapon) or `"base"` +
  `"per_lvl"` (a spell's own), `"type"`, `"knock"`, `"area"` (wedge / circle / line / single), `"dot"` (burn / chill /
  slow, one per source, refreshed), `"tags"`, `"pvp"` (numbers for its blows on players in the Battlegrounds, read by
  the class's script: the Demon's damage shares and status seconds) and `"role"` (its one job in the kit, a few
  words). The timing applies by itself (`Hero.use_skill` ->
  `SkillSpec.apply_timing`, `Dodge.can_roll`); the damage when the skill's impact code calls `SkillSpec.targets(h, id)`
  and `SkillSpec.strike(h, id, e, extra, opts)` (`DemonSkills._fists` is the example; opts `"mult"` is a bonus on one
  foe, e.g. the Brand, `"dot_secs"` a talent's longer burn). If a skill's `"hit"` moves,
  move its clip's blow to match (`Demon.SHOTS`-style keys). `tools/skill_spec_test.gd` (in the gate) validates every
  entry's fields and plays Molten Fists by its data; `tools/demon_test.gd` checks the wind-up and the dodge cancel.
  **Performance**: run `bash tools/skill_perf.sh <class> <skill>` on every new or redone skill (PASS: no new
  stutters, at most 20% slower than the weapon alone in the 24-monster fight; docs/nightly/KPIS.md "Skills"). An
  effect light with shadows goes through `Fx.effect_shadow` (cheap maps, at most 2 at once), never `shadow_enabled = true`.
- **Shared skills** (jj, 2026-11-01: class-free skills, every class can use them): `Data.SKILLS` entries with
  `"cls": "any"` (`Data.shared_skills()`; `skills_known` = the class's own + shared + Attack/Block), played by
  `SharedSkills` (`scripts/shared_skills.gd`, the ClassSkills interface; `ClassSkills.of("any")`) and drawn by `SharedFx`
  (`SkillFx.play` hands them there whatever the class). The four: Earthshatter (heavy slam, wedge), Frost Nova
  (ring of ice, chills), Arc (chain lightning), War Cry (the team skill: the battle buff for him and every co-op
  partner within 8 m, `Net.send_team_buff`, and a taunt; 8 s cooldown; Flame Wave was cut, jj 2026-11-01). They play on shared styles every body has (`slam`, `cast`, `thrust`), so they set `"use"` but
  never `"hit"` (a shared style's impact is every user's, monsters' too; `skill_spec_test` refuses it). A new shared
  skill: its entry, its id in `SharedSkills.IDS` and its `impact` case (usually `SkillSpec.targets` + `strike`), its
  `SharedFx.play` case and a `SkillGlyph` icon; `skill_spec_test` casts each on the knight and the Wraith.
  **Every skill is open from level 1** (`Data.SKILLS_UNLOCKED`, `Data.skill_locked`), and every hotkey holds a skill
  (`Hero.default_binds` and `_check_binds` fill the bar from the class's own, then the shared ones).
- **Attack pace** (every class, new ones too): `Data.ATTACK_PACE` (1.2 = attacks, skill swings and casts take 20%
  longer) multiplies `Hero.atk_dur` in `_start_attack` and the casts' own times in `use_skill`; a special class can set
  `"attack_pace"` in `Data.CLASSES` (`Data.attack_pace(cls)`). Attacks whose rate the swing sets (the basic attack, skills
  with no cooldown) hit that much harder (`Hero.pace_mult` in `dmg_mult`), so damage per second is unchanged; cooldown
  skills and channels (`"channel": true` in `Data.SKILLS`) keep their damage. Weapon speed, IAS and Dexterity still apply.
- **Damage taken** shows as one red number over the hero's head (`DamageStack`, `scripts/damage_stack.gd`, made by
  `Hero.show_damage`): hits close together add to a running total that counts up smoothly and pops on each hit; 1.1 s
  after the last hit it drifts up and fades, and the next hit starts a new total. Every class gets it. Preview:
  `tools/damage_stack_clip.gd -- outdir`.
- **UI layers and screen isolation** (`UI.setup`): every control lives in one layer of `UI.root`, bottom to top:
  `hud` (globes, bar, corner map, quest tracker, target and boss bars, nameplates, the raid HUD), `windows` (inventory,
  sheet, shops, stash, fire, waypoints, skill picker), `menus` (the title and its screens; co-op and Battlegrounds open
  over the title, dimmed by `menu_shade`, which also keeps its clicks off it), `modals` (dialogs, the party vote, pause,
  F8, death, victory) and `top` (tooltips, drags, messages, sparkles). Add a new control to its layer, never to `root`.
  `_set_hud` shows or hides the whole HUD. Game input is ignored unless `playing` (and not while a zone loads), keys
  but Esc while paused. Leaving for the title (`Game.exit_to_title`) resets what belonged to the character: its death
  and victory screens, portal, XP bonus, F8 switches, a raid (left without extracting = died there, `bg_strip`) and the
  raid's act (`bg_home_run`). `tools/screen_test.gd` checks it (in the nightly gate).
- **Visual audit and overhaul** (`docs/visual/AUDIT.md`, `docs/visual/checklist.csv`, tools in `tools/visual_audit/`):
  the ranked roadmap and every asset's scores and status. `frame_stats.gd` measures draw calls and primitives per pass
  **and per viewport** in any zone and preset (the cloud's software Vulkan runs the real Forward+ renderer: counts are
  exact, frame times meaningless; `--fast` drops screen-space effects, which add no geometry); `scene_census.gd`
  lists every zone's geometry; `glb_audit.py` / `uv_report.py` measure models (UV islands, normal-map strength,
  albedo); `model_sheet.py` + `contact_sheet.py` render Blender sheets; `skill_shots.gd` frames any class's skills.
  Rules it taught: **a SubViewport sharing the game's world must be switched off explicitly when hidden**
  (`UPDATE_WHEN_PARENT_VISIBLE` asks the parent viewport, the screen, so the character sheet's portrait rendered the
  whole scene and its shadows every frame: 66 M of the camp's 150 M primitives); **multimeshes go through
  `World.mm_chunked`** (one the size of the map is never culled and lands in every shadow pass, six per shadowed omni
  light); **Meshy models get no LODs** (their thousands of UV islands leave the importer nothing to simplify; re-bake
  from Meshy's full-detail output, `tools/blender/camp/rebake_prop.py`); shadow-casting fires join `Grade`'s budget
  (`FireFx.make`; `Grade.pick_shadows` gives budgeted omni lights dual-paraboloid maps, 2 passes instead of a cube's 6:
  camp +5% fps, nightly 2026-11-03; `--omnicube` for comparisons); the sun's cascades are fitted to the camera every frame (`Game._fit_shadows`, distances follow the
  zoom; `_shadow_hold` while the minimap captures); the hero's rim light is in every zone (`Grade.RIMS`, picked by
  `Game._rim_kind`). `normals_from_albedo.py` gave the 27 models whose Meshy normal map was flat a detail map
  (island-aware, no seam ridges); `smooth_normals.py` re-shades faceted round props in place (normals only);
  `metal_lift.py` gives Meshy's near-black metal its reflectance back (a metal's colour IS its reflectance: the
  armoured knight's plate reflected 5%; lifted where the metal map says metal, cloth untouched: knight_mocap,
  knight_armored, fallen_reaver, the trap); `emission_from_albedo.py` turns painted embers into an emission map (the
  Ashen King's cracks and eyes, KHR_materials_emissive_strength). The hit flash (`Enemy.FLASH_SHADER`: rim-weighted,
  fading; `Enemy.flash_color` for a coloured one) replaced flat white cut-outs (the swing trail got the same kind of
  fix on staging, `Hero._trail_shader`; its UVs are clamped before `pow()`, whose NaN on a hair-negative UV drew
  black specks). Each class has its own visual language (`HolyFx` knight, `InfernalFx`/`DemonFx` demon, `WarlockFx`
  fel fire, `WraithFx._spirit_burst`/`_soul_ring`, `ArrowFx` archer, `ElementalFx` for the shared skills and the
  monsters' slams, novas and summonings, `PlagueFx` the Plague Doctor's glass, liquid and fumes): no hero's skill uses
  the generic `Fx.burst`/`ring`/`flash`/`pillar` now (`SkillFx._default` keeps them as the fallback for a new class's
  undrawn skills; the Demon's accents are `DemonFx.embers`/`flare`/`fire_wave`, the Archer's marks
  `ArcherFx.hunter_mark`). Give a new skill shapes of its own, not a recoloured burst. Telegraphs (`Fx.telegraph`,
  `arc_telegraph`) are a rim, a faint wash and a fill sweeping out to meet the rim on the impact frame (added light). Hits throw streaks (`Fx.streaks`: sparks, blood). Decals on the
  ground sit 0.06-0.08 m up (the road's surface is above `height_at`). `special_shots.gd` frames monsters' heavy
  blows; `shader_check`-style runs (draw each new material once under xvfb) catch shader compile errors that the
  headless tests can't. Candidates are judged in the game renderer, not in model sheets:
  `oak_compare.gd` (oaks as the game builds them, with leaf clusters) and `body_compare.gd` (two copies of the mocap
  knight); the procedural oak (`tools/blender/trees/oak_gen.py`) lost to the Meshy oaks there and was not adopted.
  The ground: the cobbles are `Mats.TERRAIN_SHADER`'s `cobble()` (domed, chipped, worn flagstones; judge changes in
  `terrain_lab.gd`, a strip of road without a zone); the dirt has pebbles and grit (`ground_detail`, off on Low) and Act
  I's forest floor fallen oak leaves in drifts (`litter`, set in `World.terrain_patch` when `oak_forest`). Every zone's scattered rocks and the old roads' kerbs are Meshy
  (`assets/models/rocks/`, `Props.meshy_rock`/`boulder`/`seat`, `World.kerb`), and the crate, barrel and log pile
  (`assets/models/props/`, `Props._clutter_into`), and A2's columns, stumps, drums, tombs, milestones, fountains and
  triumphal arch (`assets/models/roman/`, `Roman._meshy_column`, `_set_piece`), and the aqueduct's bays, standing and
  ruined (`Roman._bays`, widths in `AQ_W` so the piers meet the old collision), and the colosseum's outer arcade
  (`Aurelia._arcade`, each bay the step to the next plus one shared pier) and the arena's podium wall (`Aurelia._podium`,
  one section over three runs; the runs beside the Gate of Life stay code-built) and its braziers (`Aurelia._brazier`); the
  stands draw with `Roman.seats()` (travertine seat slabs and ashlar courses, joints in world space); the city wall and
  gate towers (`Aurelia._city_wall`: the wall 5.8 m tall where the boxes were 7.3, collision unchanged);
  all re-baked on clean UVs, with the
  procedural versions as the fallback. Meshy props draw with `Props.MESHY_PROP_SHADER`, which has the same see-through
  near the hero as `Mats.PROP_SHADER` (keep it when changing either). The glb pieces placed with their own material
  (the camp, fort, coast, islands, lairs, the crypt's dressing) get it from `Props.see_through(world)` at the end of
  `World.build`: every static mesh 1.5 m or taller on a plain opaque StandardMaterial3D (surface, override or a
  multimesh's mesh) is given `SEE_THROUGH_SHADER`, StandardMaterial3D's own sums plus the see-through, one copy per
  material; skinned, glowing, see-through and shader materials are left alone, and a node with meta `keep_material` is
  skipped with its children. Its caches are cleared after each walk (held across zones they kept every visited zone's
  textures in video memory). `-- --no-see-through` turns it off for comparisons; `tools/visual_audit/see_through_check.gd
  -- town lair coast` lists what dithers in each zone and what tall mesh still can't. World generation draws from `World.rng`: a visual change must keep its calls (count and order) or every
  rock, tree, footprint and spawn after it moves (and co-op peers must agree). Check with
  `tools/visual_audit/layout_dump.gd` (one zone per process) and diff against the old build.
- **Performance KPIs** (`scripts/kpi.gd` `Kpi`, `docs/nightly/KPIS.md`): the official numbers. Scripted, deterministic
  scenarios (camp, moor, fight, boss, arena, crypt, server; `Kpi.SCENARIOS`) run in any build with
  `-- --kpi <scenario> out.json [--quality N] [--secs N]` (the server: `-- --server --kpi server out.json`), measuring
  fps, 1% low, p99 frame time, hitches, load time, main thread, GPU, draw calls, triangles, memory; then quit.
  Low and Medium cap the 3D view's pixels on big or Retina screens (`Game.apply_render_scale`, FSR 1); `--render-scale N`
  fixes the 3D scale (2.0 = a Retina screen's cost on a 1080p one).
  `tools/nightly/bench.sh` runs the suite (plus the download size), `tools/nightly/kpi_push.py` stores it in the KPI
  database on the staging server, Grafana draws it (https://<staging>/grafana/), `sh tools/kpi_query.sh latest` reads it.
- **Instancing and shadows** (nightly 2026-11-02): `Props.multimesh` splits instances spread wider than 24 m into
  16 m cells (a MultiMesh is culled as one box: one forest-wide MultiMesh was drawn whole into every shadow pass);
  it returns the first cell and the others copy its settings (deferred). A mesh with a `shadow_mesh` meta casts its
  shadow from a shadows-only twin MultiMesh (`Flora.shadow_twin`: the Meshy oaks, their leaf cards cut from the baked
  `assets/textures/fx/foliage_mask_<kind>.png`, `tools/bake_foliage_mask.gd`; rebake if `FOLIAGE_SHADER`'s
  needles/leaves/fern change). SSIL is Ultra only, SSAO outdoors Ultra only (indoors from Medium; `Game.apply_quality`
  reads `indoor()`): they cost ~7 ms each and showed nothing there.
- **Nightly lab** (`tools/nightly/`, `docs/nightly/README.md`): two launchd jobs on the Game Factory Mac, `perf` (01:00)
  and `mode` (04:30), each on a fresh `staging` with its own log (`docs/nightly/perf/LOG.md`, `docs/nightly/modes/LOG.md`:
  lessons, then one row per attempt), the KPI benchmark before and after (slower = not shipped), the gate, a push to
  `staging` and a Discord report. `bash tools/nightly/install.sh` installs or updates them.
- **The admin role** (Nakama, `deploy/nakama/modules/ashen.lua`: `admin_status`, `admin_check`, `admin_set`; the
  "admins" collection only the server writes): `CloudSaves.ensure` asks after signing in and an admin account gets
  the dev tools in any build (`Game.account_admin`; the Admin column shows the account id). Grant it:
  `sh tools/admin_role.sh <account id> on "name"` (runs on the staging server with Nakama's runtime key, which never
  leaves it). The Battlegrounds server turns away a non-admin wearing "Go to level 20" gear (items marked `"boost"`,
  `Battlegrounds.gear_ok`, every `GEAR_CHECK` s; without Nakama the per-PC ids in `user://bg_server/admins.json`).
  In a raid the Admin column has the round's controls (`Net.send_bg_admin` -> `Battlegrounds.admin_cmd`, refused
  without the role): Restart round (the crypt collapses, a new round in `ADMIN_RESTART` s that runs off the clock,
  `forced`, until it ends), Open gates (skips the antechamber), Open portals; and an admin may join after
  `JOIN_CLOSE`. `tools/bg_admin_test.gd` (server + client). Saves stay the player's own (client-written), so this stops honest
  clients and casual edits, not a modified game.
- **Class against class in PvP**: `Data.PVP_CLASS` (what each class deals to and takes from another player; only PvP
  blows, `Data.pvp_scale` in `Battlegrounds.pvp_hit` and the sandbox's stand-ins), tuned with `tools/duel_sim.gd`
  (`-- levels=20 rounds=6 mirror`: real bot duels in the sandbox, every pairing, win rates and kill times; flags a
  pairing past 70/30 and geared not beating fresh).
- Developer tools (`Game.dev_tools`): unlock-all-acts (`UNLOCK_ALL_ACTS`) and the **Admin column of the Escape menu** (`UI._build_admin`, `ui.test_panel`; F8 just opens the menu): Go to level 20 (`Game.go_level_20`: talents, level-20 gear, +10,000 gold each press), Max out, the switches `test_immortal`, `test_onehit`, `test_stamina`, `test_allskills`, `test_fast` (super speed, `TEST_FAST` times as fast) in `game.gd`, and a level setter (`Hero.set_level`). On when running from the Godot editor or a local debug run, for an account with the **admin role** (above; granted 2026-11-02 to jj's and Blaine's accounts, found by their characters in Nakama), or when this PC holds a valid **admin key** (`AdminKey`, `scripts/admin_key.gd`): `user://admin.key`, signed with the owner's private key; the game checks it against the public key built into the code, so nobody can forge one. Off for everyone else in production builds. Make a key: `tools/admin_key.gd` (needs the private key, which is never in the repo and isn't on the Game Factory Mac). `UNLOCK_ALL_ACTS = false` turns the tools off everywhere.
- **The Gilded Hall** (the camp's auction house, jj 2026-11-04; first look): the Meshy hall
  (`assets/models/camp/auction_hall.glb`) west of the waypoint (`ForestCamp.AUCTION_AT`, `_auction_hall`) with
  Auctioneer Corvin at its door (`assets/models/npc/auctioneer.glb`: Meshy, rigged and animated, `prep_npc.py`; role
  `"auction"` in `Game._vendor_talk`), whose window is `scripts/auction_ui.gd` `AuctionUI` (`UI.auction_panel`): elixir
  listings (Meshy-painted icons `assets/textures/items/elixir_<id>.png`, `AuctionUI.ELIXIRS`/`TIERS`) under Browse /
  Sell / My Bids. Sample listings only: bidding, escrow and elixir crafting are still to build.
  `tools/auction_shot.gd -- outdir` screenshots the hall and the window.
- **No freeze on a first cast** (`scripts/skill_warm.gd` `SkillWarm`, jj 2026-11-04): a skill's first use compiled its
  effect's shaders and loaded its models on that frame (Fire Arrow 198 ms, Thunderstep 183, Spirit Beast 544 on the
  range). `Game.load_zone` awaits `SkillWarm.run` under the loading screen the first time a class enters a zone in a
  session: an unseen co-op puppet replays everything the class's skills draw (`scripts/skill_warm_data.gd`
  `SkillWarmData.EVENTS`, recorded by `tools/skill_warm_capture.gd`), muted, for ~2 s, then it is all swept away
  (after: 86, 41, 9 ms). Re-run the capture after adding or changing a skill's effects. The settle plays in
  fast-forward (`SkillWarm.SPEED` 4x `Engine.time_scale`, never more than `MAX_STEP` 66 ms of game time a frame) with
  the hidden 3D view at `LOW_RES` (nightly 2026-11-05: 2.5-2.9 s -> 0.8-1.0 s of every first load). It warms the whole party
  (the hero's class and every co-op partner's, all at once: a partner's spells are drawn on this screen too), and the
  Plague Doctor's own effects (his `Plague.remote` events, `SkillWarmData.PLAGUE`, plus `SkillWarm.PLAGUE_TAIL`).
  `SkillWarm.keep` holds every material the warm-up drew with (Godot 4.3 frees a generated shader with its last
  material).
- **Frame-time rules** (Blaine's audit, 2026-11-05; measured in a 3-class fight on 18 monsters, worst frame 688 ms to
  56 ms): load anything a skill, effect or gear piece needs while the game runs through `ResCache` (`ResCache.inst(path)`
  / `get_res(path)`, `scripts/res_cache.gd`): the ResourceLoader only keeps what is referenced, so a bare `load()` in an
  effect parsed its glb again on every cast (each Archer arrow 14-17 ms). Never create a `Shader` per cast (cache it in a
  static var, as every fx script does). The boot loads the title's and the camp's glbs on worker threads before the intro
  ends (`Game._boot_preload`, `BOOT_PRELOAD`) and builds the camp under the loading screen. Tools:
  `tools/stress_fight.gd -- [hero] [partners|-] [secs] [foes] [--idle] [--q N] [--nowarm] [--fx-timing]` (frame stats,
  the worst frames with what was cast and where their time went, lights and particles alive), `tools/fx_bench.gd --
  [classes] [rounds]` (every recorded effect's cost after warming), `tools/hitch_probe.gd -- title|camp|skills <cls>`;
  `--fx-timing` makes `FxTiming` print every skill/effect call over 6 ms. All need a display. On the Mac mini a big
  fight is GPU-bound at ~24 ms on High (40 fps) and ~15 ms on Medium.
  The rest of the game's first times (the app audit, same day): `MonsterWarm` (`scripts/monster_warm.gd`) builds and
  draws once, under the loading screen, every monster kind that can still turn up in the zone (ambushes, summons,
  Grubb's grabbers, the arena's stages, the Vigil's waves; on a co-op client the zone's spawns too), plain and under
  the hit flash and champion rim (grabber 766 -> 27 ms, bandits 77 -> 21); monster bodies load through `ResCache`.
  `UI.warm_windows` opens the inventory, sheet, skills, talents, quests and waypoints for a frame once a session and
  draws the sheet's portrait every zone (the sheet's first open 574 -> 25 ms). A new monster that spawns mid-zone
  from a new place needs adding to `MonsterWarm.kinds`. `tools/app_hitch_audit.gd -- [--monsters-only]
  [--all-monsters]` measures each step's worst frame the first and second time (windows, loot, zone changes, spawns).
- **Zone loads** (nightly 2026-11-05): `ZonePreload` (`scripts/zone_preload.gd`) asks for the zone's .glb files on
  worker threads as the loading screen goes up (`Game.load_zone`); the lists are `ZonePreloadData.PATHS` by
  "run:zone", recorded from the built zones (`-- --kpi <scenario> out.json --preload-record`, then `python3
  tools/zone_preload_gen.py`). A stale list only costs speed; re-record after a zone gains or loses models.
- **Shadow casters**: a `discard` anywhere in a material (leaf cards, the see-through dither) runs its fragment shader
  in every shadow cascade; triangles are cheap. `Props.shadow_twins` (end of `World.build`, after `see_through`) gives
  every static mesh or multimesh whose materials are opaque but for the dither a shadows-only child with a depth-only
  material (`--no-prop-twins` for comparisons); cut-out foliage casts from baked-mask twins (`Flora.shadow_twin`, the
  harvest trees too). `--kpi ... --castlist` marks cut-out casters `cut=true`.
- Don't commit `.godot/` or `build/` (ignored). Line endings are LF (`.gitattributes`).
- Intro video: Ogg Theora only; keep under ~90 MB (GitHub's limit is 100 MB per file). Since 2026-10-31 it is Blaine's
  new trailer at full quality (Blaine: no visible compression): 60 s, 1920x1088 (a multiple of 16, so Theora adds no padding rows), Theora 12 Mbit/s + Vorbis q6,
  85.4 MB; ffmpeg on the staging server: `-vf scale=1920:1088,setsar=1 -c:v libtheora -b:v 12000k -maxrate 16000k -bufsize 24000k -c:a libvorbis
  -q:a 6 -ar 48000`. Don't recompress it to save download size. Skipping it takes two deliberate presses (Esc, Space,
  Enter, a click or gamepad A/Start: the first says "Press again to skip"; `Game._is_skip_press`, other keys such as
  volume do nothing); `tools/intro_skip_test.gd`.
  The originals and the previous intro are kept on Blaine's Mac in ~/Documents/Game Factory/Trailers/.
- CI is `.github/workflows/deploy.yml` (container `barichello/godot-ci:4.4.1`). If it fails, the
  site keeps the last good build; read the failed step in the Actions tab.
- **Preview builds**: push a branch named `test-*` (`git push origin HEAD:test-something`) and
  `.github/workflows/preview.yml` builds the Windows, Linux and Mac versions as downloads on that Actions run
  (Artifacts, kept 7 days) without publishing anything. Use it to let a partner play a change before it goes to main.

## Waypoint activity catalogue (JJ, 2026-11-03)

The existing waypoint frame, banners, sigils and Acts route remain. PvE cards include the Last Flame,
coast, islands (derived from `Isles.ISLANDS`/builders), and each registered act's dungeon. Shipped builds
also offer Online Co-op using their configured server and the current character. Act and discovery
locks remain; islands retain their level requirement. Zone journeys use the existing party ready check.
Cross-act co-op activities ask the party to switch acts first.

Register additional zone activities in `Data.WAYPOINT_ACTIVITIES` with a stable `id`, `name`, `group`
(`pve` or `daily`), `route: zone`, `run`, `zone`, `spawn`, and optional `description`, `kind`, `level`.
Use `enabled: false` or remove an entry to withdraw it. `starts_at` (inclusive) / `ends_at` (exclusive)
are UTC Unix seconds; a daily is a scheduled entry targeting implemented content, not a new reward
or quest system. Empty categories hide. The panel refreshes availability and locks while open, and
Game rechecks the current entry when clicked. Unknown zones/builders are not offered; a new zone
needs its actual World builder and inclusion in `waypoint_activity_valid`, never new menu layout code.

Existing extraction raids remain in `Data.WAYPOINT_BATTLEGROUNDS`; IDs are now checked instead of
ignored. The crypt uses the build's raid allocation address. Additional extraction raids must provide
an explicit `address`; other PvP rulesets require their gameplay/connection handler before registration.
This is build-local content configuration, not a remote live-ops service. Unimplemented daily content
and development-only sandboxes are not advertised as playable destinations.

Validation: `tools/waypoint_activities_test.gd` uses the real renderer, checks catalogue changes,
locks and expired entries, renders the menus, and visits each registered PvE zone and its arrival.


## Background co-op party finder (JJ, 2026-11-03)

`party_queue.gd` owns a second ENet socket, leaving the solo world, travel and menus running.
The title's Online Co-op / Find Party starts the selected character in solo then queues; the town
waypoint also offers Find a Party. The compact ready check uses UI's existing ornate panel, gold
labels and iron buttons. Ready/Decline never pauses the world. Accepting reserves a slot, saves the
current character, then joins co-op when alive, unpaused and outside a zone load. A failed queue
handoff keeps solo play open. Leaving play, changing characters or joining another mode cancels search.

`party_queue_server.gd` runs inside the existing co-op process on UDP 24569 (`--queue-port` override),
with gameplay still on 24570. The queue pairs at least two players, or fills available slots in the
current public co-op party, up to four. This is one shared story party, not independent instances or
PvP teams. Only the current server act is offered, and only to characters that have unlocked it.
The server owns the 30-second ready check and 45-second, single-use handoff reservations. Ready
players keep their queue position if someone declines; nonresponders leave the queue on timeout.
Disconnected clients expire and direct joins cannot steal reserved slots. The reservation token is
an ephemeral bearer token; it does not add account authentication to the existing co-op protocol.

`BuildEnv.value("party_queue")` defaults to the configured raid host on port 24569 and supports an
`[env] party_queue="host:port"` override. A matching client/server release and UDP firewall opening
are required before public staging use. Preview exports retain the local environment by default.
Do not describe a local socket test as a deployed service or authenticated internet test.

Tests: `tools/party_queue_test.gd` uses real lightweight ENet sockets on 24779;
`tools/party_queue_game_test.gd` runs a real game host on 24770 with queue 24769 and clients `a` and `b`
(see its header). Characters live in isolated test save folders. `tools/title_layout_test.gd` checks
Story/Online/LAN controls at 1920x1080, 1280x720 and 1024x768 and hides the home cards on character
subpages. It renders screenshots when run with a real renderer.


## Home-to-game UI flow (JJ, 2026-11-04)

Home actions explicitly say Continue Story, Host LAN and Join LAN. LAN Join carries the selected
character ID rather than silently loading the most recent save. Home cards hide behind LAN discovery
as well as the other title subpages; discovery lists scroll within their frame. Battlegrounds scales
its entire page and fits its heading to the available description width, keeping the champion frame
separate. Character creation's information frame scales within the viewport; gameplay control hints
wrap within screen margins. Transient zone announcements and controls hints hide while gameplay
menus are open so they cannot cover the actions. Existing waypoint routes and progression rules are unchanged.

`tools/home_game_flow_test.gd` checks layouts at 1024x768, 1280x720 and 1920x1080, long LAN lists,
selected-character LAN entry, Continue Story, in-game waypoint access, return home and new-character
creation. It uses isolated test saves and a local unavailable LAN endpoint, never a public server.
Run with the real renderer to inspect its `/tmp/flow-*.png` captures as well as its log.
