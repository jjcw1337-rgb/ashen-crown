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
## The multiplayer modes the lobby browser offers and the lobby service accepts.
const MODES := ["battlegrounds", "arena"]

## Whether a lobby mode is offered.
static func mode_on(mode: String) -> bool:
	return MODES.has(mode)
