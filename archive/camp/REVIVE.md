# The starting camp and Enter World (archived)

Enter World: the title's cards and character sidebar, the character list and the New Character screen's 3D
carousel; the starting camp in the old forest (zone `town`: the palisade ring, the traders' courts, Halvar's forge
and furnace, the guards, the ravens, the World-Tree Island in space, the grand waypoint); and the single-player
economy and activities that only the camp reached: the traders' shops, enchanting and gambling, the Gilded Hall's
auction, the bonfire, tempering at the furnace, woodcutting, quests, the waypoint window, town portals, day and
night, the shared stash, LAN co-op and Steam's friends-join-your-world. Retired from play on 2026-11-06 (the game
opens on the multiplayer page, dc7c93e) and archived whole the same night (Blaine: "we are dropping the enter
world... archive all the world stuff"). This folder is under `archive/`, which has a `.gdignore`, so Godot neither
imports nor exports it.

| Here | What |
|---|---|
| `forest_camp.gd`, `vendor_court.gd`, `smith_forge.gd`, `camp_guard.gd`, `camp_social.gd`, `camp_ravens.gd`, `raven.gd`, `camp_island.gd`, `waypoint_grand.gd`, `README.md` | the camp as it was in `game/maps/camp/` (its README says what each is) |
| `props/` | the camp's, the island's and the waypoint's models (`camp/`, `island/`, `waypoint/`) |
| `tests/`, `tools/` | the camp's tests and shots, and every project tool that only tested what is here (`title_test`, `char_test`, `home_game_flow_test`, `bonfire_test`, `temper_test`, `coals_test`, `daynight_test`, `npc_reach_test`, the `*_shot(s)` and clips, `steam_host_probe`, `space_textures.py`, `blender/` (the waypoint's, the guards', the island's, the raven's and the keepers' Blender scripts, the stash chest's assembly)) |
| `scripts/` | the screens and systems: `title_home.gd` (TitleHome), `class_stage.gd` and `class_cathedral.gd` (the New Character carousel, whole; the live `scripts/class_stage.gd` keeps only its constants), `vendor_ui.gd`, `auction_ui.gd`, `furnace.gd`, `furnace_ui.gd`, `harvest.gd`, `wood.gd`, `quests.gd`, `waypoint_panel.gd`, `day_night.gd`, `day_clock.gd`, `birds.gd`, `brazier_coals.gd`, `steam_link.gd`, `shared_stash.gd` (SharedStash), `inter_keepers.gd` (Inter as it was, with the keepers' animation, patrols and CampSocial's talk) |
| `assets/models/` | the keepers (`npc/`: grisold, hedda, maeve, roth, tarrow, the auctioneer) and the guards (`guards/`) |
| `assets/textures/` | the island's space sky (`space/`), the waypoint's rune rings, the waypoint window's banners (`wp_act1`, `wp_town`, `wp_sigil`, `wp_bg_crypt`), the auction's elixirs |
| `assets/audio/` | the bonfire (`bonfire_open`, `burn_item`), Halvar's `quench`, the ravens (`raven_caw`, `raven_wings`), the camp's night bed (`night_forest`) and its song (`music_town`), with their credits |

Kept live: the character saves the Arena's survivors are (`Game.list_characters`, `save_game`, `load_game`,
`read_save`/`write_save`, `cloud_saves.gd`, `Survivors`), `Game.start_game` (the tools' way into a world: it now
stands the hero in the Arena's hall), `Game.start_join` (the Arena's join with a survivor) and `start_host` (the
two-player tests' host), the party's ready check and the rest of the co-op code (its own cut), the dialog window,
the title's 3D stage (`TitleStage`: the multiplayer page's backdrop, where the lobby's class preview stands),
`ClassStage`'s class list, colours and signature moves, `Data.WAYPOINT_BATTLEGROUNDS`'s loading-screen painting,
the logs and the woodsman's axe in `Data.BASES` (saved bags hold them), `Game.chest_lid` (the Battlegrounds' chests
open with it), `birds_flutter` (the wyverns' wing beats are made from it), the orbit camera (no zone raises
`zoom_max` now), `WeaponCarry`'s "town" holster rule (no zone is called `town` now).

## To bring it back

Move the files back (the camp to `game/maps/camp/`, the scripts to where the screens and systems live then, the
assets to their `assets/` paths) and put back the hooks. The commit that archived it removed every one of them
(`git log -- archive/camp`, then `git show` that commit for the exact lines):

- `scripts/world.gd`: `build`'s `"town": ForestCamp.build(self)`; the island (`island_c`, `island_r`, `off_island`,
  `island_edge`, `island_clip`; `grass_ground` and the ferns keep off it); `grass_biome`'s trodden ground in the camp;
  `add_waypoint` (the stone or the grand waypoint, its colliders and arrival spots); `kind`'s default `"town"`.
- `scripts/game.gd`:
  - fields: `day_night` (with `lamp_mul`, `fire_mul` on the flicker lights), `steam`, `space_sky`, `quests`, `stash`,
    `waypoints_known`, `played_s`, `harvest_saved`, `tp_link`, `shops`; `cur_zone`'s and `shot_zone`'s `"town"`;
  - `_ready`: `Data.check_waypoints()`, `Quests.new`, `SteamLink`, the `SharedStash` and its cloud push,
    `_bury_lost_raiders()`, `_stash_start()`, and the tools' harness loading the camp (`_harness_camp`, now
    `_harness_world` loading the hall);
  - the environment: the `DayNight` node, the camp's night bed in `zone_music`, the camp's dusk light and its grade
    look (`forest_camp`), the island's space sky and `zoom_max` 2.2, `day_night.enable`;
  - `zone_title`'s `"town"`; the felled trees in the save (`_harvest_key`, `_store_harvest`, `_restore_harvest`);
    `load_zone`: the camp's seed, waypoint arrival spots, `_stock_shops`, the portal back, the birds, the ravens and
    CampSocial; `_capture_map`'s and `_grass_zone`'s camp cases;
  - `start_game`'s camp start and the elder's welcome; `start_join`'s LAN text, `start_join_steam`;
  - `on_net_failed`: Steam's world closing, a failed co-op join back to the join screen, a co-op end back to the camp;
  - `_cloud_start`'s burial, stash and title refresh; the stash (`stash_allowed`, `stash_deposit`, `stash_withdraw`,
    `_stash_fix_hero`, `_stash_start`); `_bury_lost_raiders`;
  - the save's `waypoints`, `quests`, `harvest` keys (and Hero's `stash`, `axe_given`);
  - `waypoint_battleground`; `exit_to_title`'s Steam close, portal link and the camp under the harness;
  - `_stock_shops`, `burned`, `claim_material`'s `quests.on_pick`, `_vendor_talk`; `_interact`'s kinds `tree`,
    `furnace`, `vendor`, `stash`, `bonfire`, `waypoint`, `portal`, `flower`; `use_inter_remote`'s flower;
  - the waypoint network (`travel_waypoint`, `waypoint_activities`, `waypoint_activity*`, `act_unlocked`,
    `waypoint_known`, `waypoint_go`, `_at_waypoint`); town portals (`_make_portal`, `cast_town_portal`,
    `open_town_portal_at`, `travel`'s `clear_tp`); `_pick_flower`; `on_enemy_killed`'s `quests.on_kill`;
  - `respawn` in the camp; `toggle_pause`'s Invite Friends; the hover's tree target; `close_sandbox` back to the camp;
    keys T (portal) and J (quests); the island's camera drift; `--enchtest`, `--guard-fight`.
- `scripts/hero.gd`: `stash`; the woodsman's axe in `new_character` and `from_save`; woodcutting (`start_chop`,
  `_chop_swing`, `_chop_ok`, `_chop_impact`, `_chop_next`, `stop_chop`, `_show_chop_axe`, `chop_axe`, and their calls
  in `cmd_move`, `cmd_target`, the keys' walk, `_use_skill`, `take_hit`, the pose, the attack's end and `_impact_body`).
  `game/systems/skills/dodge.gd` called `stop_chop`.
- `scripts/net.gd` (server and clients ship together): LAN discovery (`DISCO_PORT`, the broadcast in `host` and
  `_process`, `start_listening`, `stop_listening`, `found`, `local_ips`), Steam's `host_with` / `join_with`; the portal
  link in `cl_welcome` and `cl_goto` (`tp`) and `sv_travel`'s `clear_tp`; the snapshot's flowers, portals and trees;
  `cl_enemy_die`'s quests; woodcutting (`request_chop`/`sv_chop`, `send_tree`/`cl_tree`, `cl_trees`); town portals
  (`request_portal`/`sv_portal`, `portal_created`/`cl_portal`).
- `scripts/ui.gd`: the nameplates (`VendorUI.Plates`), the shop (`_build_shop`, `open_shop`, `_refresh_shop`, `_buy`,
  selling in `_inv_click`), the auction (`AuctionUI.build`), the stash (`_build_stash` and its tabs), the bonfire
  (`_build_burn`, `open_burn`, `burn_request`, `reforge_request`, `_burn`, the fire shaders, dropping on the fire),
  the furnace (`FurnaceUI`), enchanting (`_build_enchant`, `open_enchant`, `_enchant`), the waypoint window
  (`_build_waypoints`, `open_waypoints`), quests (`_build_quests`, `_fill_quests`, `_fill_tracker`, the tracker on the
  HUD), the day clock, the title's head, cards, row and sidebar (`_build_title`, `_title_card`, `_title_hover`,
  `_title_choose`, `TitleHome`), the join window (`_build_join`, `open_join`, `_refresh_join`, `_sync_menu_shade`),
  the class picker (`_build_class_picker`, `_show_class`, `_open_class_stage`, `_class_key`, `ClassArrow`,
  `open_class_picker`), the character list (`_build_characters`, `open_characters`, `_ago`), `show_title`'s cards and
  sidebar, `_walked_off`, the pause menu's Invite Friends, the Admin column's time of day, the corner map's waypoint,
  portal, vendor and stash marks, the controls line's J and T, and those windows in `toggle`, `close_all`,
  `any_panel_open`, `title_idle`, `refresh`, `_process` and `warm_windows`.
- `scripts/inter.gd`: the keepers (`archive/camp/scripts/inter_keepers.gd`: `model`, `anim`, `clips`, patrols,
  `walk_to`, `social`, the smith's strikes, the old procedural keepers' `rig`, the flowers' and waypoints' animation).
- `scripts/title_stage.gd`: `cards` and `_place_cards`, and `_frame`'s default `TitleHome.mid()`.
- `scripts/class_stage.gd`: the carousel (whole in `scripts/class_stage.gd` here), `EMBLEMS`, `PICK_SOUND`.
- the lobby (`mp_lobby_view.gd`, `lobby_client.gd`): the LAN row (`lan_row`), friends' worlds through Steam,
  the title's character back on the stage, the quest tracker's visibility.
- `scripts/cloud_saves.gd`: the stash's sync (`STASH`, `_sync_stash`, `push_stash`); its collection is left in each
  account. `scripts/lobby_stakes.gd` stamped items with `SharedStash.stamp`.
- `game/systems/data/data.gd`: `ACTS`' `town` name, `WAYPOINT_GROUPS`, `WAYPOINT_ACTIVITIES`, `WAYPOINT_ACTS`,
  `WAYPOINT_ZONES`, `waypoint_*`, `check_waypoints`, the Battlegrounds card's `name`/`kind`/`art`/`lines`, `VENDORS`,
  `CHOP_POWER`, `DEFAULT_CHOP`, `CHOP_PROFILES`, `chop_profile`.
- `game/systems/bodies/models.gd`: a resource's model (`Wood.item_model`).
- `scripts/kpi.gd`: the `camp` scenario; the zones' preload lists: `"0:town"`.
- Sound: `game/systems/audio/sfx_bank.gd`, `sfx.gd`'s `LOOPS` (`night_forest`, `music_town`), `tools/audio/spec.py`,
  `build_sfx.py`'s `STEREO`/`AMB`, `assets/audio/CREDITS.md(.json)`.
- Tests: `tools/nightly/gate.sh` ran `title_test`, `char_test`, `camp_life_test`, `vendor_test`, `guard_test`; the
  visual audit's checklist rows for the keepers and the camp's models.
