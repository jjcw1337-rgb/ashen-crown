# The starting camp (archived, was game/maps/camp/)

Archived with Enter World on 2026-11-06: see `REVIVE.md` beside this file. What follows is the camp as it was.

Act I's camp in the old forest (zone `town`): the palisade ring, the traders' courts,
the smith's forge, the guards on their rounds, the ravens on the roofs, the World-Tree Island, and the grand
waypoint (the Battlegrounds card that opens the lobby browser). Its gates are barred: the moor and the story past
it are cut (docs/architecture_cleanup.md).

| File | What |
|---|---|
| `forest_camp.gd` | `ForestCamp`: builds the camp (World.build, zone `town`) |
| `vendor_court.gd` | the traders' open shop frontages |
| `smith_forge.gd` | `SmithForge`: the smith working at his anvil |
| `camp_guard.gd` | `CampGuard`: the three guards on their rounds |
| `camp_social.gd` | `CampSocial`: people talking to each other |
| `camp_ravens.gd`, `raven.gd` | `CampRavens`, `Raven`: the ravens on the roofs |
| `camp_island.gd` | `CampIsland`: the World-Tree Island |
| `waypoint_grand.gd` | `WaypointGrand`: the grand waypoint's dais |
| `props/camp/`, `props/island/`, `props/waypoint/` | the camp's, the island's and the waypoint's models |
| `tests/` | `camp_life_test`, `vendor_test`, `guard_test`, `waypoint_test`, `waypoint_grand_test`, `waypoint_activities_test` |
| `tools/` | screenshots and clips: `camp_shots`, `camp_aerial`, `vendor_shots`, `guard_shots`, `waypoint_*` |

The Verdant Reach borrows four of these models: `props/camp/` tent and runestone, `props/waypoint/` banner and
crystal rune. The waypoint window itself (`scripts/waypoint_panel.gd`) and the traders' nameplates (`vendor_ui.gd`)
are screens and stay with the UI.
