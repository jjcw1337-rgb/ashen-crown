# Multiplayer overhaul: acceptance checklist

Blaine's spec (Discord, 2026-11-06, 17 points) requirement by requirement. Each line says what proves it: an
automated test (`tools/<name>.gd`, run headless; `gate` = in `tools/nightly/gate.sh`), a screenshot tool, or
**not proven yet**. Update this file with every step; nothing is ticked without its proof. Re-read the spec
(`docs/overhaul_plan.md` links it) before each staging push.

Legend: ✅ done and proven · 🟡 partly done (what's missing is said) · ⬜ not started

## 1. Single player untouched; Create Character hidden; Waves removed
- ✅ Enter World and single player unchanged: the run code is behind `Hero.run` (null in single player). `run_build_test` (single player: no run, talents and points as before), the whole gate (playtest, talents, every class test).
- ✅ Create Character hidden: `screen_test` (gate).
- ✅ Waves unavailable everywhere: `lobby_ui_test`, `waypoint_activities_test`, `nightly_vigil_test` (gate: the gate is sealed), lobby service `test_waves_retired`.
- ✅ Shared changes don't break single-player saves: a run is saved only as a survivor (`Game.save_game` returns for a run); `bg_test`/`bg_pvp_test`/`survivor_test` check the saved character is untouched.

## 2. Retire deliberately
- ✅ One switch file `scripts/mp_mode.gd`; one cleanup doc `docs/cleanup.md` (Waves, Create Character, raiding with your own character, the stash, talents/gold/rings/backpack in runs, the crypt map).
- ✅ Hidden features can't be launched by the new flow: the lobby service refuses Waves; `_start_run_raid` never loads a single-player character.

## 3. Full multiplayer UI redesign (Valorant-inspired modern fantasy)
- 🟡 The visual system exists (`MpStyle`: palette, Cinzel/Inter) and the run's windows use it: build, gear swap, camp upgrade, results, roster (`run_ui_shots`, `survivor_test`).
- ✅ Multiplayer entry, mode selection (tabs), lobby browser and lobby preparation redesigned (`MpLobbyView`): the mode's painted art (Meshy, `assets/textures/ui/mp_*.jpg`), large type, one gold primary action, the chosen class large on the title's lit stage. Proven at 1024x768, 1280x720 and 1920x1080: `lobby_ui_test` (every control on screen, tiles and Ready fit, nothing past the window), `mp_lobby_shots` (15 checks + screenshots).
- ⬜ Transitions between states and focus/keyboard navigation reviewed. **Not proven yet.**

## 4. Simple journey: Multiplayer → browse/create → mode → prepare → ready → play
- 🟡 Works end to end with the existing lobby service (`bg_test`); mode (tabs), host, players, capacity, state and joinability shown (`mp_lobby_shots`).
- ✅ Filtering (All / Joinable now), loading, empty, full (Join disabled, "Full") and service-failure (Retry, selections kept) states; distinct mode artwork (`mp_lobby_shots` screenshots).
- ⬜ A disconnected-from-match state in the new look (the old message path is used). **Not proven yet.**
- ✅ The survivor roster is reachable from the lobby (Survivors button; `survivor_test`).

## 5. Battlegrounds class selection inside the lobby
- 🟡 A class choice in the lobby (`LobbyClient.class_pick`, sent as `run_<class>`; `survivor_test`); a fresh level-0 run character with a basic attack and empty slots (`run_build_test`, `bg_test`).
- ✅ Class tiles with the selected class large on the stage (name, role, playstyle, its skills); every member's class and ready state; a class change in the lobby un-readies its member (service `pick`, `test_pick_changes_class_and_unreadies`; `mp_lobby_shots`, `lobby_ui_test`).
- ⬜ The class change through a real service and two clients. **Not proven yet** (step 7).
- ⬜ A level-0 character can clear a starting camp: **not proven by a fight yet** (tier I monsters are level 1; to prove with the verification bot run, step 7).

## 6. Survivors roster
- ✅ Save Character on a successful extraction only (server-confirmed `Net.cl_extracted`); a fallen run has no save (`survivor_test`, `bg_test` through a real server).
- ✅ Saves class, level, skills, slot loadout, passives, equipment and consumables; loads them back (`survivor_test`).
- ✅ No duplicates on a second press, reopened results or a second save of the same run (`survivor_test`, `bg_test`).
- ✅ Separate from single-player saves (`user://survivors/`; `survivor_test` counts characters).
- 🟡 Survivor cards: the roster lists name, class, level, camps, bosses, skills (`survivor_test`); the polished card design waits for step 6.

## 7. Arena uses saved survivors
- ✅ The Arena lobby picks a survivor; none = it says how to earn one (`survivor_test`); the join path loads it (`Game.start_join` → `Survivors.load_into`, `survivor_test`).
- ⬜ Inspect a survivor before ready (the roster shows its build; a fuller inspect panel with step 6).
- ⬜ An Arena match played with a survivor through the lobby service: **not proven yet** (step 7).
- 🟡 Compatible Arena rules kept; item stakes are hidden while survivors can't stake items (docs/cleanup.md).

## 8. One progression system, every class
- ✅ Archer and Plague Doctor: `run_build_test` (both), `survivor_test` (plague), `bg_test` (knight).
- 🟡 Every class: the pools are built from each class's own skills and talents. **Not proven per class yet** (a per-class test in step 7).

## 9. Five slots and a spellbook
- ✅ Exactly five (RMB Q E R F), the attack outside them, auto-equip into empty slots, the rest in the spellbook, G/V refused, a rebind keeps its cooldown, unlearned skills refused (`run_build_test`).
- ✅ Changing slots only between fights (`RunUI._assign`).
- ⬜ Ultimates through the same limit: they are ordinary pool skills, **not proven by a cast test yet**.

## 10. Passives instead of talents
- ✅ No talent points or talents in a run; passives with rarity, stack limits and descriptions showing the change (`run_build_test`).
- ✅ Class passives come from the class's talents (their effects already work in the skills' code); only offered once the skill they improve is learned (`run_build_test`).

## 11. Camp chest upgrades
- ✅ Clearing a camp unseals its chest; three choices; odds by tier; at least one skill while a slot is empty; no repeats or invalid options; rolled once, the same on reopening; claimed once; gear and potions as separate chest contents (`camp_test`, `run_build_test`).

## 12. Fast progression 0 → 20
- ✅ Fast curve from level 0; camp experience by tier; level-ups grow attributes and don't offer choices; camp rewards carry on past 20 (`run_build_test`, `camp_test`).
- ⬜ The pace across a whole run to level 20: **not proven yet** (step 7's bot run).

## 13. Inventory and equipment
- ✅ No gold, rings, amulets or backpack; four consumable slots with stacks of five; gear comparison and swap, the old piece left on the ground (also through the host); skills and passives apart from items (`run_build_test`, `bg_test`, `bg_pvp_test`).
- 🟡 Common/uncommon/rare gear in runs (`RunBuild.random_gear`); class-specific effects: the existing class uniques aren't in run loot yet.

## 14. A big connected lush map
- ✅ The Verdant Reach: 16 camps, 2 bosses, four starting glades, trails with loops, a stream, ridges, mushroom woodland, dark elf camps, frost hollow, ruins (`camp_test`, `bg_test`, `forest_shots`).
- 🟡 Treants and dark elf monsters of our own: the camps borrow existing monsters. **Not done.**

## 15. Every camp a complete encounter
- ✅ Each camp has its own monsters (pack), clearing ground, completion and chest; neighbours never complete each other; completion counts members wherever they are (`camp_test`).
- ✅ Tiers I-III and boss; Hrimgar and Mossbeard featured (`bg_test`).
- 🟡 Camps' compositions are curated data (`BgForest.CAMPS`); no reset rule for a camp whose monsters walk home yet.

## 16. Hosting authority
- ✅ Audit and recommendations: `docs/multiplayer_authority.md`. Survivors are documented as not tamper-proof.
- 🟡 Duplicate claims prevented on the client (offers, survivors); the server doesn't own run state yet (documented).

## 17. Verify the whole sequence and the screens
- 🟡 Automated pieces above. **Still to do (step 7):** a full archer and plague doctor run (level 0 → camps → upgrades → loot → levels → bosses → extract → save → reload → Arena), the screens at 1024x768, 1280x720, 1920x1080 and 2560x1440, and the final write-up.
