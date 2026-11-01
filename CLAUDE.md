# Ashen Crown: notes for Claude (and humans)

A Diablo II-style isometric ARPG in **Godot 4.3** (GDScript, Forward+ with an OpenGL fallback).
Everything is procedural (models, textures, sound, music) except a few asset files: the intro video
`assets/intro.ogv`, the Act I boss King Grubb `assets/models/grubb_mutant.glb` and the gnome Warlock
`assets/models/gnome_warlock.glb`, and the knight's two bodies `knight_meshy.glb` / `knight_armored.glb` (all generated
with Meshy and rigged in Blender; see "Blender assets"). Two developers (one Windows, one Linux) push to `main`; GitHub
Actions exports Web + Windows + Linux + Mac and publishes them to GitHub Pages.

- Repo: https://github.com/jjcw1337-rgb/ashen-crown
- Live test build + downloads: https://jjcw1337-rgb.github.io/ashen-crown/
- Human setup and workflow: `CONTRIBUTING.md`. Player docs: `README.md`.

## Getting the tools (Linux)

Godot 4.3 **standard** (not .NET) must be on PATH as `godot`:
```
wget https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip Godot_v4.3-stable_linux.x86_64.zip && sudo mv Godot_v4.3-stable_linux.x86_64 /usr/local/bin/godot
```
**Blender 4.5 LTS** (for models and rigs, see "Blender assets"): `bash tools/blender/setup_blender.sh` installs it
to `/opt` and links `blender` (checksum-verified). Claude's cloud workspace resets, so run it again in a new session;
it needs network access to `download.blender.org`. Run scripts headless: `blender -b --python script.py -- args`
(renders with Eevee work under `xvfb-run -a`). Export `.glb` into `assets/models/`, never `.blend`.

**Meshy** (AI image/text to 3D, paid plan): `python3 tools/meshy/meshy.py text|image|get|check ...` saves a `.glb` plus a
thumbnail. Key from `$MESHY_API_KEY` or `~/.config/meshy/key` (never in the repo); needs `api.meshy.ai` and
`assets.meshy.ai` reachable. Each generation costs credits; results expire on Meshy after 3 days. Clean up, rig and
export with Blender, the way King Grubb was made.

Exporting locally also needs the 4.3 export templates (Editor → Manage Export Templates), but
you normally don't export locally: pushing to `main` does it in CI.

## Commands

```
godot --headless --editor --quit                  # import / rebuild the class cache (run after adding a class_name)
godot --path .                                    # play
godot --headless --path . -s tools/playtest.gd    # main gameplay smoke test
```
Headless tests in `tools/` (each prints `[X] ...` lines; look for SCRIPT ERROR / Parse Error):
`playtest`, `unlock_test`, `test_panel_test`, `wraith_test`, `demon_test`, `warlock_test`, `a2_test`, `a3_test`, `run_switch_test`, `drag_test`,
`det_test`, `woodcut_test` (`--fixed-fps 60`), `temper_test`, `woodcut_mp_test` (host + join), `grass_test`, `collision_test`, `aim_test`, `plague_test` (`--fixed-fps 60`), `hoard_test`, `coop_fx_test` (every skill's effects reach a puppet, in one process), `potion_test`, `fort_test`, `sound_test`, `char_test`, `flower_test`, `feral_test`, `talent_test`, `title_test`, `a2_arena_test`, `sloth_test` (the Hollow Sloths roam, notice, hunt, use their three skills, flee, give up, drop a unique), `vendor_test` (the camp's traders, the trade window, walking off closes it), `ui_click_test` (no click on a window, menu, globe or the corner map walks the hero; a control that rebuilds itself on click must `accept_event()` first, or the click leaks through), `bg_test` (the Battlegrounds: a server and a client, `-- --server --port 24611 --raid-fast server` and `-- client 24611`), `bg_pvp_test` (a server and two players, `a` and `b`), `controls_test` (WASD, the left click, the dodge roll, every class), and the co-op pairs `mp_test`, `mp_boss_test` and `plague_mp_test` (run one copy
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
| `wraith.gd`, `wraith_skills.gd`, `wraith_fx.gd` | Wraith class: the Meshy body on the mocap system with the spectral shader; its six skills (casts, blows, the tether, phantoms, the night); their effects |
| `demon.gd`, `demon_mocap_rig.gd`, `demon_skills.gd`, `demon_fx.gd`, `demon_fists_fx.gd`, `infernal_fx.gd` | Demon class: the Meshy magma brute on the mocap system with the magma shader and his own wing/tail/cloth rig (falls back to the knight body in obsidian plate + horns/wings/tail/spikes with the solid ember-edge shader); his six skills (the fists, the charge, the slam, the boulder, the grip, the wrath); their effects (lava on the ground, fissures, boulders, meteors) |
| `warlock.gd`, `warlock_fx.gd` | Warlock class: the gnome (`Warlock.GNOME`: imported model on `Goblin.imported_rig`, A-pose arms aimed down, swaying hat and beard, fel flame, floating grimoire; falls back to the robed knight body without the glb); skill effects incl. the Drain Life beam (`WarlockFx.Beam`, an ImmediateMesh ribbon redrawn each frame) |
| `plague.gd` | Plague Doctor class: body (mocap, whole-body skill clips), Toxic Flask, Volatile Mixture, Pestilent Trap, The Last Epidemic, poison and infection, co-op replay |
| `dragon.gd`, `dragon_skills.gd` | The three dragon classes (`wyrm` Obsidian Wyrm, `serpent` Frost Serpent, `wyvern` Storm Wyvern): Meshy bodies posed in code every frame (`Dragon.pose`, handed over by `Anim.pose`); no skills yet (`DragonSkills` is the empty, ready skills script and plays their attack sounds) |
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
| `kpi.gd` | The official performance KPIs: scripted scenarios measured frame by frame (`--kpi`), see docs/nightly/KPIS.md |
| `skill_fx.gd`, `knight_fx.gd`, `archer_fx.gd` | Co-op skill effects: `SkillFx` plays every class's skill events on the caster and on his puppet for partners (see "Co-op skill effects"); the knight's and archer's effect handlers (the Wraith's, Demon's and Warlock's are in their `*_fx.gd`) |
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
- **Co-op**: every peer must run the same build; RPC ids depend on each script's RPC set.
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
  three chests and a champion with bowmen. The walls come from `World.crypt_shell` (shared with the crypt). **Rounds**
  of `RAID_SECS` (15 min): two of the four portals open at `PORTALS_AT` (5 min), joining closes at `JOIN_CLOSE`, the
  crypt collapses at the end (everyone inside dies) and the dungeon resets (`new_round`). The state reaches players
  through `Net.cl_bg_raid` (the HUD clock, `Battlegrounds.hud`). **Combat is slower and heavier** while
  `Game.bg_mode` (Hero: `ATTACK_PACE`, `HIT_MULT`, `CD_MULT`, `MOVE_MULT`, no life regeneration). **PvP**: every other
  player is an invisible stand-in `Enemy` with `pvp_pid` on each client (`sync_proxies`), so any attack or skill
  that hits monsters hits players; `Enemy.take_damage` sends `Net.sv_pvp_hit`, the server scales it (`PVP_MULT`) and
  deals it (`Net.hit_player`); kills are announced. **Real characters**: the Battlegrounds screen picks one of the
  player's characters (`Game.start_battlegrounds(addr, id)`); its save says `in_raid` until it extracts; what it
  extracts with stays in its inventory. **Death** costs every item worn and carried, the belt and the gold
  (`Game.bg_strip` / `strip_save`: levels, stats, talents and the camp's stash are kept; a plain class weapon is
  given back), dropped where it fell (`Net.sv_bg_died`); a character whose game closed mid-raid is stripped the next
  time the game starts (`Game._bury_lost_raiders`). Joining uses a one-time Nakama ticket on staging (see "Staging
  and accounts"). Tests: `tools/bg_test.gd` (server `--raid-fast`: 150 s rounds) and `tools/bg_pvp_test.gd`.
  Dev cheat (non-production builds or dev tools): type `maxout` while playing (`Game.max_out`: level 99, stats,
  every talent, a million gold, potions, a bag of the best gear).
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
- **Browser build (WebGL)** is a test build only and is fragile:
  - it is exported with **Godot 4.5.1** in CI (the desktop builds use 4.3): Godot 4.3's WebGL renderer
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
  Fire Arrow (`pierce`: through a line, sets them burning, `Enemy.ignite`), Frost Volley (`volley`: a rain on the cursor,
  hits every 0.2 s and chills, `Enemy.chill`, slower on their feet; a partner's chill reaches the host through
  `Net.send_enemy_chill`), Storm Snare (`snare`: holds the first on it, lightning arcs into the nearest others,
  `Fx.bolt`), Spirit Beast (`beast`: commands his wolf, below). Arrows are Meshy models (`assets/models/arrows/`
  war / fire / frost, prepared by `tools/blender/prep_arrow.py`: head toward Godot -Z), `Archer._arrow_mesh(kind)`.
  Talents: Flame, Frost, Storm (`Talents.TREES["archer"]`; specials arrow_split, burn_dmg, wolf_burn, chill_pct, wolf_howl,
  frost_shatter, arc_count, snare_dur, snare_max, volley_size, beast_two). His **wolf** (`spirit_beast.gd`, `SpiritBeast`): JJ's dire forest wolf (Meshy, 25% larger
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
  its draw squeezed in before Anim's release frame, the body turned side-on, `yaw`); Every shot draws a fresh arrow from the quiver: the standing shot plays Meshy's "Draw and Shoot from Back" (`shoot_back`) squeezed along `SHOT.keys` (reach, grab, arrow out, nock, raise, full draw, release on Anim's impact frame, follow-through; `KnightMocapRig.shot_time`), turned side-on (`yaw`; the aiming stand has `stand_yaw`). Shooting on the move: he keeps walking at `Archer.SHOOT_MOVE` (36%) of his pace (`Hero._process`; a shot at a clicked foe still plants him) in the aimed walk (`walk_clip`, timed to his speed, `w_aimwalk`), and only his right arm takes the reach to the quiver from `reach_clip` (a filtered Blend2 over `reach_bones`, weighted by `reach`). `Archer.pose_bow` shows the arrow in his hand from `GRAB` to `NOCK` (`_hand_arrow`: point first into the quiver `QUIVER`, then swung onto the bow) and, while he shoots, solves the bow onto his hands: grip in his left fist, the draw line on his right fingers (`FINGERS`), limbs upright with a `CANT`, so the string always meets the hand. Colours: `Archer.COLORS` ("crimson"; also teal, verdant, royal, "" = Meshy's own) swaps the albedo for `assets/textures/ranger/ranger_<name>.jpg` (`Archer.dye`), made by `tools/archer_colors.py` (texture dumped from the glb, regions from `tools/blender/archer/region_uv.py`: the face, hands, fur and straps keep their colour). Storm Snare and Spirit Beast are
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
  Skills: Toxic Flask (Q, a lobbed flask, cloud 3 m / 4 s), Volatile Mixture (E, a fuse ring 0.6 s then a 4 m fire
  blast that burns; **Ignition**: a blast that reaches one of his clouds burns it out at once for its remaining poison),
  Pestilent Trap (R, up to 2, armed after 0.8 s, the first foe springs it: stun + cloud; **Outbreak**: sprung by an
  infected foe, its cloud infects), The Last Epidemic (F, a 9 m dome for 8 s: poison, slow, infection; collapses with a
  last blow). **Statuses live on the caster** (`Plague.poison`, `infected`, `immune`), ticking every 0.5 s through
  `Enemy.take_damage` on the elemental channel (green numbers, `dmg_tint`, no blood), so a partner's damage reaches the
  host the usual way and nothing new crosses the network for it. Guards: one poison per source per foe (refreshed, never
  stacked; sources toxic, trap, epidemic, infection); one infection per foe; a dead carrier passes it to the two nearest,
  at most `INF_JUMPS` (6) jumps per cast; 4 s immunity after it ends. Every number is a const at the top of plague.gd;
  talent keys (`cloud_size`, `poison_dmg`, `blast_size`, `ignite_dmg`, `trap_max`, `inf_jumps`, `dome_size` ...) are
  read where the skill is. **Co-op**: the first class whose effects partners see: `Plague._send` → `Net.hero_fx` (the
  host relays; `sv_hero_fx`/`cl_hero_fx`) → `Plague.remote` on the puppet, whose `Plague` is a `ghost()` (builds the same
  flasks, clouds, traps and dome, deals nothing). His leather is dyed (`Plague.COLORS`, default "oxblood2": an oxblood coat and cape with a black hat,
  gloves and boots; also "oxblood", "plague", "plague2", "ash2", "" = Meshy's black): `Plague.dye` swaps the albedo for
  `assets/textures/plague/coat_<scheme>.jpg`, made by `tools/plague_colors.py` from the albedo and metal maps that
  `tools/blender/plague/dump_textures.py` saves out of the glb and the regions `tools/blender/plague/region_uv.py` finds
  (head and hat above the collar, gloves by the hand bones, boots below the coat's hem): only the dark, grey, non-metal
  leather is tinted. His cane: `Data.BASES` `physician_cane`/`crow_cane` (kind `"cane"`,
  `"cls": "plague"`, `Plague.cane_model`: the Meshy crow-skull cane `assets/models/plague/cane.glb`, `prep_cane.py`).
  Props: `assets/models/plague/` flask, volatile, trap (Meshy text-to-3D, `act1/prep_prop.py`). Talents: Toxicology,
  Volatile Arts, Contagion (icons `p_*.png`, `plague_tree*.png`). Tests: `tools/plague_test.gd` (`--fixed-fps 60`),
  `tools/plague_mp_test.gd` (host + join); screenshots `tools/plague_shots.gd` (`--fixed-fps 10`).
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
- **The Demon's skills** (`scripts/demon_skills.gd` `DemonSkills`, effects `scripts/demon_fx.gd`, tuning in
  `Data.SKILLS`; six on Q E R F G V; a pure magma brute, the summons, Blood Pact, Hellfire Claw and Underworld
  Phase are gone): Molten Fists (Q: the two-fisted punch cracks the ground open in a wedge ahead, `FISTS_R`, hits
  and ignites), Infernal Charge (E: the head-down charge up to `CHARGE_RANGE`, moved by `_update_charge` through
  the clip, bowling foes aside with a knockback and a stun, laying lava every `TRAIL_STEP` that burns `TRAIL_DUR`
  s), Cataclysm Slam (R: a ring round the blow, then `FISSURES` fissures walked out ahead with `world.move` and
  erupting in waves, `FISSURE_DELAY`/`FISSURE_WAVE`, each foe once per fissure), Brimstone Hurl (F: a boulder
  thrown from the hand at the release frame, landing `HURL_FLIGHT` s later: the splash, a knockback, fire, a pool
  for `POOL_DUR`), Hellgrip (G, level 14: the foe ahead is seized a quarter into the clip, `grip_pick`, stunned
  and hoisted, smashed at the impact for his heaviest blow plus a shockwave; refused with "No enemy in reach"),
  Wrath of the Pit (V, level 18, the ultimate: two stages chained as attacks by `_update_wrath`, the roar (terror
  round him) and the stomp (a lava ring), then `WRATH_DUR` s of meteors, one every `WRATH_EVERY` on the foe struck
  least recently within `WRATH_R` (`_call_meteor`; the spot goes in the event, so partners see the same sky), with
  the +40% buff). Every blow adds `magma(h, k)` on top of the weapon, the same curve as the Wraith's spirit-light.
  Clips through `Demon.SHOTS` (fists = claw, icharge = the looping charge, cslam = slam, hurl = hurl, grip =
  grab_throw, wrath_roar = roar, wrath_stomp = stomp; `Anim.impact_at` has their frames, `Net.STYLES` the styles).
  State lives in `Hero.dm` (the charge, `lava` patches ticking every `HAZARD_TICK`, `fissures`, `boulders` and
  `meteors` in the air, the grip's victim, the wrath); `DemonSkills.clear` drops it all (class change, death, a
  zone change) and `DemonFx.clear` what is seen. Effects are fx events `DemonFx.play` draws and `DemonFx.update`
  keeps going on the puppet too (`Hero.fxs`: `icharge` embers, `boulders`/`meteors` flown on a parabola, `grip`
  lifting the victim's rig, `wrath` ramping the body shader's `wrath` = white-hot cracks and a light); the lava on
  the ground is `DemonFx.lava_decal` (a disc of `LAVA_SHADER`: cracked rock with magma breathing through, a wedge
  for the fists, cooling to black over its life) and `lava_strip` for the fissures, `boulder` the molten rock
  (meteors too), `crater` where one lands. Old saves' bindings of hellclaw/summon/phase/pact become
  fists/icharge/cslam/hurl (`DemonSkills.OLD_IDS`, `migrate_binds` in `Hero.from_save`); the talent ids (and their
  painted icons) were kept, their effects now name the new skills (`fists_wide`, `trail_dur`, `hurl_twin`,
  `wrath_dur`, `wrath_double`). `tools/demon_test.gd` exercises every skill, the migration and the talents;
  `tools/demon_skills_clip.gd -- outdir [skill|all] [close|game]` renders frames of each (xvfb, `--fixed-fps 30`);
  `tools/coop_fx_shot.gd` has `demon:grip` and `demon:wrath`. The Underworld grade in `game.gd`
  (`set_underworld`, `DemonFx.UNDERWORLD_SHADER`, `under_amt`) and the body shader's `phase_amt` stay, unused.
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
  **lossy WebP at quality 0.9, 3D detection off** (the default was lossless, 490 MB of the old 618 MB pack; q0.9 is
  ~41 dB against the source JPGs, which are lossy already). A checkout imported before 2026-11-01 keeps its old
  lossless `.import` files until they're deleted (`find assets/models -name '*.jpg.import' -o -name '*.png.import' |
  xargs rm`, then `godot --headless --import`). Give a new texture with a committed `.import` the same settings when it
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
  fort, i.e. whenever `oak_forest`; A2/A3 keep the old blade clumps): seven species built in code (`Grass.SPECIES`:
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
  casts shadows only on Ultra. `Grass.apply_quality` updates distances (`Game.apply_quality` skips the 3D grass's
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
  (measures the joints; hints `{"sh_z", "sh_x"}` when a hood or helmet spike fools the neck finder) and
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
    milestones, statues (the earlier Meshy knight `knight_statue.glb` carved in marble, `Roman.STATUE_GLB`), fountains, the triumphal arch, cypresses
    (MultiMesh), ruined walls. Repeating pieces go through `Props.multimesh` with their own mesh copy
    (`Roman._own`: Geo's meshes are cached and shared, never set a material on them).
  - **Monsters**: bandits (`bandit`, `bandit_archer`: the Meshy bandit on `MeshyMonster`, faction "bandit"),
    the arena lion (`lion.gd`: Meshy model, a 20-bone skeleton from `sources/lion.blend` skinned by surface
    distance like the Feral, posed every frame in code by `Lion.pose`, the Feral's pack AI with its lunge as the
    pounce and its swipe as the maul; `tools/lion_sheet.gd`), the gladiator and the champion (procedural humanoids
    until their Meshy models: the concepts are in `exports/act2/`, the key's monthly Meshy cap stopped them).
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
- **The Mournwater Coast and its islands** (Act I, west of the camp through its west gate; branch `test-ocean`, work in
  progress: the visual pass, sounds and co-op come next). `coast.gd` (`Coast`, zone `"coast"`): a headland with the open sea on
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
  sailing). `tools/sea_life_shot.gd -- outprefix [q]` screenshots the chart, gulls, a fish and the Bleak Isle. The five are 250 m across,
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
  how to sail, Buy). Boats are `Data.BOATS` (`gull`: 400 gold, speed 8); owning one is `Hero.boats` (saved), bought with
  `Game.buy_boat`. The boat's model is `Boat.model(id)` (`boat.gd`: lofted clinker hull with its own plank shader, deck,
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
  pier), `tools/sail_shots.gd -- outprefix [q] [isle]`. Tests: `tools/ocean_test.gd`; screenshots `tools/ocean_shots.gd -- outprefix [q] [only]`
  (Forward+ screenshots need a Vulkan driver: `apt-get install mesa-vulkan-drivers` gives lavapipe, slow but correct).
  Note: a first import of the project needs `godot --headless --editor --quit-after 2000` (plain `--quit` can abort the
  scan before the class cache is written).
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
- **Title screen** (`UI._build_title`, `scripts/title_stage.gd` `TitleStage`): the Gate of the Ashen Crown at dusk in
  its own World3D: a ruined cathedral gate with the dusk showing through its arch (`BACKDROP_SHADER`), broken arcades,
  the fallen stone king and a giant crown in the ash, fog banks, falling ash, embers, braziers and torches, heat
  lightning now and then. Models are Meshy (concept image, then image-to-3D, 144 credits) in `assets/models/title/`
  (`gate` 18 m, `arcade` 8 m, `colossus` 10 m, `crown` 1 m, prepared by `tools/blender/prep_prop.py`; the colossus cut
  at the ash line by `tools/blender/trim_below.py`), darkened to the game's palette in code (`SOOT`); without them
  procedural stand-ins are built. Two daises: Continue (left) shows the last character played as a co-op puppet in
  their saved gear (`Game.character_gear(id)`, read-only), idle, doing their class's `ClassStage.SIGNATURE` move when
  hovered; Create New Character (right) is an empty dais with a rune circle and a cold light. The choices are cards
  (`UI._title_card`) placed under their daises each frame (`TitleStage._place_cards`); dais or card, hover leans the
  camera and lights that side (`set_focus`), a click plays the camera's move in (`enter`) and then Continue calls
  `start_game(true, …, id)` with the id of the one shown, New opens the class picker. No saves: the Continue card is
  disabled and the camera leans to New. Characters, co-op and Quit sit in a row below. While the title is up the main
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
  (`RUNE_SHADER` glows their runes), a bonfire, tents and lantern-hung oaks inside, the old forest beyond, and a
  dusk/mist mood (`Game._zone_env`, `theme.forest_camp`). Everything is Meshy (concept image, then image-to-3D),
  prepared in Blender: props by `tools/blender/prep_prop.py` into `assets/models/camp/`, trees by `prep_tree.py`.
  The shopkeepers are Meshy characters rigged by Meshy and animated from its clip library (`meshy.py rig` /
  `animate` / `library`), cleaned by `tools/blender/prep_npc.py` into `assets/models/npc/`; `Inter._animate`
  plays their work clips, turns them to face the hero and has them talk when he comes near (clips listed in
  `ForestCamp.SHOPS`). Their library clips walk the hips about (Catching_Breath strode 4.6 m out of the forge),
  so `ForestCamp._pin_root` pins every clip's hips over the keeper's spot. The camp is "The Forsaken Wilds"
  (`Data.ACTS[0]["town"]`); its smith Halvar Emberhammer works inside his forge behind the anvil (a SHOPS entry's
  `"inside"`: his spot in the stall's frame; `"stay"` in its clips: he never turns from his work and greets once a
  visit; his `radius` reaches the stall's front, since the stall is solid). His hammer rings the anvil on each blow (`anvil`: five layered Kenney takes; `Inter._strikes` hears the
  hand bone stop falling; a SHOPS entry's `"strike"`), `tools/anvil_test.gd`. Screenshots: `tools/camp_shots.gd`.
- **Nameplates and the trade window** (`scripts/vendor_ui.gd`): `VendorUI.Plates` (in `ui.plates`, under every
  window) floats a gold-trimmed plate with the name and trade (`VendorUI.ROLE_TITLES`) over each vendor and Varro,
  click-through, fading with distance, lit when hovered. The trade window (`UI._build_shop`, `open_shop(mode,
  title, items, who, greet)`) is headed by the trader: a live portrait (`VendorUI.Portrait`, their model in its
  own little world, from the keeper's `npc_file` meta or the humanoid's `look`, greeting then idling), name, trade,
  greeting and your gold; tabs by kind (`UI.SHOP_KINDS`; `shop_view` maps cells to `shop_items`) and a price on
  each cell, red when you can't afford it. `UI.trade_with` is the NPC whose window is open: walking more than 3 m
  past their `radius` closes it (`UI._walked_off`, the stash too). `tools/vendor_test.gd` checks all of it with
  the smith; `tools/vendor_shots.gd -- outdir [role]` screenshots a trader.
- **Skill bar and bindings** (every class, including new ones): the bar has a big slot for each mouse button and six
  hotkeys (Q E R F G V); any skill can go on any of them (`Hero.binds`, saved per character; `Hero.default_binds`:
  left mouse `attack`, right mouse the class's first skill, the class's first four skills on Q-F). `attack` and `block` are
  `Data.COMMON_SKILLS` (`Data.skills_known(cls)` = class skills + common). Input goes through `Game._use_bind`
  (held buttons recast when ready; `Game.skill_held(id)` for Block and Drain Life's channel). Click a bar slot or
  open the skills window (K) to rebind, or drag: a skill from the skills window onto a slot, one slot onto another
  (they swap), or off the bar (cleared; left mouse never empties). Drag uses Godot's `set_drag_forwarding`
  (`UI._skill_drag`, `UI.drop_skill`, the clear in `UI._notification`); a click without a drag opens the slot's menu.
  Block: 80% less damage from the front (missiles stopped with a shield).
  Art: Meshy-painted frame and sockets in `assets/textures/ui/`. A new class needs nothing extra.
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
  a zone can hold several). Tests: `tools/waypoint_test.gd`
  (rules), `tools/waypoint_shot.gd -- out.png [run]` (screenshot).
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
- **Performance KPIs** (`scripts/kpi.gd` `Kpi`, `docs/nightly/KPIS.md`): the official numbers. Scripted, deterministic
  scenarios (camp, moor, fight, boss, arena, crypt, server; `Kpi.SCENARIOS`) run in any build with
  `-- --kpi <scenario> out.json [--quality N] [--secs N]` (the server: `-- --server --kpi server out.json`), measuring
  fps, 1% low, p99 frame time, hitches, load time, main thread, GPU, draw calls, triangles, memory; then quit.
  `tools/nightly/bench.sh` runs the suite (plus the download size), `tools/nightly/kpi_push.py` stores it in the KPI
  database on the staging server, Grafana draws it (https://<staging>/grafana/), `sh tools/kpi_query.sh latest` reads it.
- **Nightly lab** (`tools/nightly/`, `docs/nightly/README.md`): two launchd jobs on the Game Factory Mac, `perf` (01:00)
  and `mode` (04:30), each on a fresh `staging` with its own log (`docs/nightly/perf/LOG.md`, `docs/nightly/modes/LOG.md`:
  lessons, then one row per attempt), the KPI benchmark before and after (slower = not shipped), the gate, a push to
  `staging` and a Discord report. `bash tools/nightly/install.sh` installs or updates them.
- Developer tools (`Game.dev_tools`): unlock-all-acts (`UNLOCK_ALL_ACTS`) and the F8 testing panel (`test_immortal`, `test_onehit`, `test_stamina`, `test_allskills`, `test_fast` (super speed, `TEST_FAST` times as fast) in `game.gd`, and a level setter, `Hero.set_level`). On only when running from the Godot editor or when this PC holds a valid **admin key** (`AdminKey`, `scripts/admin_key.gd`): `user://admin.key`, signed with the owner's private key; the game checks it against the public key built into the code, so nobody can forge one. Off for everyone else, in every build (live and preview). Make a key: `tools/admin_key.gd` (needs the private key, which is never in the repo). `UNLOCK_ALL_ACTS = false` turns the tools off everywhere.
- Don't commit `.godot/` or `build/` (ignored). Line endings are LF (`.gitattributes`).
- Intro video: Ogg Theora only; keep under ~90 MB (GitHub's limit is 100 MB per file). Since 2026-10-31 it is Blaine's
  new trailer at full quality (Blaine: no visible compression): 60 s, 1920x1088 (a multiple of 16, so Theora adds no padding rows), Theora 12 Mbit/s + Vorbis q6,
  85.4 MB; ffmpeg on the staging server: `-vf scale=1920:1088,setsar=1 -c:v libtheora -b:v 12000k -maxrate 16000k -bufsize 24000k -c:a libvorbis
  -q:a 6 -ar 48000`. Don't recompress it to save download size. Skipping it takes two deliberate presses (Esc, Space,
  Enter, a click or gamepad A/Start: the first says "Press again to skip"; `Game._is_skip_press`, other keys such as
  volume do nothing); `tools/intro_skip_test.gd`.
  The originals and the previous intro are kept on Blaine's Mac in ~/Documents/Game Factory/Trailers/.
- CI is `.github/workflows/deploy.yml` (container `barichello/godot-ci:4.3`). If it fails, the
  site keeps the last good build; read the failed step in the Actions tab.
- **Preview builds**: push a branch named `test-*` (`git push origin HEAD:test-something`) and
  `.github/workflows/preview.yml` builds the Windows, Linux and Mac versions as downloads on that Actions run
  (Artifacts, kept 7 days) without publishing anything. Use it to let a partner play a change before it goes to main.
