# PvP Sandbox

In Multiplayer, select Sandbox. **Play Sandbox Solo** enters directly without a lobby or sign-in.
**Create Lobby**, Ready and Start hosts practice for one to six players; others can join while it runs.
Hosted practice is free-for-all with automatic respawns. Solo additionally offers up to five bots,
monster packs and damage meters. Both let players change their temporary class, level and gear.
No practice loot, stakes, survivor rewards or saved-character changes are intended.

Solo actions belong to the selected mode. Arena and Battlegrounds have none; the Waves action is
available only if that mode is enabled. Claude's current retirement of Waves is preserved.

## Verification

- `sandbox_entry_test.gd`: public solo entry, mode buttons, class/effect changes, repeated mixed-bot
  fights and cleanup; `sandbox_test.gd`: actual bot damage, death/respawn and character restoration.
  Both are included in the functional gate and nightly published-build audit.
- `sandbox_lobby_test.gd`: start two clients with `-- host` / `-- guest`, the same `--run-id`, and
  `--broker-url http://127.0.0.1:<isolated-port>`. Use an isolated local `service.py --dev` worker and
  its own state/output/game port. Host starts alone; guest joins the active world; tests exchange PvP
  damage, verify respawn, return home and compare a saved character byte-for-byte. Optional `--capture`
  records a rendered client. The test rejects non-loopback brokers. Bound the launcher and retire only
  its own processes afterward; acquire `heavy-tests` and isolate engine user data before running.
- KPI profiles `pvp3v3`, `pvp_dragons`, `pvp_forest` measure presentation floods; `pvp_sim.gd` measures
  real skill damage against moving targets and estimates duels. Neither certifies network correctness.

Current status: source and fixtures are prepared; broker/Python checks and GDScript grammar checks
pass. Native compilation, rendered UI/solo flows, hosted worker gameplay and the complete merged gate
remain unverified while Claude owns the shared test slot. No staging publication has occurred.
Sandbox requires the matching broker and worker changes as well as clients; a client-only upload is
insufficient. Its provisional reservation is 600 MB / 0.3 CPU core, pending measurement.

Claude's committed lobby redesign through 10652ed is integrated. `MpLobbyView` draws the Sandbox tab,
solo action/class picker and hosted class tiles; `LobbyClient` keeps the connection/lifecycle logic.
Existing mode artwork is reused and loaded through the shared catalog/cache. The screenshot fixture
covers Sandbox browse/preparation and button bounds at four logical viewport sizes; renders are pending.
