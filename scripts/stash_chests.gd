class_name StashChests
extends RefCounted
## Every stash chest, numbered (jj: "file these under stash/chest together so I can keep track of them as I add"):
## its name, the model and dais it's built from (assets/models/stash/chest/), the fire it burns with
## (Battlegrounds.STASH_THEMES) and the maps that use it. assets/models/stash/chest/CHESTS.md is the same list for
## people, with renders in previews/. A new chest: its model in that folder, an entry here, a line there.
##   StashChests.for_map(zone)   the chest a map's stash uses (0: none of these, the old procedural chest)
##   StashChests.model(n)        a fresh instance of chest n's model (null without the file)

const DIR := "res://assets/models/stash/chest/"
const CHESTS := {
	1: {"name": "Ember Chest", "model": "chest_01", "dais": "dais_01", "theme": "ember", "maps": [],
		"note": "the first raid chest (red fire); saved for the next map"},
	2: {"name": "Spirit Chest", "model": "chest_01", "dais": "dais_01", "theme": "spirit", "maps": ["bg"],
		"note": "chest #1 burning blue: the Hollow Crypt's raid stash"},
}

static func for_map(zone: String) -> int:
	for n in CHESTS:
		if zone in CHESTS[n]["maps"]:
			return n
	return 0

static func path(n: int, part := "model") -> String:
	return DIR + str(CHESTS[n][part]) + ".glb" if CHESTS.has(n) else ""

static func has(n: int, part := "model") -> bool:
	return CHESTS.has(n) and ResourceLoader.exists(path(n, part))

static func model(n: int, part := "model") -> Node3D:
	if not has(n, part):
		return null
	return (load(path(n, part)) as PackedScene).instantiate()

static func theme(n: int) -> String:
	return str(CHESTS[n]["theme"]) if CHESTS.has(n) else "ember"
