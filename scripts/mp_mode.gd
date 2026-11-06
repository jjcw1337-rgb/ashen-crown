class_name MpMode
extends RefCounted
## What's live after the multiplayer overhaul (Blaine, 2026-11-06): one place for the switches, instead of
## visibility checks scattered round the project. docs/cleanup.md lists what each one retires and when the code
## behind it can go.

## Endless Waves (the Last Flame, vigil.gd) is retired: no lobby mode, no solo start, no waypoint activity, the camp's
## Vigil Gate sealed. Its code stays until docs/cleanup.md's conditions are met.
const WAVES := false
## The title's Create New Character is hidden: multiplayer makes its run characters in the Battlegrounds lobby.
## (The class picker and character saves stay: Enter World and single player still use them.)
const CREATE_CHARACTER := false
## Multiplayer runs: Battlegrounds characters start fresh at level 0 (RunBuild): five skill slots and a spellbook,
## passives from camp chests in place of talents, no gold, rings, amulets or backpack. Single player is unaffected.
const RUNS := true
## The Battlegrounds stash (the spawn chests' shared storage) belongs to the old raid-with-your-character loop; run
## characters carry nothing in or out but what they wear.
const STASH := false
## The multiplayer modes the lobby browser offers and the lobby service accepts.
const MODES := ["battlegrounds", "arena"]

## Whether a lobby mode is offered.
static func mode_on(mode: String) -> bool:
	return MODES.has(mode)
