# Multiplayer overhaul: report

Blaine's spec of 2026-11-06 (17 points). The line-by-line proof is `docs/overhaul_acceptance.md`; the plan
`docs/overhaul_plan.md`; what was retired and when its code can go `docs/cleanup.md`; who decides what
`docs/multiplayer_authority.md`.

## What was built

- **Retirements behind one switch** (`scripts/mp_mode.gd`): Endless Waves gone from every menu, lobby and the
  lobby service; Create Character hidden; the old raid-with-your-own-character loop, the raid stash and the Hollow
  Crypt map switched off. Single player and Enter World untouched (a run lives only on `Hero.run`).
- **Run characters** (`RunBuild`): level 0 with a basic attack; exactly five slots (right mouse, Q E R F) and a
  spellbook; skills keep their cooldown when moved and change only between fights; passives (14 shared plus each
  class's talents, with rarity, stack limits and "16 → 24%" text) in place of talents; four consumable slots
  (stacks of five); no gold, rings, amulets or backpack; gear swaps with a comparison and the old piece is left on
  the ground; a class keeps its own weapon kind; attributes grow by themselves on a fast curve.
- **Camps** (`Camps`): tiered encounters (I-III, boss) with their own monsters and a chest sealed until they all
  fall; the chest gives everyone gear, potions and a healing potion, deep chests a class unique, and each player
  one upgrade of three (common/uncommon/rare by tier, rolled once, claimed once).
- **The Verdant Reach** (`BgForest`): an open lush forest of 16 camps on winding trails with loops, a stream, ridges
  and passes; a mushroom woodland, dark elf encampments, a frost hollow, ruins; Hrimgar and Old Mossbeard as the
  two boss camps; new Meshy monsters (treants, dark elf blades and bows).
- **Survivors** (`Survivors`): a successful extraction ends on a results screen with Save Character (one survivor
  per run, never duplicated); a roster; the Arena lobby picks a survivor and loads it exactly.
- **The multiplayer screen** (`MpLobbyView`, `MpStyle`): modern fantasy after Valorant: painted mode art (Meshy),
  mode tabs, a lobby list with filters and loading / empty / full / failure / disconnected states, a lobby where
  your class stands large on the title's lit stage beside class tiles and everyone's ready state; the run's build,
  gear swap, upgrade, results and roster windows in the same look. A lobby-service `pick` op changes class in a
  lobby.

## What was verified

- Automated (in the nightly gate unless noted): `run_build_test` (73 checks), `camp_test`, `survivor_test`,
  `bg_test` and `bg_pvp_test` through a real server, `lobby_ui_test` (needs a local lobby service), the lobby
  service's unit tests, `mp_lobby_shots` (every control on screen at 1024, 1280, 1920 and 2560 wide).
- **Whole runs played for real** (`run_playthrough -- archer|plague`): a bot with the class's real kit, nothing
  immortal, clears all 16 camps and both bosses with no deaths, ends about level 22, extracts, saves and reloads the
  survivor. It found and fixed: a leftover 2.2x monster multiplier, bosses tuned for a whole act, a boss giving six
  levels, a boss camp counted twice, the archer taking a cleaver, runs starving for healing.
- `arena_survivor_test` (two clients, the real lobby service and an Arena worker): see its result below.

## Kept for later cleanup

The crypt map and its floors, the stash, Waves' zone and leaderboard, raid stripping and `in_raid`, item stakes
(hidden while survivors can't stake), talents/gold/backpack code (single player still uses them). Each row of
`docs/cleanup.md` says when it can go.

## Hosting limits (honest)

Matches run on our servers, but those servers still trust each player's game for damage, movement, cooldowns and
what they carry, and survivors are files on the player's own machine. So survivors and Arena results are **not
tamper-proof** yet. Developer-controlled outcomes need: the server keeping each run's build and writing survivors
to Nakama with a server key, the Arena loading survivors from there, server-side damage and movement checks, and
server-held escrow for stakes (details in `docs/multiplayer_authority.md`). Nothing paid or new was deployed.

## Not done yet

- Every class other than the archer and the plague doctor played through a whole run.
- Keyboard-only navigation walked through on the multiplayer screen.
- A camp whose monsters wander home doesn't reset.
