# Sailing (archived)

The Mournwater Coast and its five islands: the ocean (waves on the GPU and the CPU, shore and depth maps), the coast
zone with its hamlet, pier and Osric Saltmarrow the shipwright, the boats (the Gull and the Ember Sloop, bought in his
window, sailed with WASD or the mouse, with a sailing camera, a sea chart for the minimap and partners' boats drawn
under their puppets in co-op), and the islands (the Verdant Isle with its dinosaurs, trolls and drunken dwarves, the
Ruins, the Lost Isle, the Bleak Isle in its fog, the Merchant's Isle), with the sea's light, gulls, leaping fish and
sounds. Archived whole on 2026-11-06 (Blaine: "we don't want to lose the boat stuff"). This folder is under
`archive/`, which has a `.gdignore`, so Godot neither imports nor exports it.

| File | What |
|---|---|
| `ocean.gd` | `Ocean`: the sea surface, its waves (`surface_y`), shore and depth maps, tint and light, quality |
| `coast.gd` | `Coast`: the coast zone's builder (`Coast.build`, zone `coast`): beaches, pier, hamlet, Osric, `MOOR`, `DOCK`, `shore_x` |
| `isles.gd`, `isle_verdant.gd`, `isle_ruins.gd`, `isle_lost.gd`, `isle_bleak.gd`, `isle_merchant.gd` | `Isles`: the five islands (`ISLANDS`, `ISLE_SCRIPTS`), each island's zone (`build_zone`, zones `isle_<id>`) and its builder |
| `height_grid.gd` | `HeightGrid`: the sampled height grid the sea zones' ground reads |
| `boat.gd`, `boat_ride.gd`, `boat_shop.gd` | `Boat` (the hull, built or imported), `BoatRide` (sailing, docks, puppets' boats, the sea bed's sounds), `BoatShop` (Osric's window) |
| `dwarf_game.gd` | `DwarfGame`: the Verdant Isle's drunken dwarves (rock-paper-scissors, then a fight) |
| `tools/` | its tests and shots (`sail_test`, `sail_mp_test`, `sloop_test`, `boat_shop_test`, `ocean_test`, `sea_sound_test`, `dwarf_test`, the `*_shot(s)` tools), `blender/prep_boat.py` (prepares a boat model), `audio/make_sea.py` (makes the sea's sounds) |
| `assets/models/` | `coast/`, `isles/` (with `verdant/`), `boats/sloop.glb`, `npc/osric.glb` and its two textures |
| `assets/audio/` | the sea's sounds (`surf`, `sea`, `splash`, `gull`, `hull_creak`, `hull_slap`, `mallet`) and their credits |
| `hooks/` | the code cut out of live files, to paste back: `game.gd` (every Game method and field below), `data.gd` (`Data.BOATS` and the rest), `birds.gd` (Birds with its gulls and fish), `terrain_shader.txt` (the terrain shader's sand, seabed, sea cliffs and caustics) |

Kept live (not sailing's alone): the dinosaurs, trolls and dwarves as monsters (`Data.ENEMIES` `raptor`, `trex`,
`trike`, `trike_baby`, `dwarf`..., `theropod.gd`, `trike.gd`, their models and sounds), World's decks (the Verdant
Reach's bridges use them), `World.terrain_patch`'s options, Inter's patrols (the camp's traders stroll), and the
World-Tree Island's far-off scenery (`isle_coast.glb`, `isle_moor.glb` in `game/maps/camp/props/island/`).

## To bring it back

Move the scripts back to `scripts/` (or under `game/maps/coast/`), the models and sounds back to their old paths
(`assets/models/coast/`, `isles/`, `boats/`, `npc/osric*`, `assets/audio/sfx/`; `Data.BOATS`'s sloop points at
`res://assets/models/boats/sloop.glb`), rebuild the class cache (`godot --headless --path . --import`), then put back
the hooks. The commit that archived it removed every one of them (`git log -- archive/sailing`, then `git show` that
commit for the exact lines):

- `scripts/world.gd`:
  - `build`: `"coast": Coast.build(self)` and, for any other kind starting `isle_`, `Isles.build_zone(self, Isles.id_of(kind))`;
  - the sea zones' ground: `height_fn` (read first in `ground_h`), `sea`, `WADE`, `steep` and `_too_steep` (water deeper
    than `WADE` and cliffs are walls in `_wall_at` and the grid's `blocked` cells unless a deck is over them), and
    `grass_ground`'s and `_scatter_ferns`' sand and sea (no grass below 1 m).
- `scripts/game.gd` (all in `hooks/game.gd`):
  - fields `boat`, `sail_blend`, `sail_cam_yaw`, `water_pt` (set in `_update_hover` from the mouse ray at y = 0);
  - `zone_music`: in a sea zone the `wild` song over the `surf` bed; `_sea_sounds` (called every frame after
    `_fit_shadows` while playing) fades the surf with the distance from the shore;
  - `_zone_env`: `if world.sea: _sea_env()` (the golden evening, then `_isle_mood` and `_ocean_light`);
    `_rim_kind`: `"day"` when `world.sea`; the grass wind `"sea"` (`grass_field.gd`'s `WIND` had a `sea` entry);
  - `_add_ocean(zone)` in `load_zone` (now `_reset_sky`, its first half): `cam.far` 900 and the `Ocean` node in a sea zone;
    `apply_quality`: `Ocean.set_quality`;
  - `zone_title`: `"coast"` (the act's `coast` name) and `isle_*` (the island's name); `load_zone`'s seed list had
    `"coast"` and `zone.hash() % 997` for an island;
  - `load_zone`: `birds.sea = world.sea`, `_add_boat(zone, spawn)` after the zone's life; `_capture_map`: on the coast
    `_sea_chart()` and `ui.minimap.chart`;
  - `_fit_shadows`: the sailing camera's long default split (`sail_blend > 0`);
  - the camera: `_sail_camera(real_dt, sh)` each frame (it also set `cam.basis` when not sailing; that line stays);
  - input: left mouse steers while `sailing()`, no right mouse, `E` lands (`try_land`), the skill keys do nothing,
    `dodge_roll` returns, `_process` calls `_sail_input`, no blocking, no binds, no WASD, no left-mouse repeat; zone
    exits wait while `hero.aboard`;
  - `_vendor_talk`: role `shipwright` -> `_shipwright_talk`; `_interact` kinds `boat` (`_boat_clicked`) and `dwarves`
    (`DwarfGame.talk`);
  - `waypoint_activities`: one entry per island in `Isles.ISLANDS` (with `ISLE_SCRIPTS`); `waypoint_activity_valid`:
    zones `coast` and `isle_*`;
  - the boat section: `sailing`, `_add_boat`, `_party_rank`, `isle_mooring`, `_boat_clicked`, `_sail_input`, `try_land`,
    `_ashore_prompt`, `land_boat`, `_sail_camera`, `_shipwright_talk`, `buy_boat`; and `_sea_env`, `_isle_mood`,
    `_ocean_light`, `_add_ocean`, `_sea_chart`, `_sea_sounds`.
- `scripts/hero.gd`: `boats`, `aboard`, `sailed`, `dwarves`, `owns_boat`, `best_boat`; the puppet's `net_boat_st`,
  `net_boat_id`, `net_boat` (read from state numbers 15-20 in `apply_net_state`, freed in `net_zone_reset`,
  `BoatRide.puppet_update` in `_puppet_process`); the pose at the tiller (`if aboard:` in `_process`); the save's
  `boats`, `sailed` and `dwarves` (a character saved since the cut has lost them).
- `scripts/net.gd`: `_boat_packet` appended to `_hero_packet` (aboard, x, z, yaw, speed, the boat's index in `Data.BOATS`).
- `scripts/ui.gd`: `boat_shop` / `boat_panel` (`BoatShop.build`, `tick` in `_process`, in `_walked_off`, `close_all`,
  `any_panel_open`), the sail prompt (`_build_sail_prompt`, `set_sail_prompt`, `accept_event_safe`), and the minimap's
  `chart` (a wider view, 240 m while sailing).
- `scripts/data.gd` (in `hooks/data.gd`): `BOATS`; `ACTS[0]`'s `coast` name; `VENDORS[0]`'s `shipwright`;
  `WAYPOINT_ACTIVITIES`' `coast` entry; `zone_level`'s coast and islands (base + 3).
- `scripts/birds.gd` (whole in `hooks/birds.gd`): gulls, gull cries and leaping fish with splashes at sea.
- `scripts/mats.gd` (in `hooks/terrain_shader.txt`): the terrain shader's `sea`, `col_sand`, sand, wet sand, seabed,
  caustics and sea cliffs, and the `ocean_t` global.
- `scripts/zone_preload_data.gd`: the `0:coast` and `0:isle_*` lists (or record them again with `ZonePreload.record`).
- `scripts/vendor_ui.gd`: the `shipwright` title; `scripts/inter.gd`'s patrol comment named Osric.
- `game/maps/camp/forest_camp.gd`: the west gate's exit to the coast (only when the camp isn't the island) and the
  `from_coast` spawn.
- `scripts/sfx_bank.gd`, `assets/audio/CREDITS.md(.json)`, `tools/audio/spec.py` and `build_sfx.py` (`STEREO`, `AMB`):
  the seven sea sounds.
- Tools: `tools/visual_audit/` (`scene_census` and `frame_stats` zone `coast` and the `Isles` / `Boat` caches,
  `layout_dump`, `see_through_check`, `checklist.py`'s rows for the isles' models, the sloop, Osric and the ocean).
- Tests: `game/maps/camp/tests/waypoint_activities_test.gd` counted the islands and checked the Verdant Isle's level gate;
  `camp_life_test.gd` checked the coast's gate was barred.
