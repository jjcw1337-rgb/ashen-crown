class_name Data
extends RefCounted
## Static game data: acts, monsters, item bases, affixes, uniques, vendors.

const ACTS := [
	{"name": "The Ashen Moors", "town": "The Forsaken Wilds", "wild": "Cairnfell Moor", "lair": "Grubb's Fort",
		"boss": "goblin_king", "lvl": 1, "theme": "moor", "foes": ["fallen", "zombie", "skel_archer"]},
	{"name": "The Sunscar Wastes", "town": "Lut Khemar", "wild": "Dunes of Sorrow", "lair": "Tomb of Sekhmun",
		"boss": "sekhmun", "lvl": 8, "theme": "desert", "foes": ["raider", "mummy", "scarab"]},
	{"name": "The Drowned Wilds", "town": "Vel Dara", "wild": "Mirewood", "lair": "Temple of Vael",
		"boss": "vael", "lvl": 15, "theme": "jungle", "foes": ["fetish", "spider", "lizardman"]},
	{"name": "The Burning Abyss", "town": "Bastion of Dawn", "wild": "Plains of Cinder", "lair": "Throne of Cinders",
		"boss": "malgoroth", "lvl": 22, "theme": "hell", "foes": ["imp", "hell_knight", "doom_caster"]},
]

## A2 is its own act on Act I's camp: the Imperial Road (via.gd: the moor, a bandit ambush, the old
## Roman road, Aurelia's outskirts) to the city of Aurelia and its arena (aurelia.gd), where the champion
## of the games (games.gd) is the act's boss. Keys override Data.ACTS[0] for that run (act_info).
const RUN_ACTS := {
	1: {"name": "The Imperial Road", "wild": "The Imperial Road", "lair": "Aurelia", "boss": "champion",
		"foes": ["zombie", "fallen", "skel_archer"]},
}

## An act's names, boss and foes for a run (difficulty): Data.ACTS with that run's overrides.
static func act_info(act: int, run: int) -> Dictionary:
	if act == 0 and RUN_ACTS.has(run):
		return ACTS[act].merged(RUN_ACTS[run], true)
	return ACTS[act]

## The waypoint network, one entry per act in the order they unlock (an act is a run of the game:
## `run` is its difficulty index, Data.RUNS). An act opens once the act before it falls (Game.max_run);
## each of its waypoints opens once a player touches that waypoint stone (Game.waypoints_known, kept
## per act in Game.run_progress). The camp's is open as soon as you arrive.
## Adding an act: a RUNS entry (+ RUN_ACTS names), its zones, and an entry here ("name" overrides the
## tab name, which is otherwise Data.RUNS[run].name).
## Adding a waypoint: a point here (a new id; its zone), and in that zone's builder one line,
## `add_waypoint("<id>", Vector3(x, 0, z))` (World.add_waypoint: the stone, its colliders and its own
## arrival spot), so a zone can hold several (see World / Via / ForestCamp for the existing ones). A new zone also goes in
## WAYPOINT_ZONES and World.build. check_waypoints() reports mistakes (dev builds print them at start).
## Optional per entry: "name" (the tab's name; else Data.RUNS[run].name), "requires" (open once that
## run's lord falls, instead of the act before it: for side areas such as Ancient Levels).
##   group: its tab group (WAYPOINT_GROUPS) · tab: the numeral on the act's tab (its name is Data.RUNS[run].name) · art: its banner (Meshy) · points: id (what the stone binds),
##   zone (where it takes you), kind (camp | wild | road | city: its icon), name (optional; else the
##   act's name for that zone) · boss: the lord whose fall opens the next act
## The window's tab groups, left to right; a group shows only once it has an entry (group: its id).
const WAYPOINT_GROUPS := [
	{"id": "acts", "name": "Acts"},
	{"id": "ancient", "name": "Ancient Levels"},
]

const WAYPOINT_ACTS := [
	{"run": 0, "group": "acts", "tab": "I", "art": "res://assets/textures/ui/wp_act1.png", "boss": "goblin_king",
		"points": [{"id": "town", "zone": "town", "kind": "camp"}, {"id": "wild", "zone": "wild", "kind": "wild"}]},
	{"run": 1, "group": "acts", "tab": "II", "art": "res://assets/textures/ui/wp_act2.png", "boss": "champion",
		"points": [{"id": "town", "zone": "town", "kind": "camp"}, {"id": "wild", "zone": "wild", "kind": "road"}]},
	{"run": 2, "group": "acts", "tab": "III", "art": "res://assets/textures/ui/wp_act3.png", "boss": "ashen_king",
		"points": [{"id": "town", "zone": "town", "kind": "camp"}, {"id": "wild", "zone": "wild", "kind": "wild"}]},
]

static func waypoint_act(run: int) -> Dictionary:
	for a in WAYPOINT_ACTS:
		if int(a["run"]) == run:
			return a
	return {}

static func waypoint_point(run: int, id: String) -> Dictionary:
	for p in waypoint_act(run).get("points", []):
		if str(p["id"]) == id:
			return p
	return {}

## Zones the world can build (World.build); a waypoint must lead to one of these.
const WAYPOINT_ZONES := ["town", "wild", "lair"]

## Problems in WAYPOINT_ACTS, one line each (empty = all good). Checked at start in dev builds
## (Game) and by tools/waypoint_test.gd, so a mistake shows the moment it is made.
static func check_waypoints() -> Array:
	var errs := []
	var runs := {}
	var groups := WAYPOINT_GROUPS.map(func(g): return g["id"])
	for a in WAYPOINT_ACTS:
		var r := int(a.get("run", -1))
		var tag := "act run %d" % r
		if runs.has(r):
			errs.append(tag + ": run used twice")
		runs[r] = true
		if not groups.has(a.get("group", "acts")):
			errs.append(tag + ": unknown group '%s' (add it to WAYPOINT_GROUPS)" % a.get("group"))
		if a.has("art") and not ResourceLoader.exists(a["art"]):
			errs.append(tag + ": banner not found: " + str(a["art"]))
		if a.has("boss") and not ENEMIES.has(a["boss"]):
			errs.append(tag + ": unknown boss '%s'" % a["boss"])
		if not a.has("requires") and r >= RUNS.size():
			errs.append(tag + ": no Data.RUNS entry (or give it \"requires\")")
		var pts: Array = a.get("points", [])
		if pts.is_empty():
			errs.append(tag + ": no waypoints")
		var ids := {}
		for p in pts:
			var id := str(p.get("id", ""))
			if id == "" or ids.has(id):
				errs.append(tag + ": waypoint id missing or used twice ('%s')" % id)
			ids[id] = true
			if not WAYPOINT_ZONES.has(str(p.get("zone", ""))):
				errs.append(tag + ": waypoint '%s' leads to unknown zone '%s'" % [id, p.get("zone", "")])
	return errs

const VENDORS := [
	{"smith": "Halvar Emberhammer", "armor": "Hedda Ironhand", "alch": "Agnes Grimwood", "gamble": "Tarrow the Dice", "stash": "Stash", "elder": "Captain Roth"},
	{"smith": "Kadir Forgebrand", "armor": "Saphra", "alch": "Iskander the Wise", "gamble": "Jamal Two-Coins", "stash": "Stash", "elder": "Vizier Hasun"},
	{"smith": "Ombo Stonejaw", "armor": "Teyla of the Reeds", "alch": "Mother Ashka", "gamble": "Quill", "stash": "Stash", "elder": "Archivist Nel"},
	{"smith": "Brother Halvard", "armor": "Seraph Aldwen", "alch": "Lumen the Pure", "gamble": "The Faceless", "stash": "Stash", "elder": "High Paladin Corin"},
]

## look keys: skin, cloth, cloth2, armor, height, bulk, head, eyes, horns, cape, thin, tail, wings, weapon, shield
const ENEMIES := {
	"fallen": {"mesh": "fallen", "name": "Fallen", "rig": "humanoid", "life": 14, "dmg": [2, 5], "speed": 4.2, "range": 1.5, "xp": 9,
		"ai": "melee", "atk": "over", "atk_time": 0.85, "armor": 2, "radius": 0.45, "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.62, 0.12, 0.08), "cloth": Color(0.22, 0.16, 0.1), "height": 0.72, "bulk": 0.9, "head": "horned", "eyes": Color(1.0, 0.8, 0.1), "weapon": "club"}},
	"zombie": {"mesh": "zombie", "faction": "undead", "name": "Zombie", "rig": "humanoid", "life": 32, "dmg": [3, 7], "speed": 1.9, "range": 1.6, "xp": 13,
		"ai": "melee", "atk": "claw", "atk_time": 1.25, "armor": 4, "radius": 0.5, "blood": Color(0.25, 0.3, 0.05),
		"look": {"skin": Color(0.42, 0.48, 0.36), "cloth": Color(0.25, 0.23, 0.2), "cloth2": Color(0.18, 0.16, 0.14), "height": 1.0, "bulk": 1.1, "head": "human", "hair": Color(0.15, 0.15, 0.12), "eyes": Color(0.6, 1.0, 0.3)}},
	# the Feral (feral.gd): packs cling to oak trunks deep in the Act I forest and drop on you
	"feral": {"mesh": "feral", "name": "Feral", "rig": "humanoid", "life": 15, "dmg": [2, 5], "speed": 4.2, "range": 1.4, "xp": 12,
		"ai": "feral", "atk": "feral_swipe", "atk_time": 0.8, "armor": 1, "radius": 0.5, "aggro": 14.0, "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.66, 0.6, 0.55), "cloth": Color(0.25, 0.2, 0.15), "height": 0.72, "bulk": 0.8, "head": "human", "hair": Color(0.08, 0.07, 0.06), "eyes": Color(1.0, 0.7, 0.3)}},
	# A2: the bandits of the Imperial Road (they wait hidden and spring an ambush, via.gd) and the beasts,
	# gladiators and champion of Aurelia's arena (games.gd). "mesh" picks the Meshy model when it's there.
	"bandit": {"mesh": "bandit", "name": "Road Bandit", "rig": "humanoid", "life": 22, "dmg": [3, 7], "speed": 4.4, "range": 1.6, "xp": 13,
		"ai": "melee", "atk": "side", "atk_time": 0.8, "armor": 3, "radius": 0.45, "faction": "bandit", "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.62, 0.46, 0.34), "cloth": Color(0.3, 0.24, 0.16), "cloth2": Color(0.22, 0.25, 0.14), "height": 1.0, "bulk": 0.95, "head": "human", "hair": Color(0.12, 0.09, 0.06), "weapon": "scimitar"}},
	"bandit_archer": {"mesh": "bandit", "name": "Bandit Bowman", "rig": "humanoid", "life": 16, "dmg": [3, 6], "speed": 3.6, "range": 12.0, "xp": 12,
		"ai": "ranged", "atk": "bow", "atk_time": 1.2, "armor": 2, "radius": 0.45, "proj": "arrow", "faction": "bandit", "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.6, 0.45, 0.33), "cloth": Color(0.26, 0.22, 0.15), "cloth2": Color(0.3, 0.2, 0.12), "height": 0.98, "bulk": 0.9, "head": "human", "hair": Color(0.15, 0.1, 0.07), "weapon": "bow"}},
	"lion": {"mesh": "lion", "name": "Arena Lion", "rig": "crawler", "life": 30, "dmg": [4, 8], "speed": 5.0, "range": 1.9, "xp": 16,
		"ai": "feral", "atk": "feral_swipe", "atk_time": 0.95, "armor": 3, "radius": 0.8, "aggro": 30.0, "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.55, 0.4, 0.22), "shell": Color(0.3, 0.2, 0.1), "legs": 4, "size": 1.2, "eyes": Color(1.0, 0.75, 0.2)}},
	"gladiator": {"mesh": "gladiator", "name": "Gladiator", "rig": "humanoid", "life": 44, "dmg": [5, 10], "speed": 4.0, "range": 1.7, "xp": 22,
		"ai": "melee", "atk": "side", "atk_time": 0.85, "armor": 8, "radius": 0.5, "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.66, 0.48, 0.36), "cloth": Color(0.85, 0.82, 0.74), "armor": Color(0.7, 0.5, 0.22), "height": 1.05, "bulk": 1.15, "head": "human", "hair": Color(0.1, 0.08, 0.06), "weapon": "scimitar"}},
	"champion": {"mesh": "champion", "name": "Aurelius, Champion of the Arena", "rig": "humanoid", "life": 220, "dmg": [9, 16], "speed": 3.4, "range": 2.4, "xp": 520,
		"ai": "boss", "atk": "over", "atk_time": 1.1, "armor": 9, "radius": 0.9, "boss": true, "summon": "", "slam": true, "nova": "", "proj": "",
		"aggro": 45.0, "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.62, 0.45, 0.33), "cloth": Color(0.55, 0.06, 0.05), "armor": Color(0.85, 0.65, 0.25), "height": 1.5, "bulk": 1.35, "head": "human", "hair": Color(0.1, 0.08, 0.06), "weapon": "scimitar", "cape": Color(0.55, 0.06, 0.05)}},
	# King Grubb's Gold Grabbers: they scoop up his spilled gold and haul it back to him (hoard.gd)
	"grabber": {"name": "Gold Grabber", "rig": "humanoid", "model": "grabber", "life": 13, "dmg": [2, 4], "speed": 4.4, "range": 1.3, "xp": 6, "no_loot": true,
		"ai": "melee", "atk": "thrust", "atk_time": 0.75, "armor": 2, "radius": 0.4, "blood": Color(0.4, 0.05, 0.02),
		"look": {"height": 0.75, "eyes": Color(1.0, 0.6, 0.1)}},
	# the goblins of Grubb's fort: they guard it, and fight the moor's dead on sight ("faction")
	"goblin_guard": {"mesh": "goblin_guard", "faction": "goblin", "name": "Goblin Guard", "rig": "humanoid", "life": 24, "dmg": [3, 7], "speed": 3.8, "range": 1.6, "xp": 12,
		"ai": "melee", "atk": "over", "atk_time": 0.9, "armor": 4, "radius": 0.45, "blood": Color(0.35, 0.08, 0.03),
		"look": {"height": 0.8, "eyes": Color(1.0, 0.7, 0.1), "weapon": "scimitar"}},
	"skel_archer": {"mesh": "archer", "name": "Bone Archer", "rig": "humanoid", "life": 18, "dmg": [3, 6], "speed": 3.0, "range": 11.0, "xp": 12,
		"ai": "ranged", "atk": "bow", "atk_time": 1.3, "armor": 3, "radius": 0.45, "proj": "arrow", "skin": "archer", "blood": Color(0.85, 0.82, 0.7),
		"look": {"skin": Color(0.85, 0.82, 0.72), "cloth": Color(0.25, 0.2, 0.15), "height": 1.0, "bulk": 0.8, "head": "skull", "thin": true, "eyes": Color(0.3, 0.7, 1.0), "weapon": "bow"}},
	"goblin_king": {"name": "King Grubb the Gilded", "rig": "humanoid", "model": "mutant", "life": 360, "dmg": [9, 16], "speed": 2.5, "range": 3.2, "xp": 420,
		"ai": "boss", "atk": "smash", "atk_time": 1.3, "armor": 10, "radius": 1.35, "boss": true, "summon": "", "slam": true, "nova": "", "proj": "", "hoard": true,
		"blood": Color(0.4, 0.05, 0.02),
		"look": {"height": 2.0, "eyes": Color(1.0, 0.75, 0.15)}},

	"ashen_king": {"name": "The Ashen King", "rig": "humanoid", "skin": "king", "life": 900, "dmg": [14, 24], "speed": 2.8, "range": 2.9, "xp": 900,
		"ai": "boss", "atk": "over", "atk_time": 1.2, "armor": 18, "radius": 0.95, "boss": true, "summon": "skel_archer", "slam": true, "nova": "fire", "proj": "fireball",
		"boss_drop": "cinderbrand", "blood": Color(0.25, 0.2, 0.15),
		"look": {"height": 1.85, "eyes": Color(1.0, 0.35, 0.05)}},

	"raider": {"name": "Sand Raider", "rig": "humanoid", "life": 26, "dmg": [5, 10], "speed": 4.0, "range": 1.7, "xp": 18,
		"ai": "melee", "atk": "side", "atk_time": 0.9, "armor": 8, "radius": 0.45, "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.55, 0.38, 0.25), "cloth": Color(0.75, 0.68, 0.52), "cloth2": Color(0.45, 0.15, 0.1), "height": 1.0, "bulk": 1.0, "head": "turban", "weapon": "scimitar"}},
	"mummy": {"name": "Embalmed", "rig": "humanoid", "life": 48, "dmg": [6, 12], "speed": 1.8, "range": 1.7, "xp": 24,
		"ai": "melee", "atk": "claw", "atk_time": 1.3, "armor": 10, "radius": 0.5, "blood": Color(0.6, 0.55, 0.4),
		"look": {"skin": Color(0.72, 0.65, 0.5), "cloth": Color(0.68, 0.6, 0.45), "height": 1.05, "bulk": 1.0, "head": "mummy", "eyes": Color(1.0, 0.6, 0.1)}},
	"scarab": {"name": "Dune Scarab", "rig": "crawler", "life": 30, "dmg": [5, 9], "speed": 5.0, "range": 1.6, "xp": 20,
		"ai": "melee", "atk": "bite", "atk_time": 0.8, "armor": 14, "radius": 0.7, "blood": Color(0.3, 0.6, 0.1),
		"look": {"skin": Color(0.12, 0.3, 0.32), "shell": Color(0.1, 0.45, 0.4), "legs": 6, "size": 0.9, "eyes": Color(1.0, 0.5, 0.1), "horn": true}},
	"sekhmun": {"name": "Sekhmun the Undying", "rig": "humanoid", "life": 1250, "dmg": [16, 26], "speed": 2.4, "range": 2.6, "xp": 1500,
		"ai": "boss", "atk": "over", "atk_time": 1.2, "armor": 24, "radius": 0.9, "boss": true, "summon": "mummy", "slam": true, "nova": "", "proj": "fireball",
		"blood": Color(0.6, 0.5, 0.3),
		"look": {"skin": Color(0.6, 0.52, 0.38), "cloth": Color(0.62, 0.55, 0.4), "cloth2": Color(0.1, 0.25, 0.55), "armor": Color(0.85, 0.65, 0.2), "height": 2.1, "bulk": 1.2, "head": "pharaoh", "eyes": Color(0.3, 0.8, 1.0), "weapon": "staff"}},

	"fetish": {"name": "Mire Fetish", "rig": "humanoid", "life": 26, "dmg": [6, 11], "speed": 4.6, "range": 10.0, "xp": 28,
		"ai": "ranged", "atk": "thrust", "atk_time": 1.0, "armor": 10, "radius": 0.4, "proj": "dart", "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.35, 0.22, 0.12), "cloth": Color(0.3, 0.45, 0.15), "height": 0.62, "bulk": 0.85, "head": "mask", "eyes": Color(1.0, 0.9, 0.2), "weapon": "blowgun"}},
	"spider": {"name": "Bog Spider", "rig": "crawler", "life": 44, "dmg": [8, 14], "speed": 5.3, "range": 1.7, "xp": 32,
		"ai": "melee", "atk": "bite", "atk_time": 0.85, "armor": 12, "radius": 0.8, "blood": Color(0.3, 0.6, 0.1),
		"look": {"skin": Color(0.12, 0.1, 0.08), "shell": Color(0.2, 0.15, 0.08), "legs": 8, "size": 1.1, "eyes": Color(1.0, 0.1, 0.1), "stripe": Color(0.7, 0.4, 0.05)}},
	"lizardman": {"name": "Saurian Spearman", "rig": "humanoid", "life": 62, "dmg": [10, 17], "speed": 3.8, "range": 2.4, "xp": 38,
		"ai": "melee", "atk": "thrust", "atk_time": 1.0, "armor": 18, "radius": 0.5, "blood": Color(0.5, 0.05, 0.02),
		"look": {"skin": Color(0.22, 0.38, 0.18), "cloth": Color(0.4, 0.28, 0.15), "height": 1.15, "bulk": 1.05, "head": "beast", "eyes": Color(1.0, 0.85, 0.1), "tail": true, "weapon": "spear"}},
	"vael": {"name": "Archon Vael", "rig": "humanoid", "life": 2300, "dmg": [24, 36], "speed": 2.8, "range": 2.6, "xp": 4200,
		"ai": "boss", "atk": "side", "atk_time": 1.1, "armor": 40, "radius": 0.9, "boss": true, "summon": "fetish", "slam": false, "nova": "poison", "proj": "poison",
		"blood": Color(0.3, 0.6, 0.1),
		"look": {"skin": Color(0.25, 0.32, 0.2), "cloth": Color(0.1, 0.25, 0.15), "cloth2": Color(0.6, 0.5, 0.15), "height": 2.2, "bulk": 1.1, "head": "mask", "eyes": Color(0.4, 1.0, 0.3), "cape": Color(0.08, 0.2, 0.12), "weapon": "staff", "horns": true}},

	"imp": {"name": "Cinder Imp", "rig": "humanoid", "life": 46, "dmg": [12, 19], "speed": 5.2, "range": 1.5, "xp": 46,
		"ai": "melee", "atk": "claw", "atk_time": 0.75, "armor": 20, "radius": 0.45, "blood": Color(0.9, 0.3, 0.05),
		"look": {"skin": Color(0.55, 0.08, 0.04), "cloth": Color(0.12, 0.05, 0.03), "height": 0.8, "bulk": 0.85, "head": "horned", "eyes": Color(1.0, 0.7, 0.1), "wings": true, "tail": true}},
	"hell_knight": {"name": "Doom Knight", "rig": "humanoid", "life": 120, "dmg": [18, 28], "speed": 3.0, "range": 2.0, "xp": 72,
		"ai": "melee", "atk": "over", "atk_time": 1.15, "armor": 40, "radius": 0.6, "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.2, 0.1, 0.1), "cloth": Color(0.15, 0.05, 0.05), "armor": Color(0.12, 0.11, 0.12), "height": 1.3, "bulk": 1.3, "head": "dark_helm", "eyes": Color(1.0, 0.2, 0.05), "weapon": "great_sword", "spikes": true}},
	"doom_caster": {"name": "Ashen Invoker", "rig": "humanoid", "life": 70, "dmg": [16, 26], "speed": 3.2, "range": 11.0, "xp": 60,
		"ai": "ranged", "atk": "cast", "atk_time": 1.3, "armor": 22, "radius": 0.45, "proj": "fireball", "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.3, 0.25, 0.22), "cloth": Color(0.2, 0.06, 0.05), "cloth2": Color(0.55, 0.3, 0.1), "height": 1.05, "bulk": 0.95, "head": "hood", "eyes": Color(1.0, 0.45, 0.05), "weapon": "staff", "cape": Color(0.25, 0.05, 0.04)}},
	"malgoroth": {"name": "Malgoroth, Lord of Cinders", "rig": "humanoid", "life": 4800, "dmg": [32, 50], "speed": 3.0, "range": 3.2, "xp": 12000,
		"ai": "boss", "atk": "slam", "atk_time": 1.3, "armor": 60, "radius": 1.3, "boss": true, "summon": "imp", "slam": true, "nova": "fire", "proj": "fireball",
		"blood": Color(0.9, 0.3, 0.05),
		"look": {"skin": Color(0.45, 0.06, 0.03), "cloth": Color(0.1, 0.03, 0.02), "armor": Color(0.15, 0.12, 0.1), "height": 3.0, "bulk": 1.5, "head": "demon", "eyes": Color(1.0, 0.75, 0.2), "wings": true, "tail": true, "horns": true, "weapon": "great_axe", "spikes": true}},
}

## Champion name prefixes for elite packs.
const CHAMP_PREFIX := ["Gloom", "Rot", "Blood", "Storm", "Grim", "Bane", "Cinder", "Vile", "Doom", "Ash"]
const CHAMP_SUFFIX := ["maw", "fang", "hide", "brand", "skull", "spine", "heart", "claw"]

## Item bases. slot: weapon, shield, helm, armor, gloves, boots, belt, ring, amulet, potion, gold
const BASES := {
	"short_sword": {"name": "Short Sword", "slot": "weapon", "kind": "sword", "dmg": [2, 6], "speed": 1.1, "lvl": 1, "price": 30, "shape": {"len": 0.62, "w": 0.06, "guard": 0.2}},
	"falchion": {"name": "Falchion", "slot": "weapon", "kind": "sword", "dmg": [4, 10], "speed": 1.0, "lvl": 5, "price": 80, "shape": {"len": 0.72, "w": 0.075, "guard": 0.22, "curve": 1.0}},
	"broad_sword": {"name": "Broad Sword", "slot": "weapon", "kind": "sword", "dmg": [7, 15], "speed": 1.0, "lvl": 11, "price": 160, "shape": {"len": 0.82, "w": 0.095, "guard": 0.3}},
	"flamberge": {"name": "Flamberge", "slot": "weapon", "kind": "sword", "dmg": [12, 24], "speed": 0.95, "lvl": 19, "price": 320, "shape": {"len": 0.95, "w": 0.08, "guard": 0.34, "wavy": 1.0}},
	"runeblade": {"name": "Runeblade", "slot": "weapon", "kind": "sword", "dmg": [18, 34], "speed": 1.05, "lvl": 26, "price": 600, "shape": {"len": 1.0, "w": 0.1, "guard": 0.36, "runes": 1.0}},
	"hand_axe": {"name": "Hand Axe", "slot": "weapon", "kind": "axe", "dmg": [3, 7], "speed": 1.05, "lvl": 2, "price": 35, "shape": {"haft": 0.6, "head": 0.16}},
	"war_axe": {"name": "War Axe", "slot": "weapon", "kind": "axe", "dmg": [9, 19], "speed": 0.9, "lvl": 13, "price": 190, "shape": {"haft": 0.75, "head": 0.24, "double": 1.0}},
	"executioner": {"name": "Headsman's Axe", "slot": "weapon", "kind": "axe", "dmg": [16, 32], "speed": 0.85, "lvl": 22, "price": 420, "shape": {"haft": 0.85, "head": 0.32, "beard": 1.0}},
	"club": {"name": "Spiked Club", "slot": "weapon", "kind": "club", "dmg": [2, 7], "speed": 1.0, "lvl": 1, "price": 20, "shape": {"len": 0.6}},
	"mace": {"name": "Flanged Mace", "slot": "weapon", "kind": "mace", "dmg": [5, 11], "speed": 1.0, "lvl": 6, "price": 90, "shape": {"len": 0.62, "flanges": 6}},
	"morning_star": {"name": "Morning Star", "slot": "weapon", "kind": "star", "dmg": [9, 18], "speed": 0.95, "lvl": 14, "price": 200, "shape": {"len": 0.66}},
	"war_hammer": {"name": "War Hammer", "slot": "weapon", "kind": "hammer", "dmg": [14, 28], "speed": 0.85, "lvl": 20, "price": 360, "shape": {"len": 0.75}},

	"buckler": {"name": "Buckler", "slot": "shield", "kind": "round", "def": 4, "block": 18, "lvl": 1, "price": 25, "shape": {"r": 0.2}},
	"kite_shield": {"name": "Kite Shield", "slot": "shield", "kind": "kite", "def": 10, "block": 24, "lvl": 6, "price": 90, "shape": {"w": 0.42, "h": 0.64}},
	"spiked_shield": {"name": "Spiked Targe", "slot": "shield", "kind": "spiked", "def": 16, "block": 26, "lvl": 12, "price": 170, "shape": {"r": 0.27}},
	"tower_shield": {"name": "Tower Shield", "slot": "shield", "kind": "tower", "def": 26, "block": 32, "lvl": 18, "price": 300, "shape": {"w": 0.5, "h": 0.86}},
	"aegis": {"name": "Gilded Aegis", "slot": "shield", "kind": "aegis", "def": 40, "block": 36, "lvl": 25, "price": 560, "shape": {"w": 0.52, "h": 0.7}},

	"cap": {"name": "Leather Cap", "slot": "helm", "kind": "cap", "def": 3, "lvl": 1, "price": 15},
	"skull_cap": {"name": "Skull Cap", "slot": "helm", "kind": "skullcap", "def": 7, "lvl": 5, "price": 60},
	"great_helm": {"name": "Great Helm", "slot": "helm", "kind": "great", "def": 15, "lvl": 12, "price": 160},
	"horned_helm": {"name": "Horned Helm", "slot": "helm", "kind": "horned", "def": 22, "lvl": 18, "price": 260},
	"crown": {"name": "Crown", "slot": "helm", "kind": "crown", "def": 30, "lvl": 24, "price": 450},

	"quilted": {"name": "Quilted Armor", "slot": "armor", "kind": "quilted", "def": 6, "lvl": 1, "price": 30},
	"leather_armor": {"name": "Studded Leather", "slot": "armor", "kind": "leather", "def": 12, "lvl": 4, "price": 70},
	"chain_mail": {"name": "Chain Mail", "slot": "armor", "kind": "chain", "def": 24, "lvl": 9, "price": 150},
	"plate_mail": {"name": "Plate Mail", "slot": "armor", "kind": "plate", "def": 42, "lvl": 16, "price": 300},
	"ornate_plate": {"name": "Ornate Plate", "slot": "armor", "kind": "ornate", "def": 64, "lvl": 24, "price": 560},

	"leather_gloves": {"name": "Leather Gloves", "slot": "gloves", "kind": "gloves", "def": 2, "lvl": 1, "price": 15},
	"gauntlets": {"name": "Gauntlets", "slot": "gloves", "kind": "gauntlets", "def": 10, "lvl": 12, "price": 140},
	"leather_boots": {"name": "Leather Boots", "slot": "boots", "kind": "boots", "def": 2, "lvl": 1, "price": 15},
	"greaves": {"name": "Plated Greaves", "slot": "boots", "kind": "greaves", "def": 10, "lvl": 12, "price": 140},
	"sash": {"name": "Sash", "slot": "belt", "kind": "sash", "def": 1, "lvl": 1, "price": 15},
	"war_belt": {"name": "War Belt", "slot": "belt", "kind": "warbelt", "def": 8, "lvl": 12, "price": 130},
	"ring": {"name": "Ring", "slot": "ring", "kind": "ring", "lvl": 1, "price": 60},
	"amulet": {"name": "Amulet", "slot": "amulet", "kind": "amulet", "lvl": 1, "price": 90},

	"hp_potion": {"name": "Healing Potion", "slot": "potion", "kind": "potion", "lvl": 1, "price": 12, "heal": 60, "color": Color(0.9, 0.05, 0.05)},
	"mp_potion": {"name": "Mana Potion", "slot": "potion", "kind": "potion", "lvl": 1, "price": 12, "mana": 40, "color": Color(0.1, 0.25, 1.0)},
	"rejuv": {"name": "Rejuvenation Potion", "slot": "potion", "kind": "potion", "lvl": 1, "price": 60, "rejuv": 0.4, "color": Color(0.6, 0.1, 0.9)},
	"gold": {"name": "Gold", "slot": "gold", "kind": "gold", "lvl": 1, "price": 0},
}

## Affixes: [stat, prefix/suffix name, min, max, per-level growth]
const AFFIXES := [
	["ed", "Cruel", 15, 40, 3.0],
	["dmg", "Sharp", 1, 4, 0.5],
	["fire", "Blazing", 2, 6, 0.8],
	["str", "of Strength", 2, 6, 0.4],
	["dex", "of Skill", 2, 6, 0.4],
	["vit", "of Vigor", 2, 6, 0.4],
	["life", "of the Whale", 8, 20, 2.0],
	["mana", "of the Owl", 6, 15, 1.2],
	["ias", "of Haste", 8, 20, 0.6],
	["ls", "of the Leech", 2, 5, 0.15],
	["def", "Sturdy", 6, 18, 2.0],
	["edef", "Stout", 15, 40, 2.0],
	["res", "Prismatic", 5, 15, 0.8],
	["block", "of the Wall", 4, 10, 0.2],
	["gf", "of Greed", 15, 50, 2.0],
	["mf", "of Fortune", 8, 25, 1.0],
	["regen", "of Renewal", 1, 3, 0.2],
	["frw", "of Speed", 6, 15, 0.3],
]

const STAT_LABEL := {
	"ed": "+%d%% Enhanced Damage", "dmg": "+%d Damage", "fire": "Adds %d Fire Damage", "str": "+%d to Strength",
	"dex": "+%d to Dexterity", "vit": "+%d to Vitality", "life": "+%d to Life", "mana": "+%d to Mana",
	"ias": "+%d%% Attack Speed", "ls": "%d%% Life Stolen per Hit", "def": "+%d Defense", "edef": "+%d%% Enhanced Defense",
	"res": "All Resistances +%d", "block": "+%d%% Chance to Block", "gf": "%d%% Extra Gold", "mf": "%d%% Better Chance of Magic Items",
	"regen": "Replenish %d Life per second", "frw": "+%d%% Faster Run/Walk",
}

## Which affixes can roll on which slot class.
const AFFIX_SLOTS := {
	"weapon": ["ed", "dmg", "fire", "str", "dex", "ias", "ls", "life", "mana", "mf"],
	"shield": ["def", "edef", "res", "block", "vit", "life", "str"],
	"helm": ["def", "edef", "res", "life", "mana", "mf", "regen", "vit"],
	"armor": ["def", "edef", "res", "life", "vit", "str", "regen"],
	"gloves": ["def", "ias", "dex", "str", "ls", "gf"],
	"boots": ["def", "frw", "res", "dex", "gf", "mf"],
	"belt": ["def", "life", "vit", "str", "gf", "regen"],
	"ring": ["str", "dex", "vit", "life", "mana", "ls", "res", "mf", "fire", "dmg"],
	"amulet": ["str", "dex", "vit", "life", "mana", "res", "mf", "gf", "fire", "ias"],
}

const RARE_A := ["Grim", "Blood", "Storm", "Dread", "Wraith", "Rune", "Ghoul", "Doom", "Raven", "Bone", "Ember", "Shadow", "Hailstone", "Viper"]
const RARE_B := {
	"weapon": ["Bite", "Song", "Edge", "Fang", "Reaver", "Cleaver", "Thirst"],
	"shield": ["Ward", "Wall", "Bastion", "Guard", "Aegis"],
	"helm": ["Visage", "Crest", "Horn", "Brow", "Cowl"],
	"armor": ["Shell", "Hide", "Mantle", "Carapace", "Coat"],
	"gloves": ["Grip", "Fist", "Clutch", "Knuckle"],
	"boots": ["Stride", "Track", "Trample", "Road"],
	"belt": ["Coil", "Cord", "Lock", "Strap"],
	"ring": ["Loop", "Band", "Circle", "Spiral"],
	"amulet": ["Charm", "Heart", "Talisman", "Eye"],
}

## Unique items with fixed bases, stats and a signature look.
const UNIQUES := {
	"emberfang": {"name": "Emberfang", "base": "falchion", "lvl": 6, "stats": [["ed", 80], ["fire", 8], ["ias", 15], ["ls", 3]],
		"metal": Color(0.25, 0.08, 0.04), "trim": Color(0.95, 0.55, 0.15), "glow": Color(1.0, 0.4, 0.05), "gem": Color(1.0, 0.3, 0.0)},
	"wardens_wall": {"name": "The Warden's Wall", "base": "kite_shield", "lvl": 7, "stats": [["edef", 90], ["block", 12], ["res", 15], ["life", 25]],
		"metal": Color(0.55, 0.57, 0.62), "trim": Color(0.25, 0.45, 0.85), "glow": Color(0.3, 0.6, 1.0), "gem": Color(0.3, 0.6, 1.0)},
	"ashen_king": {"name": "Crown of the Ashen King", "base": "crown", "lvl": 24, "stats": [["edef", 120], ["life", 60], ["res", 25], ["mf", 40]],
		"metal": Color(0.2, 0.2, 0.22), "trim": Color(0.9, 0.9, 0.95), "glow": Color(0.8, 0.85, 1.0), "gem": Color(0.9, 0.1, 0.2)},
	"bloodweave": {"name": "Bloodweave Mail", "base": "chain_mail", "lvl": 10, "stats": [["edef", 100], ["ls", 5], ["str", 15], ["life", 40]],
		"metal": Color(0.45, 0.08, 0.08), "trim": Color(0.15, 0.15, 0.15), "glow": Color(1.0, 0.05, 0.1), "gem": Color(1.0, 0.0, 0.1)},
	"stormstride": {"name": "Stormstride", "base": "greaves", "lvl": 14, "stats": [["frw", 30], ["dex", 15], ["res", 20], ["edef", 80]],
		"metal": Color(0.35, 0.4, 0.55), "trim": Color(0.6, 0.85, 1.0), "glow": Color(0.5, 0.8, 1.0), "gem": Color(0.5, 0.8, 1.0)},
	"ninth_sun": {"name": "Ring of the Ninth Sun", "base": "ring", "lvl": 12, "stats": [["fire", 15], ["str", 10], ["dex", 10], ["mf", 20], ["life", 20]],
		"metal": Color(0.95, 0.75, 0.3), "trim": Color(1.0, 0.85, 0.4), "glow": Color(1.0, 0.7, 0.2), "gem": Color(1.0, 0.6, 0.1)},
	"cinderbrand": {"name": "Cinderbrand, the King's Edge", "base": "flamberge", "lvl": 18, "boss_only": true,
		"stats": [["ed", 160], ["fire", 30], ["ias", 20], ["ls", 6], ["str", 20], ["life", 60]],
		"metal": Color(0.2, 0.11, 0.08), "trim": Color(1.0, 0.62, 0.22), "glow": Color(1.0, 0.36, 0.05), "gem": Color(1.0, 0.22, 0.02)},
	"mire_heart": {"name": "Heart of the Mire", "base": "amulet", "lvl": 16, "stats": [["vit", 20], ["regen", 6], ["res", 30], ["ls", 4]],
		"metal": Color(0.25, 0.35, 0.2), "trim": Color(0.5, 0.7, 0.3), "glow": Color(0.4, 1.0, 0.3), "gem": Color(0.3, 1.0, 0.4)},
	"dawnbreaker": {"name": "Dawnbreaker", "base": "runeblade", "lvl": 26, "stats": [["ed", 180], ["fire", 30], ["ias", 25], ["ls", 6], ["str", 20]],
		"metal": Color(0.95, 0.92, 0.85), "trim": Color(1.0, 0.8, 0.35), "glow": Color(1.0, 0.85, 0.4), "gem": Color(1.0, 0.95, 0.6)},
	"skullsplitter": {"name": "Skullsplitter", "base": "war_axe", "lvl": 15, "stats": [["ed", 140], ["dmg", 12], ["ls", 5], ["str", 12]],
		"metal": Color(0.3, 0.3, 0.32), "trim": Color(0.85, 0.82, 0.7), "glow": Color(0.9, 0.2, 0.1), "gem": Color(0.9, 0.1, 0.05)},
	"sunwarden": {"name": "Sunwarden Aegis", "base": "aegis", "lvl": 25, "stats": [["edef", 150], ["block", 15], ["res", 35], ["vit", 25]],
		"metal": Color(0.95, 0.8, 0.45), "trim": Color(1.0, 1.0, 0.95), "glow": Color(1.0, 0.85, 0.4), "gem": Color(1.0, 0.9, 0.5)},
}

## Each run is Act I again with stronger monsters and loot (indexed by Game.difficulty).
## Multipliers on Act I: monster life (and armor), the final boss's life, monster damage,
## the flat stats on items they drop (Items.empower) and experience. Tuned with
## tools/balance_sim.gd (see BALANCE.md).
const RUNS := [
	{"name": "Act I", "life": 1.0, "boss_life": 1.0, "dmg": 1.0, "loot": 1.0, "xp": 1.0},
	{"name": "A2", "life": 6.0, "boss_life": 4.0, "dmg": 5.0, "loot": 5.0, "xp": 5.0},
	{"name": "A3", "life": 24.0, "boss_life": 10.0, "dmg": 15.0, "loot": 25.0, "xp": 25.0},
]

const RARITY_COLOR := [Color(0.92, 0.92, 0.92), Color(0.45, 0.55, 1.0), Color(1.0, 0.95, 0.35), Color(0.82, 0.66, 0.38)]
const RARITY_NAME := ["Normal", "Magic", "Rare", "Unique"]

const SKILLS := [
	{"id": "cleave", "cls": "knight", "name": "Holy Slam", "key": "Q", "lvl": 1, "mana": 5, "cd": 0.0, "aim": "point", "range": 6.0, "desc": "Leap at the cursor and bring the sword down in a burst of white light: 160% weapon damage to everything around the blow, knocking them back and stunning them for 1 second."},
	{"id": "nova", "cls": "knight", "name": "Holy Nova", "key": "E", "lvl": 3, "mana": 14, "cd": 2.5, "aim": "self", "desc": "A ring of holy fire bursts outward, burning enemies within 7 metres."},
	{"id": "charge", "cls": "knight", "name": "Charge", "key": "R", "lvl": 6, "mana": 10, "cd": 4.0, "aim": "facing", "range": 9.0, "desc": "Dash the way you face (toward the nearest enemy ahead), smashing through enemies and knocking them back."},
	{"id": "cry", "cls": "knight", "name": "Battle Cry", "key": "F", "lvl": 10, "mana": 20, "cd": 20.0, "aim": "self", "desc": "Rally yourself: +40% damage and +50% defense for 12 seconds. Stuns nearby foes."},
	{"id": "reap", "cls": "wraith", "name": "Soul Reap", "key": "Q", "lvl": 1, "mana": 5, "cd": 0.0, "aim": "facing", "range": 3.5, "desc": "A spectral scythe sweeps in front of you for 150% weapon damage. Each soul it cuts flies back and heals you."},
	{"id": "wail", "cls": "wraith", "name": "Banshee Wail", "key": "E", "lvl": 3, "mana": 14, "cd": 3.0, "aim": "self", "desc": "A scream that tears outward 7 metres: hurls enemies back, freezes them in terror and damages them."},
	{"id": "shade", "cls": "wraith", "name": "Shadow Step", "key": "R", "lvl": 6, "mana": 10, "cd": 4.0, "aim": "point", "desc": "Melt into shadow and re-form at the cursor, striking everything around you. The shade you leave behind implodes."},
	{"id": "host", "cls": "wraith", "name": "Spectral Host", "key": "F", "lvl": 10, "mana": 20, "cd": 18.0, "aim": "self", "desc": "Three spirits circle you for 12 seconds, darting out to strike nearby enemies. +40% damage while they last."},
	{"id": "hellclaw", "cls": "demon", "name": "Hellfire Claw", "key": "Q", "lvl": 1, "mana": 5, "cd": 0.0, "aim": "facing", "range": 3.5, "desc": "Three burning rakes tear across the front for 140% weapon damage plus fire, setting enemies alight."},
	{"id": "summon", "cls": "demon", "name": "Summon Demon", "key": "E", "lvl": 3, "mana": 18, "cd": 1.5, "aim": "self", "desc": "A demon claws its way up out of a burning sigil to fight beside you. Up to 3 at once; a fourth replaces the oldest."},
	{"id": "phase", "cls": "demon", "name": "Underworld Phase", "key": "R", "lvl": 6, "mana": 15, "cd": 12.0, "aim": "self", "desc": "Slip into the Underworld for 6 seconds: monsters cannot see or hurt you and you move faster. When you return, the rift erupts around you."},
	{"id": "pact", "cls": "demon", "name": "Blood Pact", "key": "F", "lvl": 10, "mana": 0, "cd": 20.0, "aim": "self", "desc": "Pay 20% of your life: you and your demons deal +40% damage for 12 seconds, and your demons are healed, faster and fiercer."},
	{"id": "drain", "cls": "warlock", "channel": true, "name": "Drain Life", "key": "Q", "lvl": 1, "mana": 6, "cd": 0.0, "aim": "facing", "range": 11.0, "desc": "Latch a green beam onto an enemy and pull the life out of it. The beam forks to up to 3 enemies near your target and everything it drains heals you. Hold Q to keep draining (costs mana each second)."},
	{"id": "blight", "cls": "warlock", "name": "Blight Bolt", "key": "E", "lvl": 3, "mana": 12, "cd": 1.5, "aim": "facing", "range": 15.0, "desc": "Hurl a howling skull of blight. It bursts where it lands and leaves a plague pool that rots enemies standing in it for 4 seconds."},
	{"id": "shackles", "cls": "warlock", "name": "Soul Shackles", "key": "R", "lvl": 6, "mana": 16, "cd": 8.0, "aim": "self", "desc": "Chains of fel fire snap out to every enemy within 7 metres, damaging them and binding them in place for 2.5 seconds."},
	{"id": "covenant", "cls": "warlock", "name": "Fel Covenant", "key": "F", "lvl": 10, "mana": 20, "cd": 20.0, "aim": "self", "desc": "Seal a pact with what waits beyond: +40% damage for 12 seconds, and Drain Life forks to two more enemies and heals twice as much."},
]

## Playable classes. Base attributes at level 1.
## How long every attack, skill swing and cast takes, as a multiple of its base timing (1.2 = 20% slower).
## Every class uses it, including new ones; a class can set its own "attack_pace" in CLASSES (a special
## character). Weapon speed, increased attack speed and Dexterity still speed attacks up from there.
## Attacks whose rate the swing sets hit that much harder (Hero.pace_mult), so damage per second stays where the balance put it.
const ATTACK_PACE := 1.2

static func attack_pace(cls: String) -> float:
	return float(CLASSES[cls].get("attack_pace", ATTACK_PACE)) if CLASSES.has(cls) else ATTACK_PACE

const CLASSES := {
	"knight": {"name": "Knight", "str": 20, "dex": 15, "vit": 25, "ene": 10,
		"desc": "A crusader in steel. Sword and shield, heavy blows, holy fire and a rallying cry."},
	"wraith": {"name": "Wraith", "str": 15, "dex": 22, "vit": 18, "ene": 28,
		"desc": "A hooded spirit that never touches the ground. Reaps souls to heal, screams enemies into terror, steps through shadow and calls a host of spirits."},
	"demon": {"name": "Demon", "str": 24, "dex": 14, "vit": 24, "ene": 18,
		"desc": "A horned, winged fiend in obsidian plate. Claws with hellfire, summons up to three demons and slips into the Underworld to walk unseen."},
	"warlock": {"name": "Warlock", "str": 14, "dex": 16, "vit": 20, "ene": 30,
		"desc": "A hooded sorcerer bound by a fel pact. Drains the life from foes in a forking green beam, rots them with blight and chains them where they stand."},
}

static func skills_for(cls: String) -> Array:
	var out := []
	for s in SKILLS:
		if s["cls"] == cls:
			out.append(s)
	return out

## Skills every class has, whatever classes are added: the weapon attack (each class's own swing; the
## knight's is the three-swing sword combo) and Block. They live on the mouse buttons by default.
const COMMON_SKILLS := [
	{"id": "attack", "cls": "any", "name": "Attack", "key": "", "lvl": 1, "mana": 0, "cd": 0.0, "aim": "point", "desc": "Strike with your weapon toward the cursor. Hold to keep attacking: the knight chains a forehand cut, a rising backhand and a spinning finisher."},
	{"id": "block", "cls": "any", "name": "Block", "key": "", "lvl": 1, "mana": 0, "cd": 0.0, "aim": "self", "hold": true, "desc": "Hold to raise your guard: 80% less damage from the front. With a shield, arrows and missiles from the front are stopped entirely."},
]

## Every skill a class can bind: its own skills, then the common ones.
static func skills_known(cls: String) -> Array:
	return skills_for(cls) + COMMON_SKILLS

static func skill_def(id: String) -> Dictionary:
	for s in SKILLS:
		if s["id"] == id:
			return s
	for s in COMMON_SKILLS:
		if s["id"] == id:
			return s
	return {}

static func xp_for_level(lvl: int) -> int:
	return int(round(120.0 * pow(float(lvl), 1.75) + 60.0 * lvl))

static func zone_level(act: int, kind: String) -> int:
	var base: int = ACTS[act]["lvl"]
	match kind:
		"wild": return base + 2
		"lair": return base + 5
	return base
