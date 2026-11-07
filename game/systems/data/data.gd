class_name Data
extends RefCounted
## Static game data: the act, monsters, item bases, affixes, uniques, vendors.

## The one act: Act I, its camp (Enter World, zone "town") and its level. Game.cur_act is always 0.
const ACTS := [
	{"name": "The Ashen Moors", "town": "The Forsaken Wilds", "lvl": 1},
]

## The waypoint network: Act I's tab and its stones (only the camp's today). Each waypoint opens once a player
## touches its stone (Game.waypoints_known); the camp's is open as soon as you arrive.
## Adding a waypoint: a point here (a new id; its zone), and in that zone's builder one line,
## `add_waypoint("<id>", Vector3(x, 0, z))` (World.add_waypoint: the stone, its colliders and its own
## arrival spot), so a zone can hold several (see ForestCamp). A new zone also goes in WAYPOINT_ZONES and
## World.build. check_waypoints() reports mistakes (dev builds print them at start).
##   group: its tab group (WAYPOINT_GROUPS) · tab: the numeral on the act's tab (its name is Data.RUNS[run].name) ·
##   art: its banner (Meshy) · points: id (what the stone binds), zone (where it takes you), kind (camp | wild | road |
##   city: its icon), name (optional; else the zone's title)
## The window's tab groups, left to right; a group shows only once it has an entry (group: its id).
const WAYPOINT_GROUPS := [
	{"id": "acts", "name": "Acts"},
	{"id": "ancient", "name": "Ancient Levels"},
	{"id": "pve", "name": "PvE"},
	{"id": "battlegrounds", "name": "Battlegrounds"},
	{"id": "daily", "name": "Dailies"},
]

## Battlegrounds the waypoint window offers (its "Battlegrounds" tab group; shown once this has an entry).
## Each card is a way down from the camp's waypoint with the character playing (Game.waypoint_battleground: a word
## on the stakes, the dais flares, the raid server is joined; the raid ends back on the dais). The raid's numbers
## (round length, when the portals open, how many raiders) come from Battlegrounds' constants, never from here.
##   id · name · kind (its mode, under the name) · art (the Meshy painting on the window's banner, 640x480) · wide
##   (the same painting at 16:9, behind the loading words on the way down) · lines (what the card says of the place)
const WAYPOINT_BATTLEGROUNDS := [
	{"id": "crypt", "name": "The Verdant Reach", "kind": "Extraction raid",
		"art": "res://assets/textures/ui/wp_bg_crypt.png", "wide": "res://assets/textures/ui/wp_bg_crypt_wide.jpg",
		"lines": ["An open forest of monster camps, two bosses in its depths. Clear a camp and its chest offers a skill, a rite or a gem.",
			"Other raiders are hunting there too. Reach an Extraction Portal once they open to keep your hero as a survivor."]},
]

## Activity registration: add/remove entries here, not buttons in the waypoint panel.
## group: pve | daily; route: zone; run, zone, spawn; optional level, enabled,
## starts_at / ends_at (UTC Unix seconds). Scheduled entries disappear outside their window.
static var WAYPOINT_ACTIVITIES: Array = []

static func waypoint_available(entry: Dictionary, now: float) -> bool:
	return bool(entry.get("enabled", true)) and now >= float(entry.get("starts_at", 0)) and (not entry.has("ends_at") or now < float(entry["ends_at"]))

static func waypoint_battleground(id: String) -> Dictionary:
	for b in WAYPOINT_BATTLEGROUNDS:
		if str(b.get("id", "")) == id and waypoint_available(b, Time.get_unix_time_from_system()):
			return b
	return {}

const WAYPOINT_ACTS := [
	{"run": 0, "group": "acts", "tab": "I", "art": "res://assets/textures/ui/wp_act1.png",
		"points": [{"id": "town", "zone": "town", "kind": "camp"}]},
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
const WAYPOINT_ZONES := ["town"]

## Problems in WAYPOINT_ACTS, one line each (empty = all good). Checked at start in dev builds
## (Game) and by game/maps/camp/tests/waypoint_test.gd, so a mistake shows the moment it is made.
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
		if r != 0:
			errs.append(tag + ": Act I (run 0) is the only act")
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
	for b in WAYPOINT_BATTLEGROUNDS:
		var btag := "battleground '%s'" % str(b.get("id", "?"))
		if str(b.get("id", "")) == "" or str(b.get("name", "")) == "":
			errs.append(btag + ": needs an id and a name")
		for key in ["art", "wide"]:
			if b.has(key) and not ResourceLoader.exists(b[key]):
				errs.append(btag + ": %s not found: %s" % [key, str(b[key])])
	return errs

## How each character draws and puts away its weapon (WeaponCarry; the motion itself lives in Anim).
## Keyed by class (or, later, an enemy kind). Any key left out takes WeaponCarry.DEFAULT; a character
## with no entry gets the default draw and a warning. A new character = a new entry (and, for a new
## kind of motion, a new "draw_motion" branch in Anim.pose).
##   motion: "knight" (cross-body draw from the left hip) | "back" (over the right shoulder)
##   store: "hilt" (the body model's sheathed hilt shows; the weapon model hides) | "back" (on the back)
##   draw_time / holster_time: seconds · grab: fraction of the motion where the hand takes it
##   threat_range: metres · disengage: seconds safe before holstering · town: "holster" (always away)
const WEAPON_PROFILES := {
	# the crusader: a heavy, deliberate draw across the body from the scabbard on his left hip
	"knight": {"motion": "knight", "store": "hilt", "draw_time": 0.85, "holster_time": 0.9, "grab": 0.38, "disengage": 4.0},
	# the other classes keep the default over-the-shoulder draw until their new models arrive
	"warlock": {"motion": "back", "store": "back"},
	# the archer's bow goes across his back beside the quiver
	"archer": {"motion": "back", "store": "back"},
	"wraith": {"motion": "back", "store": "back"},
	"demon": {"motion": "back", "store": "back"},
	# the plague doctor's cane rides across his back too (his coat's belt is full of vials)
	"plague": {"motion": "back", "store": "back"},
	# Doug tucks his drumstick in his belt (it's a snack too)
	"doug": {"motion": "back", "store": "back"},
	# the dragons hold nothing (an equipped weapon hangs off a hidden joint): the default motion, out of sight
	"wyrm": {"motion": "back", "store": "back"},
	"serpent": {"motion": "back", "store": "back"},
	"wyvern": {"motion": "back", "store": "back"},
}

## The camp's people by role (ForestCamp, the quest givers).
const VENDORS := {"smith": "Halvar Emberhammer", "armor": "Hedda Ironhand", "alch": "Agnes Grimwood", "gamble": "Tarrow the Dice", "stash": "Stash", "elder": "Captain Roth"}

## look keys: skin, cloth, cloth2, armor, height, bulk, head, eyes, horns, cape, thin, tail, wings, weapon, shield
const ENEMIES := {
	"fallen": {"mesh": "fallen", "name": "Fallen", "rig": "humanoid", "life": 14, "dmg": [2, 5], "speed": 4.2, "range": 1.5, "xp": 9,
		"ai": "melee", "atk": "over", "atk_time": 0.85, "armor": 2, "radius": 0.45, "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.62, 0.12, 0.08), "cloth": Color(0.22, 0.16, 0.1), "height": 0.72, "bulk": 0.9, "head": "horned", "eyes": Color(1.0, 0.8, 0.1), "weapon": "club"}},
	# the three Fallen (FallenBrain; Anim's "gait"s and styles): one
	# faction, three ways of fighting. Usable in any act: add the id to that act's "foes".
	"fallen_skirmisher": {"mesh": "fallen_skirmisher", "name": "Fallen Skirmisher", "rig": "humanoid", "life": 18, "dmg": [4, 8], "speed": 4.6, "range": 1.5, "xp": 12,
		"ai": "skirmisher", "atk": "skirm_lunge", "atk_time": 0.9, "armor": 2, "radius": 0.42, "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.6, 0.14, 0.08), "cloth": Color(0.22, 0.16, 0.1), "height": 0.69, "bulk": 0.9, "head": "horned", "eyes": Color(1.0, 0.8, 0.1), "weapon": "sickle", "gait": "skirm", "stride": 1.3}},
	"fallen_reaver": {"mesh": "fallen_reaver", "name": "Fallen Reaver", "rig": "humanoid", "life": 45, "dmg": [8, 14], "speed": 3.2, "range": 2.2, "xp": 22,
		"ai": "reaver", "atk": "reaver_cleave", "atk_time": 1.6, "armor": 6, "radius": 0.6, "turn": 0.09, "blood": Color(0.45, 0.02, 0.02),
		"look": {"skin": Color(0.35, 0.1, 0.08), "cloth": Color(0.15, 0.12, 0.1), "height": 0.97, "bulk": 1.3, "head": "horned", "eyes": Color(1.0, 0.5, 0.1), "weapon": "cleaver", "gait": "reaver", "stride": 0.8}},
	"fallen_stalker": {"mesh": "fallen_stalker", "name": "Fallen Stalker", "rig": "humanoid", "life": 20, "dmg": [4, 8], "speed": 4.4, "range": 1.6, "xp": 16,
		"ai": "stalker", "atk": "stalk_hook", "atk_time": 1.1, "armor": 3, "radius": 0.42, "blood": Color(0.4, 0.03, 0.05),
		"look": {"skin": Color(0.4, 0.2, 0.18), "cloth": Color(0.18, 0.14, 0.12), "height": 0.94, "bulk": 0.8, "head": "horned", "eyes": Color(0.9, 1.0, 0.4), "gait": "stalk", "stride": 0.95}},
	# the archer's Spirit Beast as a monster (JJ's dire forest wolf, the Feral's pack AI): not placed anywhere yet
	"spirit_beast": {"mesh": "wolf", "name": "Spirit Wolf", "rig": "crawler", "life": 34, "dmg": [5, 9], "speed": 5.2, "range": 1.9, "xp": 20,
		"ai": "feral", "atk": "feral_swipe", "atk_time": 1.0, "armor": 4, "radius": 0.7, "aggro": 13.0, "blood": Color(0.55, 0.95, 0.6),
		"look": {"skin": Color(0.55, 0.85, 0.6), "height": 1.2}},
	"zombie": {"mesh": "zombie", "faction": "undead", "name": "Zombie", "rig": "humanoid", "life": 32, "dmg": [3, 7], "speed": 1.9, "range": 1.6, "xp": 13,
		"ai": "melee", "atk": "claw", "atk_time": 1.25, "armor": 4, "radius": 0.5, "blood": Color(0.25, 0.3, 0.05),
		"look": {"skin": Color(0.42, 0.48, 0.36), "cloth": Color(0.25, 0.23, 0.2), "cloth2": Color(0.18, 0.16, 0.14), "height": 1.0, "bulk": 1.1, "head": "human", "hair": Color(0.15, 0.15, 0.12), "eyes": Color(0.6, 1.0, 0.3)}},
	# the Feral (feral.gd): packs cling to oak trunks deep in the Act I forest and drop on you
	"feral": {"mesh": "feral", "name": "Feral", "rig": "humanoid", "life": 15, "dmg": [2, 5], "speed": 4.2, "range": 1.4, "xp": 12,
		"ai": "feral", "atk": "feral_swipe", "atk_time": 0.8, "armor": 1, "radius": 0.5, "aggro": 14.0, "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.66, 0.6, 0.55), "cloth": Color(0.25, 0.2, 0.15), "height": 0.72, "bulk": 0.8, "head": "human", "hair": Color(0.08, 0.07, 0.06), "eyes": Color(1.0, 0.7, 0.3)}},
	# the Hollow Sloths (game/monsters/hollow_sloth/): three elemental giants, best avoided; each fights with
	# its element ("element") and drops its own material ("drop"). "variant" picks its model.
	"sloth_fire": {"mesh": "sloth", "variant": "fire", "element": "fire", "drop": "cinderheart", "name": "Cinderhide, the Burning Sloth", "rig": "crawler",
		"life": 320, "dmg": [8, 15], "speed": 2.2, "range": 2.6, "xp": 160, "ai": "sloth", "atk": "sloth_sweep", "atk_time": 1.35, "armor": 10, "radius": 1.3,
		"aggro": 15.0, "trophy": true, "blood": Color(0.35, 0.08, 0.02), "look": {"skin": Color(0.16, 0.12, 0.1), "height": 1.7, "eyes": Color(1.0, 0.5, 0.1)}},
	"sloth_ice": {"mesh": "sloth", "variant": "ice", "element": "cold", "drop": "everfrost", "name": "Rimeclaw, the Frozen Sloth", "rig": "crawler",
		"life": 320, "dmg": [8, 15], "speed": 2.2, "range": 2.6, "xp": 160, "ai": "sloth", "atk": "sloth_sweep", "atk_time": 1.35, "armor": 10, "radius": 1.3,
		"aggro": 15.0, "trophy": true, "blood": Color(0.3, 0.06, 0.04), "look": {"skin": Color(0.78, 0.8, 0.82), "height": 1.7, "eyes": Color(0.45, 0.85, 1.0)}},
	"sloth_storm": {"mesh": "sloth", "variant": "storm", "element": "lightning", "drop": "stormglass", "name": "Thundermaw, the Storm Sloth", "rig": "crawler",
		"life": 320, "dmg": [8, 15], "speed": 2.2, "range": 2.6, "xp": 160, "ai": "sloth", "atk": "sloth_sweep", "atk_time": 1.35, "armor": 10, "radius": 1.3,
		"aggro": 15.0, "trophy": true, "blood": Color(0.3, 0.06, 0.04), "look": {"skin": Color(0.25, 0.26, 0.33), "height": 1.7, "eyes": Color(0.75, 0.45, 1.0)}},
	# the bandits (game/monsters/bandit/), and the beasts, gladiators and champion of the old arena games
	# (game/monsters/gladiator/, champion/; the lion: lion.gd). "mesh" picks the Meshy model when it's there.
	"bandit": {"mesh": "bandit", "name": "Road Bandit", "rig": "humanoid", "life": 22, "dmg": [3, 7], "speed": 4.4, "range": 1.6, "xp": 13,
		"ai": "melee", "atk": "side", "atk_time": 0.8, "armor": 3, "radius": 0.45, "faction": "bandit", "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.62, 0.46, 0.34), "cloth": Color(0.3, 0.24, 0.16), "cloth2": Color(0.22, 0.25, 0.14), "height": 1.0, "bulk": 0.95, "head": "human", "hair": Color(0.12, 0.09, 0.06), "weapon": "scimitar"}},
	# the Verdant Reach's treant (Meshy, concept exports/bg_forest/treant_concept.png; rig_monster.py with crotch/sh_z
	# hints for its crown): the mushroom woodland's slow, heavy guardian
	"treant": {"mesh": "treant", "name": "Rootbound Treant", "rig": "humanoid", "life": 70, "dmg": [7, 12], "speed": 2.7, "range": 2.3, "xp": 34,
		"ai": "melee", "atk": "slam", "atk_time": 1.4, "armor": 10, "radius": 0.85, "blood": Color(0.32, 0.5, 0.2),
		"look": {"skin": Color(0.36, 0.27, 0.18), "cloth": Color(0.25, 0.35, 0.15), "cloth2": Color(0.2, 0.3, 0.12), "height": 1.55, "bulk": 1.3, "head": "human", "hair": Color(0.2, 0.4, 0.15), "weapon": ""}},
	# the Verdant Reach's dark elves (Meshy, concept exports/bg_forest/dark_elf_concept.png; rig_monster.py): the
	# encampments' blades and bows, a little quicker and harder than bandits
	"dark_elf": {"mesh": "dark_elf", "name": "Shadeleaf Reaver", "rig": "humanoid", "life": 26, "dmg": [4, 8], "speed": 4.6, "range": 1.7, "xp": 15,
		"ai": "melee", "atk": "side", "atk_time": 0.75, "armor": 4, "radius": 0.45, "faction": "elf", "blood": Color(0.42, 0.05, 0.25),
		"look": {"skin": Color(0.45, 0.45, 0.5), "cloth": Color(0.16, 0.13, 0.2), "cloth2": Color(0.3, 0.16, 0.36), "height": 1.0, "bulk": 0.9, "head": "human", "hair": Color(0.85, 0.85, 0.88), "weapon": "scimitar"}},
	"dark_elf_archer": {"mesh": "dark_elf", "name": "Shadeleaf Sniper", "rig": "humanoid", "life": 18, "dmg": [4, 7], "speed": 4.0, "range": 13.0, "xp": 14,
		"ai": "ranged", "atk": "bow", "atk_time": 1.1, "armor": 2, "radius": 0.45, "proj": "arrow", "faction": "elf", "blood": Color(0.42, 0.05, 0.25),
		"look": {"skin": Color(0.45, 0.45, 0.5), "cloth": Color(0.16, 0.13, 0.2), "cloth2": Color(0.3, 0.16, 0.36), "height": 1.0, "bulk": 0.88, "head": "human", "hair": Color(0.85, 0.85, 0.88), "weapon": "bow"}},
	"bandit_archer": {"mesh": "bandit", "name": "Bandit Bowman", "rig": "humanoid", "life": 16, "dmg": [3, 6], "speed": 3.6, "range": 12.0, "xp": 12,
		"ai": "ranged", "atk": "bow", "atk_time": 1.2, "armor": 2, "radius": 0.45, "proj": "arrow", "faction": "bandit", "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.6, 0.45, 0.33), "cloth": Color(0.26, 0.22, 0.15), "cloth2": Color(0.3, 0.2, 0.12), "height": 0.98, "bulk": 0.9, "head": "human", "hair": Color(0.15, 0.1, 0.07), "weapon": "bow"}},
	# the Forsaken Bear (bear.gd): a lone wanderer off the road; no faction, so it fights anything in its way
	"bear": {"mesh": "bear", "name": "Forsaken Bear", "rig": "crawler", "life": 130, "dmg": [9, 16], "speed": 3.0, "range": 2.4, "xp": 60,
		"ai": "bear", "atk": "bear_maul", "atk_time": 1.5, "armor": 8, "radius": 1.0, "aggro": 12.0, "blood": Color(0.35, 0.05, 0.03),
		"look": {"skin": Color(0.16, 0.15, 0.14), "shell": Color(0.1, 0.1, 0.09), "legs": 4, "size": 1.6, "eyes": Color(0.45, 1.0, 0.4)}},
	"troll_shaman": {"mesh": "troll_shaman", "faction": "troll", "name": "Troll Beast-Tamer", "rig": "humanoid", "life": 70, "dmg": [7, 12], "speed": 3.4, "range": 10.0, "xp": 48,
		"ai": "ranged", "atk": "cast", "atk_time": 1.3, "armor": 5, "radius": 0.5, "proj": "poison", "blood": Color(0.25, 0.4, 0.3),
		"look": {"height": 2.3, "eyes": Color(1.0, 0.6, 0.15)}},
	# the Battlegrounds' bosses (Blaine's overhaul): Meshy, rigged by rig_monster.py;
	# their fights (abilities, arenas, the hermit's chest) are the overhaul's to build on these entries
	"ice_troll": {"mesh": "ice_troll", "class_unique": true, "name": "Hrimgar the Frostbound", "rig": "humanoid", "life": 1400, "dmg": [24, 38], "speed": 3.2, "range": 3.0, "xp": 1400,
		"ai": "melee", "atk": "slam", "atk_time": 1.7, "armor": 22, "radius": 1.3, "boss": true, "aggro": 18.0, "blood": Color(0.55, 0.8, 1.0),
		"look": {"height": 1.9, "eyes": Color(0.6, 0.95, 1.0)}},          # x a man's 1.8 m: 3.4 m
	"spore_shroom": {"prop": "fungus", "name": "Poison Mushroom", "rig": "crawler", "life": 80, "dmg": [5, 8], "speed": 0.0, "range": 3.0, "xp": 12,
		"ai": "melee", "atk": "slam", "atk_time": 1.0, "armor": 0, "radius": 0.7, "blood": Color(0.35, 0.6, 0.2),
		"look": {"height": 1.2, "prop_scale": 1.3, "eyes": Color(0.5, 1.0, 0.4)}},
	"hermit": {"mesh": "hermit", "class_unique": true, "name": "Old Mossbeard", "rig": "humanoid", "life": 900, "dmg": [14, 22], "speed": 3.0, "range": 9.0, "xp": 1100,
		"ai": "ranged", "atk": "cast", "atk_time": 1.4, "armor": 10, "radius": 0.6, "boss": true, "aggro": 14.0, "proj": "poison", "blood": Color(0.35, 0.55, 0.2),
		"look": {"height": 0.82, "eyes": Color(0.5, 1.0, 0.4)}},         # 1.5 m, hunched
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
	# King Grubb's goblins: they guard him, and fight the dead on sight ("faction")
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

	"mummy": {"name": "Embalmed", "rig": "humanoid", "life": 48, "dmg": [6, 12], "speed": 1.8, "range": 1.7, "xp": 24,
		"ai": "melee", "atk": "claw", "atk_time": 1.3, "armor": 10, "radius": 0.5, "blood": Color(0.6, 0.55, 0.4),
		"look": {"skin": Color(0.72, 0.65, 0.5), "cloth": Color(0.68, 0.6, 0.45), "height": 1.05, "bulk": 1.0, "head": "mummy", "eyes": Color(1.0, 0.6, 0.1)}},

	"fetish": {"name": "Mire Fetish", "rig": "humanoid", "life": 26, "dmg": [6, 11], "speed": 4.6, "range": 10.0, "xp": 28,
		"ai": "ranged", "atk": "thrust", "atk_time": 1.0, "armor": 10, "radius": 0.4, "proj": "dart", "blood": Color(0.5, 0.02, 0.02),
		"look": {"skin": Color(0.35, 0.22, 0.12), "cloth": Color(0.3, 0.45, 0.15), "height": 0.62, "bulk": 0.85, "head": "mask", "eyes": Color(1.0, 0.9, 0.2), "weapon": "blowgun"}},
	"spider": {"name": "Bog Spider", "rig": "crawler", "life": 44, "dmg": [8, 14], "speed": 5.3, "range": 1.7, "xp": 32,
		"ai": "melee", "atk": "bite", "atk_time": 0.85, "armor": 12, "radius": 0.8, "blood": Color(0.3, 0.6, 0.1),
		"look": {"skin": Color(0.12, 0.1, 0.08), "shell": Color(0.2, 0.15, 0.08), "legs": 8, "size": 1.1, "eyes": Color(1.0, 0.1, 0.1), "stripe": Color(0.7, 0.4, 0.05)}},

	"imp": {"name": "Cinder Imp", "rig": "humanoid", "life": 46, "dmg": [12, 19], "speed": 5.2, "range": 1.5, "xp": 46,
		"ai": "melee", "atk": "claw", "atk_time": 0.75, "armor": 20, "radius": 0.45, "blood": Color(0.9, 0.3, 0.05),
		"look": {"skin": Color(0.55, 0.08, 0.04), "cloth": Color(0.12, 0.05, 0.03), "height": 0.8, "bulk": 0.85, "head": "horned", "eyes": Color(1.0, 0.7, 0.1), "wings": true, "tail": true}},
}

## Champion name prefixes for elite packs.
const CHAMP_PREFIX := ["Gloom", "Rot", "Blood", "Storm", "Grim", "Bane", "Cinder", "Vile", "Doom", "Ash"]
const CHAMP_SUFFIX := ["maw", "fang", "hide", "brand", "skull", "spine", "heart", "claw"]

## Item bases. slot: weapon, shield, helm, armor, gloves, boots, belt, ring, amulet, potion, gold, material
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
	# the Veilmother's Locket's raid potion (Hero.drink "invis": unseen for that long; breaks on a blow, given or taken)
	"shadow_phial": {"name": "Shadow Phial", "slot": "potion", "kind": "potion", "lvl": 1, "price": 0, "invis": 6.0, "color": Color(0.4, 0.32, 0.62)},
	"rejuv": {"name": "Rejuvenation Potion", "slot": "potion", "kind": "potion", "lvl": 1, "price": 60, "rejuv": 0.4, "color": Color(0.6, 0.1, 0.9)},
	# a run's consumables (camp chests, RunTalents.CONSUMABLES): elixirs are timed buffs, flasks are thrown at the pointer
	"elixir_fury": {"icon": "res://assets/textures/items/c_elixir_fury.png", "name": "Elixir of Fury", "slot": "potion", "kind": "potion", "lvl": 1, "price": 40, "color": Color(0.95, 0.25, 0.1),
		"buff": {"dmg": 30, "ias": 10}, "secs": 20.0, "desc": "+30% damage and +10% attack speed for 20 seconds."},
	"draught_iron": {"icon": "res://assets/textures/items/c_draught_iron.png", "name": "Ironbark Draught", "slot": "potion", "kind": "potion", "lvl": 1, "price": 40, "color": Color(0.55, 0.45, 0.3),
		"buff": {"armor_pct": 60, "res": 15}, "secs": 20.0, "desc": "+60% defense and +15% resistances for 20 seconds."},
	"tonic_swift": {"icon": "res://assets/textures/items/c_tonic_swift.png", "name": "Swiftness Tonic", "slot": "potion", "kind": "potion", "lvl": 1, "price": 30, "color": Color(0.3, 0.95, 0.85),
		"buff": {"frw": 25, "ias": 12}, "secs": 15.0, "desc": "+25% run speed and +12% attack speed for 15 seconds."},
	"salve_troll": {"icon": "res://assets/textures/items/c_salve_troll.png", "name": "Troll Salve", "slot": "potion", "kind": "potion", "lvl": 1, "price": 40, "color": Color(0.35, 0.7, 0.2),
		"buff": {"regen": 0.0}, "regen_pct": 6.0, "secs": 10.0, "desc": "Regenerate 60% of your life over 10 seconds."},
	"elixir_wrath": {"icon": "res://assets/textures/items/c_elixir_wrath.png", "name": "Elixir of Wrath", "slot": "potion", "kind": "potion", "lvl": 1, "price": 60, "color": Color(1.0, 0.75, 0.15),
		"buff": {"crit": 25, "crit_dmg": 50}, "secs": 15.0, "desc": "+25% critical chance and +50% critical damage for 15 seconds."},
	"flask_fire": {"icon": "res://assets/textures/items/c_flask_fire.png", "name": "Fire Flask", "slot": "potion", "kind": "potion", "lvl": 1, "price": 40, "color": Color(1.0, 0.45, 0.1),
		"bomb": 0, "bomb_pct": 260, "bomb_r": 4.0, "desc": "Thrown at the pointer: 260% weapon damage within 4 m, setting everything alight."},
	"flask_frost": {"icon": "res://assets/textures/items/c_flask_frost.png", "name": "Frost Flask", "slot": "potion", "kind": "potion", "lvl": 1, "price": 40, "color": Color(0.55, 0.85, 1.0),
		"bomb": 1, "bomb_pct": 160, "bomb_r": 4.5, "desc": "Thrown at the pointer: 160% weapon damage within 4.5 m, freezing them for 2 seconds."},
	"flask_storm": {"icon": "res://assets/textures/items/c_flask_storm.png", "name": "Thunder Flask", "slot": "potion", "kind": "potion", "lvl": 1, "price": 40, "color": Color(0.6, 0.65, 1.0),
		"bomb": 2, "bomb_pct": 200, "bomb_r": 5.0, "desc": "Thrown at the pointer: lightning strikes everything within 5 m for 200% weapon damage."},
	"scroll_ward": {"icon": "res://assets/textures/items/c_scroll_ward.png", "name": "Scroll of Warding", "slot": "potion", "kind": "potion", "lvl": 1, "price": 50, "color": Color(0.85, 0.8, 1.0),
		"ward_pct": 40, "desc": "For 20 seconds, a ward soaks blows worth 40% of your life."},
	"tome_insight": {"icon": "res://assets/textures/items/c_tome_insight.png", "name": "Tome of Insight", "slot": "potion", "kind": "potion", "lvl": 1, "price": 80, "color": Color(0.95, 0.85, 0.5),
		"xp_level": 0.6, "desc": "Read it: 60% of a level's experience."},
	"gold": {"name": "Gold", "slot": "gold", "kind": "gold", "lvl": 1, "price": 0},
	# the plague doctor's cane ("cls": only he carries it; Plague.cane_model draws it)
"roast_drumstick": {"name": "Roast Drumstick", "slot": "weapon", "kind": "club", "cls": "doug", "dmg": [3, 7], "speed": 1.2, "lvl": 1, "price": 30, "shape": {"len": 0.55, "w": 0.12}},
"physician_cane": {"name": "Physician's Cane", "slot": "weapon", "kind": "cane", "cls": "plague", "dmg": [3, 7], "speed": 1.1, "lvl": 1, "price": 35},
"crow_cane": {"name": "Crow-Skull Cane", "slot": "weapon", "kind": "cane", "cls": "plague", "dmg": [8, 16], "speed": 1.1, "lvl": 12, "price": 210},
# bows: the archer's weapons ("cls": only he can draw them)
	"short_bow": {"name": "Short Bow", "slot": "weapon", "kind": "bow", "cls": "archer", "dmg": [2, 6], "speed": 1.15, "lvl": 1, "price": 30},
	"hunting_bow": {"name": "Hunting Bow", "slot": "weapon", "kind": "bow", "cls": "archer", "dmg": [4, 10], "speed": 1.1, "lvl": 5, "price": 85},
	"long_bow": {"name": "Long Bow", "slot": "weapon", "kind": "longbow", "cls": "archer", "dmg": [7, 16], "speed": 1.0, "lvl": 11, "price": 170},
	"war_bow": {"name": "War Bow", "slot": "weapon", "kind": "longbow", "cls": "archer", "dmg": [12, 25], "speed": 0.95, "lvl": 19, "price": 330},
	"grave_bow": {"name": "Gravewood Bow", "slot": "weapon", "kind": "longbow", "cls": "archer", "dmg": [18, 34], "speed": 1.0, "lvl": 26, "price": 600},
	# materials: one space in the inventory, kept for crafting; each Hollow Sloth drops its own (sloth.gd)
	"cinderheart": {"icon": "res://assets/textures/items/cinderheart.png", "model": "res://assets/models/items/cinderheart.glb", "name": "Cinderheart Ember", "slot": "material", "kind": "ember", "lvl": 1, "price": 400, "color": Color(1.0, 0.45, 0.08),
		"lore": "Still burning, torn from the chest of Cinderhide"},
	"everfrost": {"icon": "res://assets/textures/items/everfrost.png", "model": "res://assets/models/items/everfrost.glb", "name": "Everfrost Talon", "slot": "material", "kind": "talon", "lvl": 1, "price": 400, "color": Color(0.45, 0.85, 1.0),
		"lore": "A claw of Rimeclaw's that never thaws"},
	"stormglass": {"icon": "res://assets/textures/items/stormglass.png", "model": "res://assets/models/items/stormglass.glb", "name": "Stormglass Eye", "slot": "material", "kind": "orb", "lvl": 1, "price": 400, "color": Color(0.72, 0.45, 1.0),
		"lore": "Thundermaw's eye, a storm still raging inside"},
	# resources (Harvest, Furnace): stacked in one inventory cell up to "stack", never worn; "fuel" is what the
	# furnace reads (heat it adds per second while burning, how long one burns, the hottest it can drive the fire)
	"oak_log": {"name": "Oak Log", "slot": "resource", "kind": "log", "lvl": 1, "price": 4, "stack": 50, "color": Color(0.55, 0.38, 0.22),
		"bark": Color(0.24, 0.18, 0.12), "heart": Color(0.78, 0.6, 0.4), "fuel": {"heat": 62.0, "burn": 40.0, "max_temp": 1240.0, "name": "steady"},
		"lore": "Dense moor oak. Burns long and even."},
	"pine_log": {"name": "Pine Log", "slot": "resource", "kind": "log", "lvl": 1, "price": 3, "stack": 50, "color": Color(0.72, 0.56, 0.34),
		"bark": Color(0.3, 0.2, 0.13), "heart": Color(0.9, 0.76, 0.52), "fuel": {"heat": 105.0, "burn": 16.0, "max_temp": 1040.0, "name": "fast and hot"},
		"lore": "Resinous pine. Flares quickly and is gone."},
	"heartwood": {"name": "Ashen Heartwood", "slot": "resource", "kind": "log", "lvl": 1, "price": 40, "stack": 10, "color": Color(1.0, 0.42, 0.12),
		"bark": Color(0.06, 0.05, 0.05), "heart": Color(0.95, 0.35, 0.08), "glow": true, "fuel": {"heat": 120.0, "burn": 50.0, "max_temp": 1400.0, "name": "searing"},
		"lore": "Wood that smouldered for an age inside a living tree. Only it burns white."},
	# tools: carried in the inventory, never equipped; the woodsman's axe lets anyone chop trees (combat axes do too)
	"woodsman_axe": {"name": "Woodsman's Axe", "slot": "tool", "kind": "axe", "lvl": 1, "price": 25, "chop": 1.0, "shape": {"haft": 0.62, "head": 0.17},
		"lore": "A plain felling axe. Every hero in the Wilds carries one."},
}

## How many strikes' worth each combat axe is when used to chop (a woodsman's axe is 1.0; Harvest.chop_power).
const CHOP_POWER := {"hand_axe": 1.1, "war_axe": 1.35, "executioner": 1.65}

## Chopping, per class (like WEAPON_PROFILES): how far from the trunk the hero stands, the swing's length in seconds,
## the axe's size in the hand. A class with no entry gets DEFAULT_CHOP and the procedural "chop" pose (Anim), so a
## new class chops on day one.
const DEFAULT_CHOP := {"stand": 1.05, "swing": 1.05, "axe_scale": 1.0}
const CHOP_PROFILES := {
	"knight": {"stand": 1.1, "swing": 1.05},
	"archer": {"stand": 1.05, "swing": 1.0},
	"plague": {"stand": 1.05, "swing": 1.1},
	"demon": {"stand": 1.35, "swing": 1.25, "axe_scale": 1.35},
	"wraith": {"stand": 1.15, "swing": 1.0, "axe_scale": 1.0, "spectral": true},
	"warlock": {"stand": 0.85, "swing": 0.9, "axe_scale": 0.75},
}

static func chop_profile(cls: String) -> Dictionary:
	return DEFAULT_CHOP.merged(CHOP_PROFILES.get(cls, {}), true)

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
	# utility (the items rework): at most one per item (Items.generate), capped across all gear (GEAR_CAP)
	["stam", "of the Fox", 5, 8, 0.1],
	["cdr", "of Recall", 2, 4, 0.1],
	["pot", "of the Physician", 10, 15, 0.25],
	["ten", "of Iron Will", 8, 12, 0.3],
]

const STAT_LABEL := {
	"ed": "+%d%% Enhanced Damage", "dmg": "+%d Damage", "fire": "Adds %d Fire Damage", "str": "+%d to Strength",
	"dex": "+%d to Dexterity", "vit": "+%d to Vitality", "life": "+%d to Life", "mana": "+%d to Mana",
	"ias": "+%d%% Attack Speed", "ls": "%d%% Life Stolen per Hit", "def": "+%d Defense", "edef": "+%d%% Enhanced Defense",
	"res": "All Resistances +%d", "block": "+%d%% Chance to Block", "gf": "%d%% Extra Gold", "mf": "%d%% Better Chance of Magic Items",
	"regen": "Replenish %d Life per second", "frw": "+%d%% Faster Run/Walk",
	"stam": "-%d%% Dodge Stamina Cost", "cdr": "-%d%% Skill Cooldowns", "pot": "+%d%% Potion Healing",
	"ten": "-%d%% Duration of Stuns and Slows",
	"roll": "A free dodge roll (no stamina) every %d seconds",
	"ward": "A ward of %d%% of your life that soaks blows, back out of combat",
	"burn": "Your blows set foes burning (%d%% of the blow a second)",
	"chill": "Your blows chill foes, slowing them %d%%",
	"kill_heal": "Heal %d%% of your life on each kill",
	"dash": "+%d%% speed for 2 seconds after a dodge roll",
	"phial": "Begin each raid with %d Shadow Phial: unseen for 6 seconds",
}

## Which affixes can roll on which slot class.
const AFFIX_SLOTS := {
	"weapon": ["ed", "dmg", "fire", "str", "dex", "ias", "ls", "life", "mana", "mf"],
	"shield": ["def", "edef", "res", "block", "vit", "life", "str"],
	"helm": ["def", "edef", "res", "life", "mana", "mf", "regen", "vit", "ten"],
	"armor": ["def", "edef", "res", "life", "vit", "str", "regen", "ten"],
	"gloves": ["def", "ias", "dex", "str", "ls", "gf", "cdr"],
	"boots": ["def", "frw", "res", "dex", "gf", "mf", "stam", "ten"],
	"belt": ["def", "life", "vit", "str", "gf", "regen", "pot", "stam"],
	"ring": ["str", "dex", "vit", "life", "mana", "ls", "res", "mf", "fire", "dmg", "cdr", "stam"],
	"amulet": ["str", "dex", "vit", "life", "mana", "res", "mf", "gf", "fire", "ias", "cdr", "ten", "pot"],
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
	# the class uniques (Blaine's progression overhaul): level 20, only the bosses of the Battlegrounds and the golden
	# chest give them (boss_only), each with one of the raid's item effects (a free roll or a ward: Hero.pvp_roll_s,
	# Hero.ward) and small stats; one class each ("cls": only that class may wear it)
	"oathkeeper": {"name": "Oathkeeper's Plate", "base": "plate_mail", "lvl": 20, "cls": "knight", "boss_only": true, "stats": [["ward", 15], ["vit", 10], ["res", 10]],
		"metal": Color(0.8, 0.8, 0.85), "trim": Color(1.0, 0.85, 0.4), "glow": Color(1.0, 0.9, 0.5), "gem": Color(0.9, 0.1, 0.1)},
	"ninth_bell": {"name": "Shroud of the Ninth Bell", "base": "amulet", "lvl": 20, "cls": "wraith", "boss_only": true, "stats": [["roll", 6], ["dex", 10], ["mana", 20]],
		"metal": Color(0.3, 0.35, 0.45), "trim": Color(0.6, 0.9, 1.0), "glow": Color(0.5, 0.9, 1.0), "gem": Color(0.5, 0.9, 1.0)},
	"brimfire": {"name": "Brimfire Girdle", "base": "war_belt", "lvl": 20, "cls": "demon", "boss_only": true, "stats": [["ward", 12], ["str", 12], ["life", 20]],
		"metal": Color(0.2, 0.08, 0.05), "trim": Color(1.0, 0.45, 0.1), "glow": Color(1.0, 0.35, 0.05), "gem": Color(1.0, 0.25, 0.0)},
	"covenant_signet": {"name": "Signet of the Covenant", "base": "ring", "lvl": 20, "cls": "warlock", "boss_only": true, "stats": [["roll", 6], ["mana", 25], ["vit", 6]],
		"metal": Color(0.3, 0.2, 0.4), "trim": Color(0.5, 1.0, 0.4), "glow": Color(0.4, 1.0, 0.3), "gem": Color(0.5, 1.0, 0.3)},
	"windrunner": {"name": "Windrunner Treads", "base": "greaves", "lvl": 20, "cls": "archer", "boss_only": true, "stats": [["roll", 6], ["frw", 5], ["dex", 8]],
		"metal": Color(0.3, 0.35, 0.25), "trim": Color(0.7, 0.9, 0.5), "glow": Color(0.6, 1.0, 0.5), "gem": Color(0.6, 1.0, 0.5)},
	"plaguewarden": {"name": "Plaguewarden's Cowl", "base": "great_helm", "lvl": 20, "cls": "plague", "boss_only": true, "stats": [["ward", 12], ["res", 10], ["ene", 8]],
		"metal": Color(0.15, 0.15, 0.12), "trim": Color(0.75, 0.6, 0.3), "glow": Color(0.5, 1.0, 0.3), "gem": Color(0.5, 1.0, 0.3)},
	"lucky_nose": {"name": "The Lucky Nose", "base": "amulet", "lvl": 20, "cls": "doug", "boss_only": true, "stats": [["roll", 6], ["life", 25], ["str", 6]],
		"metal": Color(0.9, 0.75, 0.3), "trim": Color(1.0, 0.85, 0.2), "glow": Color(1.0, 0.2, 0.2), "gem": Color(1.0, 0.1, 0.1)},
	# Blaine's "start each battleground with a potion that grants invisibility" (evaluated: 20 s outlasts most duels,
	# so 6): Hrimgar's and Mossbeard's, level 20
	"veil_locket": {"name": "Veilmother's Locket", "base": "amulet", "lvl": 20, "boss_only": true, "stats": [["phial", 1], ["dex", 8], ["res", 10]],
		"metal": Color(0.25, 0.22, 0.32), "trim": Color(0.7, 0.62, 0.9), "glow": Color(0.6, 0.5, 1.0), "gem": Color(0.55, 0.4, 1.0)},
	"emberfang": {"name": "Emberfang", "base": "falchion", "lvl": 6, "stats": [["burn", 25], ["ed", 80], ["fire", 8], ["ias", 15], ["ls", 3]],
		"metal": Color(0.25, 0.08, 0.04), "trim": Color(0.95, 0.55, 0.15), "glow": Color(1.0, 0.4, 0.05), "gem": Color(1.0, 0.3, 0.0)},
	"wardens_wall": {"name": "The Warden's Wall", "base": "kite_shield", "lvl": 7, "stats": [["ten", 20], ["edef", 90], ["block", 12], ["res", 15], ["life", 25]],
		"metal": Color(0.55, 0.57, 0.62), "trim": Color(0.25, 0.45, 0.85), "glow": Color(0.3, 0.6, 1.0), "gem": Color(0.3, 0.6, 1.0)},
	"ashen_king": {"name": "Crown of the Ashen King", "base": "crown", "lvl": 24, "stats": [["roll", 8], ["edef", 120], ["life", 60], ["res", 25], ["mf", 40]],
		"metal": Color(0.2, 0.2, 0.22), "trim": Color(0.9, 0.9, 0.95), "glow": Color(0.8, 0.85, 1.0), "gem": Color(0.9, 0.1, 0.2)},
	"bloodweave": {"name": "Bloodweave Mail", "base": "chain_mail", "lvl": 10, "stats": [["kill_heal", 4], ["edef", 100], ["ls", 5], ["str", 15], ["life", 40]],
		"metal": Color(0.45, 0.08, 0.08), "trim": Color(0.15, 0.15, 0.15), "glow": Color(1.0, 0.05, 0.1), "gem": Color(1.0, 0.0, 0.1)},
	"stormstride": {"name": "Stormstride", "base": "greaves", "lvl": 14, "stats": [["dash", 25], ["frw", 30], ["dex", 15], ["res", 20], ["edef", 80]],
		"metal": Color(0.35, 0.4, 0.55), "trim": Color(0.6, 0.85, 1.0), "glow": Color(0.5, 0.8, 1.0), "gem": Color(0.5, 0.8, 1.0)},
	"ninth_sun": {"name": "Ring of the Ninth Sun", "base": "ring", "lvl": 12, "stats": [["burn", 15], ["fire", 15], ["str", 10], ["dex", 10], ["mf", 20], ["life", 20]],
		"metal": Color(0.95, 0.75, 0.3), "trim": Color(1.0, 0.85, 0.4), "glow": Color(1.0, 0.7, 0.2), "gem": Color(1.0, 0.6, 0.1)},
	"cinderbrand": {"name": "Cinderbrand, the King's Edge", "base": "flamberge", "lvl": 18, "boss_only": true,
		"stats": [["burn", 40], ["ed", 160], ["fire", 30], ["ias", 20], ["ls", 6], ["str", 20], ["life", 60]],
		"metal": Color(0.2, 0.11, 0.08), "trim": Color(1.0, 0.62, 0.22), "glow": Color(1.0, 0.36, 0.05), "gem": Color(1.0, 0.22, 0.02)},
	"mire_heart": {"name": "Heart of the Mire", "base": "amulet", "lvl": 16, "stats": [["kill_heal", 5], ["vit", 20], ["regen", 6], ["res", 30], ["ls", 4]],
		"metal": Color(0.25, 0.35, 0.2), "trim": Color(0.5, 0.7, 0.3), "glow": Color(0.4, 1.0, 0.3), "gem": Color(0.3, 1.0, 0.4)},
	"dawnbreaker": {"name": "Dawnbreaker", "base": "runeblade", "lvl": 26, "stats": [["chill", 25], ["ed", 180], ["fire", 30], ["ias", 25], ["ls", 6], ["str", 20]],
		"metal": Color(0.95, 0.92, 0.85), "trim": Color(1.0, 0.8, 0.35), "glow": Color(1.0, 0.85, 0.4), "gem": Color(1.0, 0.95, 0.6)},
	"skullsplitter": {"name": "Skullsplitter", "base": "war_axe", "lvl": 15, "stats": [["chill", 20], ["ed", 140], ["dmg", 12], ["ls", 5], ["str", 12]],
		"metal": Color(0.3, 0.3, 0.32), "trim": Color(0.85, 0.82, 0.7), "glow": Color(0.9, 0.2, 0.1), "gem": Color(0.9, 0.1, 0.05)},
	"sunwarden": {"name": "Sunwarden Aegis", "base": "aegis", "lvl": 25, "stats": [["ward", 12], ["edef", 150], ["block", 15], ["res", 35], ["vit", 25]],
		"metal": Color(0.95, 0.8, 0.45), "trim": Color(1.0, 1.0, 0.95), "glow": Color(1.0, 0.85, 0.4), "gem": Color(1.0, 0.9, 0.5)},
}

## The old acts' strengths. Act I is the only act now; A2's and A3's stay for the items saved from them: an item
## keeps its "power" (how much stronger its stats are, Items.empower) and its tooltip names the act it came from.
const RUNS := [
	{"name": "Act I", "life": 1.0, "boss_life": 1.0, "dmg": 1.0, "loot": 1.0, "xp": 1.0, "power": 1.0},
	{"name": "A2", "life": 2.5, "boss_life": 3.1, "dmg": 0.9, "loot": 5.0, "xp": 5.0, "power": 1.6},
	{"name": "A3", "life": 4.6, "boss_life": 1.7, "dmg": 0.85, "loot": 25.0, "xp": 25.0, "power": 2.4},
]
## The items rework moved A2/A3 items from these act strengths to RUNS "power" (Items.upgrade).
const OLD_POWER := {5: 1.6, 25: 2.4}

const RARITY_COLOR := [Color(0.92, 0.92, 0.92), Color(0.45, 0.55, 1.0), Color(1.0, 0.95, 0.35), Color(0.82, 0.66, 0.38)]
const RARITY_NAME := ["Normal", "Magic", "Rare", "Unique"]

## Laid over by the Hero Codex (data/codex/, Codex.apply_skills) when this script loads: a static var, not a const.
static var SKILLS: Array = [
	{"id": "cleave", "cls": "knight", "name": "Holy Slam", "key": "Q", "lvl": 1, "mana": 5, "cd": 0.0, "aim": "point", "range": 6.0, "desc": "Leap at the cursor and bring the sword down in a burst of white light: 160% weapon damage to everything around the blow, knocking them back and stunning them for 1 second."},
	{"id": "nova", "cls": "knight", "name": "Holy Nova", "key": "E", "lvl": 3, "mana": 14, "cd": 0.0, "use": 1.0, "power": 0.37, "aim": "self", "desc": "A ring of holy fire bursts outward, burning enemies within 7 metres."},
	{"id": "charge", "cls": "knight", "name": "Charge", "key": "R", "lvl": 5, "mana": 10, "cd": 4.0, "tags": ["movement"], "aim": "facing", "range": 9.0, "desc": "Dash toward the cursor, smashing through enemies and knocking them back."},
	{"id": "cry", "cls": "knight", "name": "Battle Cry", "key": "F", "lvl": 9, "mana": 20, "cd": 20.0, "tags": ["warcry", "buff"], "aim": "self", "desc": "Rally yourself: +40% damage and +50% defense for 12 seconds. Stuns nearby foes."},
	{"id": "rend", "cls": "wraith", "name": "Spectral Rend", "key": "Q", "lvl": 1, "mana": 5, "cd": 0.0, "aim": "facing", "range": 4.5, "desc": "Lunge at the foe ahead and tear through it with elongated spectral claws: two rakes for 90% weapon damage each. Every soul the claws tear out flies back and heals you."},
	{"id": "siphon", "cls": "wraith", "name": "Soul Siphon", "key": "E", "lvl": 3, "mana": 12, "cd": 6.0, "tags": ["cc", "sustain"], "aim": "facing", "range": 9.0, "desc": "Reach out and hook a spectral tether into an enemy: for 2.5 seconds it stands rigid while the tether drains it (about 180% weapon damage in all) and heals you a third of what it takes, and it is slowed after. A soul torn loose heals you more. The tether holds while you fight on."},
	{"id": "step", "cls": "wraith", "name": "Shadow Step", "key": "R", "lvl": 5, "mana": 10, "cd": 5.0, "tags": ["movement"], "aim": "point", "range": 9.0, "desc": "Come apart into mist and re-form at the cursor, spinning into a claw strike round where you land for 130% weapon damage. For a moment after, blows pass through you. The shade you left behind collapses and hurts."},
	{"id": "grasp", "cls": "wraith", "name": "Haunting Grasp", "key": "F", "lvl": 9, "mana": 16, "cd": 10.0, "tags": ["cc"], "aim": "point", "range": 10.0, "desc": "Slam the ground: spectral hands burst out of the earth around the cursor, seizing every enemy within 3.5 metres for 110% weapon damage, dragging them inward and holding them fast for 2.5 seconds."},
	{"id": "phantom", "cls": "wraith", "name": "Phantom Assault", "key": "G", "lvl": 14, "mana": 22, "cd": 0.0, "use": 1.8, "power": 0.58, "aim": "facing", "range": 8.0, "desc": "Split into three phantoms that streak through the enemies ahead in a fan, each tearing everything in its path for 120% weapon damage, then strike with your own claws."},
	{"id": "night", "cls": "wraith", "name": "Eternal Night", "key": "V", "lvl": 20, "mana": 40, "cd": 40.0, "tags": ["ultimate"], "aim": "self", "desc": "Rise and bring down the night over 9 metres: a scream of terror (150% weapon damage, enemies hurled back and frozen with fear), then the dark feeds on everything in it while you hang untouchable above it, and it collapses into your slam for 200%. +40% damage for 12 seconds."},
	# the Demon (game/heroes/demon/): one job per skill. "pvp" overrides apply in the Battlegrounds against players only
	# (dmg = share of the PvE multiplier; the crowd control's seconds), on top of the server's PVP_MULT. Fault of the Pit and
	# Brimstone Hurl are main skills the Path of Exile way (no cooldown: a "use" time and a measured "power").
	{"id": "fists", "cls": "demon", "name": "Molten Fists", "key": "Q", "lvl": 1, "mana": 5, "cd": 0.0, "aim": "facing", "range": 3.4,
		"style": "fists", "use": 2.0, "hit": 0.75, "speed": "attack", "dmg": 300, "type": "phys", "knock": 0.5,
		"area": {"shape": "wedge", "r": 3.4, "angle": 84}, "dot": {"kind": "burn", "pct": 25, "secs": 3}, "tags": ["attack", "melee", "slam", "heavy", "fire"],
		"role": "Burst finisher", "pvp": {"brand_bonus": 0.2}, "desc": "A slow, heavy two-fisted blow: your fists catch fire as you draw back, then crack the ground open ahead of you. Everything in the wedge takes 300% weapon damage plus magma and is set alight. Branded enemies take 30% more and lose the Brand. Dodge to cancel it."},
	{"id": "icharge", "cls": "demon", "name": "Infernal Charge", "key": "E", "lvl": 3, "mana": 12, "cd": 9.0, "tags": ["movement"], "aim": "point", "range": 9.0, "role": "Engage / mobility", "pvp": {"dmg": 0.8, "stagger": 0.5}, "desc": "Paw the ground, then charge head-down up to 9 metres along a burning line everyone can see. You stop on the first champion or player you hit: it takes 120% weapon damage plus magma, is staggered and Branded. Lesser monsters are bowled aside."},
	{"id": "cslam", "cls": "demon", "name": "Fault of the Pit", "key": "R", "lvl": 5, "mana": 16, "cd": 0.0, "use": 2.2, "power": 0.95, "tags": ["attack", "slam", "area", "fire"], "aim": "facing", "range": 6.0, "role": "Area control", "pvp": {"dmg": 0.7, "knockup": 0.35, "slow": 0.35}, "desc": "Slam the ground and split it in a line 7 metres long across your aim. After a glowing warning it erupts: everything on it takes 133% weapon damage plus magma, is thrown up and Branded. The fault stays molten for 4 seconds: crossing it burns and slows by 35%."},
	{"id": "hurl", "cls": "demon", "name": "Brimstone Hurl", "key": "F", "lvl": 9, "mana": 18, "cd": 0.0, "use": 1.6, "power": 0.43, "tags": ["attack", "projectile", "area", "fire"], "aim": "point", "range": 14.0, "role": "Ranged pressure", "pvp": {"dmg": 0.75}, "desc": "Tear a molten boulder out of the ground and lob it up to 14 metres; its shadow shows where it will land. A direct hit (1.3 metres) deals 77% weapon damage plus magma and Brands; the edge (2.6 metres) half. No cooldown: throw again as soon as the throw is done. It shatters into burning shards."},
	{"id": "grip", "cls": "demon", "name": "Hellgrip", "key": "G", "lvl": 14, "mana": 20, "cd": 14.0, "tags": ["cc"], "aim": "facing", "range": 7.5, "role": "Pick / pull", "pvp": {"dmg": 0.62, "hold": 1.1}, "desc": "Hurl a molten chain with an iron claw 7.5 metres: the first enemy it hooks is dragged to you, hoisted and smashed into the ground for 320% weapon damage plus magma. Bosses drag you to them instead. A Branded target gives back 30% of the cooldown."},
	{"id": "wrath", "cls": "demon", "name": "Wrath of the Pit", "key": "V", "lvl": 20, "mana": 35, "cd": 60.0, "tags": ["ultimate"], "aim": "self", "role": "Defensive counter", "pvp": {"fear": 0.75, "bonus": 0.2, "meteors": 3}, "desc": "Fold your wings round you for up to 2 seconds (press again to end it early): you take 50% less damage, can't be stunned or moved, and store the damage as heat. Then burst out: everything within 6 metres takes 100% weapon damage plus the stored heat (up to 30% of your life), is hurled back and frozen with fear. For 6 seconds you deal +40% damage and meteors rain on the enemies round you."},
	{"id": "drain", "cls": "warlock", "channel": true, "name": "Drain Life", "key": "Q", "lvl": 1, "mana": 6, "cd": 0.0, "aim": "facing", "range": 11.0, "desc": "Hold to drain life from an enemy with a green beam. It also hits up to 3 enemies near it, and everything it drains heals you."},
	{"id": "blight", "cls": "warlock", "name": "Blight Bolt", "key": "E", "lvl": 3, "mana": 12, "cd": 0.0, "use": 1.0, "power": 0.59, "aim": "facing", "range": 15.0, "desc": "Throw a blight skull. It bursts and leaves a poison pool for 4 seconds."},
	{"id": "shackles", "cls": "warlock", "name": "Soul Shackles", "key": "R", "lvl": 5, "mana": 16, "cd": 8.0, "tags": ["cc"], "aim": "self", "desc": "Chain every enemy within 7 metres in place for 2.5 seconds, hurting them."},
	# the archer: his attack is the bow (Hero._bow_attack); the arrows are Hero.arrows
	{"id": "pierce", "cls": "archer", "name": "Fire Arrow", "key": "Q", "lvl": 1, "mana": 5, "cd": 0.0, "aim": "facing", "range": 16.0, "desc": "A burning arrow that tears through every enemy in a line for 130% weapon damage and sets them alight: they burn for 3 seconds."},
	{"id": "volley", "cls": "archer", "name": "Frost Volley", "key": "E", "lvl": 3, "mana": 14, "cd": 0.0, "use": 1.1, "aim": "point", "range": 14.0, "desc": "Loose a flight of frost arrows into the sky: they rain on the cursor for over a second, hitting everything within 4 metres again and again and chilling them (40% slower); the ground stays frozen for a few seconds, slowing everything that stands in it or crosses it."},
	{"id": "snare", "cls": "archer", "name": "Thunderstep", "key": "R", "lvl": 5, "mana": 12, "cd": 7.0, "tags": ["mobility", "cc"], "aim": "point", "range": 10.0, "desc": "Backflip away from the pointer, driving a thunderstone into a gold storm sigil where you stood. A moment later it detonates: everything on it is stunned and hurt, and lightning leaps on into the 3 nearest others beyond it."},
	{"id": "beast", "cls": "archer", "name": "Spirit Beast", "key": "F", "lvl": 9, "mana": 12, "cd": 8.0, "tags": ["command", "summon"], "aim": "point", "range": 18.0, "desc": "Your Spirit Beast hunts at your side from the start (and you run 10% faster with it). Command it: on an enemy it pounces and fights it, on open ground it holds there, on yourself it comes back. Each command rouses you both: +40% damage for 12 seconds."},
	{"id": "toxic", "cls": "plague", "name": "Pestilence Vial", "key": "Q", "lvl": 1, "mana": 7, "cd": 0.0, "aim": "point", "range": 12.0, "desc": "Pluck a vial of plague from your bandolier and lob it. A ring shows everyone where it will land. It bursts for a small hit and leaves a contaminated pool 2.6 metres wide for 3.5 seconds: anything standing in it is poisoned and keeps rotting for 2 seconds after it steps out. Pools of the same kind don't stack."},
	{"id": "swarm", "cls": "plague", "name": "Swarmcraft", "key": "E", "lvl": 3, "mana": 16, "cd": 12.0, "tags": ["summon", "cc"], "aim": "point", "range": 13.0, "desc": "Uncork your reliquary: a swarm of plague flies flies to the spot and hangs there for 6 seconds, biting whatever is inside and harrying it (attacks and casts 25% slower). Use it again to send the swarm somewhere else (twice). It never chases anyone, it's slower than a running man, and a dodge roll through it scatters it for a moment. The cooldown starts when it comes home."},
	{"id": "bloom", "cls": "plague", "name": "Corpse Bloom", "key": "R", "lvl": 5, "mana": 14, "cd": 10.0, "tags": ["trap", "cc"], "aim": "point", "range": 9.0, "desc": "Drive a seed into the ground. It grows for a second, then breathes for 6 seconds: every 2 seconds its ring of roots draws in and a spore pulse hits everything within 3.5 metres. Anyone who stood still while the ring drew in is snared by its roots for 0.6 seconds. In the Battlegrounds other players can break it with three blows."},
	{"id": "fog", "cls": "plague", "name": "Fog of the Forgotten", "key": "F", "lvl": 9, "mana": 15, "cd": 16.0, "tags": ["movement", "buff"], "aim": "point", "range": 4.0, "desc": "Dash your censer at your feet and hop 4 metres back from the pointer. Pale fog 6 metres across hangs for 6 seconds: other players outside it can't see anyone inside, and inside it everyone within 3.5 metres is seen. You move 25% faster in it; monsters beyond 3.5 metres lose track of you in it; striking from it reveals you for a moment."},
	{"id": "transfusion", "cls": "plague", "name": "Transfusion", "key": "G", "lvl": 14, "mana": 10, "cd": 18.0, "tags": ["buff", "sustain"], "aim": "self", "desc": "Drive the needle of your apparatus into your arm: for 2 seconds you take 45% less damage and move at 70% speed, and slows, snares and Blight are washed out of you. What the tanks soak heals you afterwards (up to 15% of your life). Attacking ends it early."},
	{"id": "experiment", "cls": "plague", "name": "The Last Experiment", "key": "V", "lvl": 20, "mana": 40, "cd": 45.0, "tags": ["ultimate"], "aim": "point", "range": 7.0, "desc": "Slam down your vat (everyone sees an 8-metre warning ring) and crank it for 2.5 seconds. Then the glass bursts, the thing inside crawls out and the ring becomes a quarantine for 7 seconds: spores, Blight and a 20% slow inside, and the creature lumbers at the nearest foe, spewing. A stun, another skill or walking away from the vat bursts it early, only 5 metres wide. In the Battlegrounds other players can break the vat while you crank it (three blows: the experiment fails) and kill the creature (four)."},
	{"id": "covenant", "cls": "warlock", "name": "Fel Covenant", "key": "F", "lvl": 9, "mana": 20, "cd": 20.0, "tags": ["buff"], "aim": "self", "desc": "For 12 seconds you deal 40% more damage, and Drain Life hits more enemies and heals twice as much."},
	# the Warlock's three directions (WarlockHex; Blaine 2026-11-06, the Hero Codex): Corruption, Fear, Drain
	{"id": "w_corruption", "cls": "warlock", "name": "Corruption", "key": "", "lvl": 2, "mana": 4, "cd": 0.0, "use": 0.45, "aim": "facing", "range": 15.0, "tags": ["spell", "dot", "curse"], "role": "Cheap curse",
		"desc": "A cheap curse: 240% spell damage over 10 seconds."},
	{"id": "w_malediction", "cls": "warlock", "name": "Malediction", "key": "", "lvl": 7, "mana": 10, "cd": 0.0, "use": 0.8, "aim": "facing", "range": 15.0, "tags": ["spell", "projectile"], "role": "Curse payoff",
		"desc": "A bolt for 90% spell damage, plus 50% for each of your curses on the enemy."},
	{"id": "w_unending", "cls": "warlock", "name": "Unending Rot", "key": "", "lvl": 11, "mana": 8, "cd": 0.0, "use": 0.5, "aim": "facing", "range": 15.0, "tags": ["spell", "dot", "curse"], "role": "Ramping curse",
		"desc": "A curse that grows stronger the longer the enemy stays cursed, up to four times as strong."},
	{"id": "w_festering", "cls": "warlock", "name": "Festering Hex", "key": "", "lvl": 13, "mana": 12, "cd": 6.0, "use": 0.5, "aim": "facing", "range": 15.0, "tags": ["spell", "dot", "curse", "cc"], "role": "Stun curse",
		"desc": "A curse that bursts every 5 seconds for 120% spell damage and a short stun."},
	{"id": "w_leeching", "cls": "warlock", "name": "Leeching Curse", "key": "", "lvl": 11, "mana": 8, "cd": 0.0, "use": 0.5, "aim": "facing", "range": 15.0, "tags": ["spell", "dot", "curse", "sustain"], "role": "Healing curse",
		"desc": "A curse for 160% spell damage over 8 seconds. Half of it heals you."},
	{"id": "w_reckoning", "cls": "warlock", "name": "Reckoning", "key": "", "lvl": 16, "mana": 16, "cd": 0.0, "use": 0.7, "aim": "facing", "range": 15.0, "tags": ["spell", "dot", "curse"], "role": "Curse multiplier",
		"desc": "A curse for 6 seconds whose every tick hits as hard as all your other curses on the enemy put together."},
	{"id": "w_terrify", "cls": "warlock", "name": "Terrify", "key": "", "lvl": 4, "mana": 8, "cd": 9.0, "use": 0.4, "aim": "facing", "range": 8.0, "tags": ["spell", "cc"], "role": "Single fear",
		"desc": "Freeze an enemy in terror for 1.5 seconds. Scared enemies take 20% more from your spells."},
	{"id": "w_effigy", "cls": "warlock", "name": "Dread Totem", "key": "", "lvl": 12, "mana": 14, "cd": 14.0, "use": 0.6, "aim": "point", "range": 12.0, "tags": ["trap", "cc"], "role": "Fear totem",
		"desc": "Plant a totem for 8 seconds. It scares the first 3 enemies that come near it."},
	{"id": "w_darkwind", "cls": "warlock", "name": "Void Wisp", "key": "", "lvl": 8, "mana": 12, "cd": 6.0, "use": 0.6, "aim": "facing", "range": 12.0, "tags": ["spell", "projectile", "chain", "cc"], "role": "Bouncing wisp",
		"desc": "A wisp that bounces between up to 5 enemies, hurting and slowing each. Scared enemies take double."},
	{"id": "w_crowstorm", "cls": "warlock", "name": "Eclipse Bloom", "key": "", "lvl": 20, "mana": 40, "cd": 45.0, "use": 1.5, "aim": "point", "range": 8.0, "tags": ["ultimate", "cc", "movement"], "role": "Ultimate",
		"desc": "Blink up to 8 metres into a storm of void petals. Enemies caught are scared and keep getting hurt for 5 seconds."},
	{"id": "w_leechbolt", "cls": "warlock", "name": "Leech Bolt", "key": "", "lvl": 2, "mana": 5, "cd": 0.0, "use": 0.6, "aim": "facing", "range": 14.0, "tags": ["spell", "projectile", "sustain"], "role": "Healing bolt",
		"desc": "A quick bolt for 140% spell damage. 30% of it heals you."},
	{"id": "w_harvest", "cls": "warlock", "name": "Thornlash", "key": "", "lvl": 7, "mana": 12, "cd": 0.0, "use": 0.9, "aim": "self", "tags": ["spell", "area", "sustain"], "role": "Healing lash",
		"desc": "Lash thorned vines all around you for 180% spell damage. Each enemy hit heals you."},
	{"id": "w_soulfeast", "cls": "warlock", "name": "Soul Feast", "key": "", "lvl": 20, "mana": 30, "cd": 30.0, "use": 3.0, "aim": "self", "tags": ["ultimate", "channel", "sustain"], "role": "Ultimate",
		"desc": "Channel for 3 seconds to drain every enemy within 7 metres. Healing past full life becomes a shield."},
	# Doug (doug_skills.gd): the trickster; every tool readable, every tool answerable
	{"id": "pie", "cls": "doug", "name": "Cream Pie", "key": "", "lvl": 1, "mana": 6, "cd": 0.0, "use": 0.9, "hit": 0.5, "style": "pie", "speed": "attack", "dmg": 120, "type": "phys", "aim": "point", "range": 12.0, "tags": ["projectile", "attack"],
		"desc": "Lob a cream pie at the cursor (12 m): a splat for 120% weapon damage and the target is Pied: monsters blinded for 2 seconds, a player's screen creamed at the edges and their aim assist gone for 1.5 seconds. The same target can't be Pied again for 6 seconds."},
	{"id": "peels", "cls": "doug", "name": "Banana Peels", "key": "Q", "lvl": 2, "mana": 9, "cd": 7.0, "use": 0.8, "hit": 0.55, "style": "peels", "aim": "facing", "range": 6.0, "tags": ["trap"],
		"desc": "Toss three banana peels in a fan ahead (they land 3 to 6 metres out and last 8 seconds; at most 6 down). Whoever steps on one slips: a player is knocked down for 0.7 seconds and slides on, a monster is stunned for 1 second. A dodge roll over a peel doesn't slip."},
	{"id": "slide", "cls": "doug", "name": "Pratfall Slide", "key": "E", "lvl": 4, "mana": 10, "cd": 5.0, "use": 0.7, "hit": 0.2, "style": "slide", "dmg": 90, "knock": 3.0, "aim": "facing", "range": 7.0, "tags": ["movement"],
		"desc": "Belly-slide 7 metres the way you face, honking: foes in the way take 90% weapon damage and are shoved aside. You pop up with a ta-da."},
	{"id": "doppel", "cls": "doug", "name": "Doppel-Doug", "key": "R", "lvl": 7, "mana": 14, "cd": 14.0, "use": 0.4, "hit": 0.5, "style": "doppel", "aim": "point", "range": 12.0, "tags": ["buff", "summon"],
		"desc": "Duck behind a puff of confetti: you turn invisible for 1.8 seconds while a balloon double of you runs off toward the cursor, waving. Struck, the double pops in a confetti burst that slows whoever is near for 1.5 seconds."},
	{"id": "juggle", "cls": "doug", "name": "Pin Juggle", "key": "F", "lvl": 10, "mana": 16, "cd": 0.0, "use": 1.4, "hit": 0.35, "style": "juggle", "dmg": 60, "type": "fire", "aim": "point", "range": 12.0, "tags": ["projectile", "fire"],
		"desc": "Throw five flaming juggling pins in quick succession at the cursor; each bounces on to two more foes. 60% weapon damage as fire each."},
	{"id": "bounce", "cls": "doug", "name": "Big Top Bounce", "key": "G", "lvl": 14, "mana": 18, "cd": 10.0, "use": 1.3, "hit": 0.78, "style": "bounce", "dmg": 180, "knock": 2.0, "aim": "point", "range": 10.0, "tags": ["movement", "cc"], "cancel": false,
		"desc": "Slam down a trampoline and bounce up to 10 metres to the cursor, landing in a belly-flop: 180% weapon damage in 3 metres and foes are launched for 0.8 seconds. A shadow and a whistle mark where you'll land."},
	{"id": "car", "cls": "doug", "name": "Clown Car", "key": "V", "lvl": 20, "mana": 40, "cd": 60.0, "use": 0.6, "hit": 0.5, "style": "car", "dmg": 140, "aim": "self", "tags": ["ultimate"],
		"desc": "A tiny clown car screeches in and you drive it for 5 seconds: fast, unstoppable, ramming foes for 140% weapon damage and knocking them flying. Then it bursts in confetti and six mini clowns tumble out, sprint at the nearest foes and pie them."},
	# the shared skills (SharedSkills): "cls": "any", every class can put them on its bar (jj, 2026-11-01)
	{"id": "earthshatter", "cls": "any", "name": "Earthshatter", "key": "", "lvl": 16, "mana": 8, "cd": 0.0, "aim": "facing", "range": 5.0,
		"style": "slam", "use": 1.6, "speed": "attack", "dmg": 230, "base": [10, 16], "per_lvl": 2.5, "type": "phys", "knock": 1.2,
		"area": {"shape": "wedge", "r": 5.0, "angle": 100}, "tags": ["attack", "melee", "slam", "heavy", "area"],
		"desc": "A heavy two-handed slam: the wedge it will crack shows as you heave, then the ground splits ahead of you for 230% weapon damage plus a part that grows with your level, throwing foes back."},
	{"id": "frost_nova", "cls": "any", "name": "Frost Nova", "key": "", "lvl": 8, "mana": 10, "cd": 0.0, "aim": "self",
		"style": "cast", "use": 0.9, "speed": "cast", "base": [12, 18], "per_lvl": 3.5, "type": "cold",
		"area": {"shape": "circle", "r": 4.0, "at": "self"}, "dot": {"kind": "chill", "k": 0.45, "secs": 3.0}, "tags": ["spell", "cold", "area", "nova"],
		"desc": "A ring of ice bursts out around you, 4 metres: cold damage, and everything it hits is chilled, slowed for 3 seconds."},
	{"id": "arc", "cls": "any", "name": "Arc", "key": "", "lvl": 11, "mana": 6, "cd": 0.0, "aim": "facing", "range": 10.0,
		"style": "cast", "use": 0.7, "speed": "cast", "base": [8, 14], "per_lvl": 2.8, "type": "lightning",
		"area": {"shape": "single", "r": 10.0}, "tags": ["spell", "lightning", "chain"],
		"desc": "Lightning leaps from your hand into the nearest foe ahead and on to three more nearby, striking each."},
	# the Frost Serpent's own (jj, 2026-11-04: "give frost serpent a frost breath attack")
	{"id": "frost_breath", "cls": "serpent", "name": "Frost Breath", "key": "Q", "lvl": 1, "mana": 10, "cd": 0.0, "aim": "facing", "range": 7.0,
		"style": "breath", "use": 1.4, "speed": "cast", "base": [4, 7], "per_lvl": 1.3, "type": "cold",
		"area": {"shape": "wedge", "r": 7.0, "angle": 70.0}, "dot": {"kind": "chill", "k": 0.45, "secs": 1.5}, "tags": ["spell", "cold", "area", "channel"],
		"desc": "The serpent lowers its head and breathes a freezing gale over everything in a cone 7 metres ahead for over a second: cold damage again and again, chilling (slowing) them; the ground frosts over and ice bursts up where it ends."},
	# the Storm Wyvern's own (jj, 2026-11-04: "give Arc for the storm wyvern"): rears up and breathes chain lightning
	{"id": "storm_arc", "cls": "wyvern", "name": "Storm Arc", "key": "Q", "lvl": 1, "mana": 6, "cd": 0.0, "aim": "facing", "range": 11.0,
		"style": "cast", "use": 0.75, "speed": "cast", "base": [10, 16], "per_lvl": 3.2, "type": "lightning",
		"area": {"shape": "single", "r": 11.0}, "tags": ["spell", "lightning", "chain"],
		"desc": "The wyvern rears up, the lightning in its wings flaring, and breathes a bolt into the nearest foe ahead that leaps on to four more nearby, striking each."},
	{"id": "war_cry", "cls": "any", "name": "War Cry", "key": "", "lvl": 6, "mana": 12, "cd": 8.0, "aim": "self",
		"style": "cast", "use": 0.8, "speed": "attack", "tags": ["warcry", "buff"],
		"desc": "A roar that rallies your team: you and every ally within 8 metres deal +40% damage for 6 seconds, and the monsters near turn on you. In the Battlegrounds it is yours alone (no teams there yet)."},
]

## Playable classes. Base attributes at level 1.
## How long every attack, skill swing and cast takes, as a multiple of its base timing (1.2 = 20% slower).
## Every class uses it, including new ones; a class can set its own "attack_pace" in CLASSES (a special
## character). Weapon speed, increased attack speed and Dexterity still speed attacks up from there.
## Attacks whose rate the swing sets hit that much harder (Hero.pace_mult), so damage per second stays where the balance put it.
const ATTACK_PACE := 1.2

static func attack_pace(cls: String) -> float:
	return float(CLASSES[cls].get("attack_pace", ATTACK_PACE)) if CLASSES.has(cls) else ATTACK_PACE

## Every playable class. "voice": the hurt/death sounds' suffix (hurt_<voice>, death_<voice>; "knight" when absent).
## A new class also needs its skills (SKILLS, with "cls"), a skills script (ClassSkills.of) and its effects (SkillFx.play).
const CLASSES := {
	"knight": {"name": "Knight", "str": 20, "dex": 15, "vit": 25, "ene": 10,
		"desc": "A crusader in steel. Sword and shield, heavy blows, holy fire and a rallying cry."},
	"wraith": {"voice": "wraith", "name": "Wraith", "str": 15, "dex": 22, "vit": 18, "ene": 28,
		"desc": "A horned spirit in chains that never touches the ground. Tears souls out with spectral claws, drains them down a tether, steps through shadow, drags foes into the earth's grasp and brings down the night."},
	"demon": {"voice": "demon", "name": "Demon", "str": 24, "dex": 14, "vit": 24, "ene": 18,
		"desc": "A horned, winged brute of charcoal hide with magma burning through the cracks. Cracks the ground with his fists, charges through his foes on a trail of lava, hurls molten boulders and calls meteors down from the pit."},
	# the bow class (Jace's): its name is his to choose; "Archer" until then
	"archer": {"name": "Archer", "str": 14, "dex": 26, "vit": 18, "ene": 14, "weapon": "short_bow",
		"desc": "A red-hooded ranger with a carved recurve bow and his dire wolf at his side. Shoots on the move: fire arrows that burn through a line, frost volleys that chill, and a thunderstep that leaves a storm sigil behind him."},
	"doug": {"name": "Doug", "str": 18, "dex": 22, "vit": 18, "ene": 16, "weapon": "roast_drumstick",
		"desc": "A washed-up circus brawler with a roast drumstick and a bag of tricks. Every gag is a weapon: pies that blind, peels that trip, a double that runs the other way, and a clown car nobody wants to see coming."},
	"plague": {"name": "Plague Doctor", "str": 14, "dex": 18, "vit": 18, "ene": 24, "weapon": "physician_cane",
		"desc": "A beaked physician of the cursed years, belted with vials and a smoking censer. Fights by control: vials of plague, a swarm of flies, a corpse flower that roots the careless, a fog to vanish in, a transfusion to outlast a beating, and a last experiment that turns the ground to quarantine."},
	"warlock": {"voice": "gnome", "name": "Warlock", "str": 10, "dex": 10, "vit": 10, "ene": 10,
		"desc": "A hooded sorcerer bound by a fel pact. Drains the life from foes in a forking green beam, rots them with blight and chains them where they stand."},
	# the dragons (scripts/dragon.gd): no skills yet, only the basic attack (claw, bite, tail spin); "claws" is the
	# damage and speed of their natural weapons when nothing is equipped (they start with none)
	"wyrm": {"voice": "wyrm", "name": "Obsidian Wyrm", "str": 26, "dex": 12, "vit": 26, "ene": 12, "claws": [3, 8], "claw_speed": 1.0,
		"desc": "A heavy, low-slung dragon of black volcanic scale, ember-tipped spines and blood-red wings. Rakes with its foreclaws, bites, and spins to sweep its long tail through everything around it."},
	"serpent": {"voice": "serpent", "name": "Frost Serpent", "str": 20, "dex": 22, "vit": 20, "ene": 14, "claws": [3, 7], "claw_speed": 1.1,
		"desc": "A long, wingless dragon of pale ice-blue scale with crystal antlers and a ridge of ice shards. Swims over the ground, strikes with claw and fang and lashes its tail in a full turn."},
	"wyvern": {"voice": "wyvern", "name": "Storm Wyvern", "str": 22, "dex": 20, "vit": 22, "ene": 12, "claws": [3, 7], "claw_speed": 1.1,
		"desc": "A rearing two-legged dragon whose wings are its forelimbs, with lightning veined through the membranes. Strikes with its wing claws, bites, and whips its barbed tail round."},
}

## A class's damage and speed with no weapon equipped: the dragons' claws and teeth, bare hands for the rest.
static func unarmed(cls: String) -> Array:
	return CLASSES[cls].get("claws", [1, 3]) if CLASSES.has(cls) else [1, 3]

static func unarmed_speed(cls: String) -> float:
	return float(CLASSES[cls].get("claw_speed", 1.2)) if CLASSES.has(cls) else 1.2

## The shared skills ("cls": "any" in SKILLS), every class's to use (SharedSkills).
static func _static_init() -> void:
	Codex.apply_skills(SKILLS)
	Codex.apply_skills(RUN_SKILLS)

static func shared_skills() -> Array:
	return SKILLS.filter(func(s): return s["cls"] == "any")

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

## Every skill a class can bind: its own skills, the shared ones, then the common ones.
static func skills_known(cls: String) -> Array:
	return skills_for(cls) + shared_skills() + COMMON_SKILLS

## Skills unlock by level (Blaine's progression overhaul): each skill's "lvl";
## a class's skills Q 1, E 3, R 5, F 9, G 14 and every ultimate at 20, the shared ones spread between (War Cry 6,
## Frost Nova 8, Arc 11, Earthshatter 16). A locked skill shows greyed with its level, can't be bound or cast.
## true opens every skill from level 1 again (jj's unlock-all, 2026-11-01); the F8 panel's "All skills" does it for
## testing (Game.test_allskills).
## Skills only a multiplayer run offers (Blaine's roguelike pass, 2026-11-06): camp chests draw them with the class's
## own (RunBuild.skill_pool); single player never sees them (skills_for, skills_known and the class picker read SKILLS).
## Their build theme is RunTalents.SKILL_THEMES; their reward rarity comes from "lvl" (RunBuild.skill_rarity).
## Laid over by the Hero Codex (data/codex/, Codex.apply_skills) when this script loads.
static var RUN_SKILLS: Array = [
	{"id": "a_multishot", "cls": "archer", "name": "Scatter Shot", "lvl": 1, "mana": 7, "cd": 0.0, "use": 0.85, "aim": "facing", "range": 13.0, "role": "packs up close",
		"desc": "Loose five arrows in a fan: 55% weapon damage each. A foe close enough takes several."},
	{"id": "a_glacial", "cls": "archer", "name": "Glacial Shard", "lvl": 1, "mana": 6, "cd": 0.0, "use": 0.85, "aim": "facing", "range": 16.0, "role": "line chill",
		"desc": "An arrow of ice that pierces every foe in a line for 110% weapon damage and chills them (40% slower) for 3 seconds."},
	{"id": "a_explosive", "cls": "archer", "name": "Blast Arrow", "lvl": 9, "mana": 9, "cd": 0.0, "use": 1.0, "aim": "facing", "range": 16.0, "role": "fire burst",
		"desc": "A fire arrow that bursts at the first foe it strikes or where its flight ends: 150% weapon damage to everything within 3.5 metres, setting them burning."},
	{"id": "a_stormshot", "cls": "archer", "name": "Storm Shot", "lvl": 9, "mana": 8, "cd": 0.0, "use": 0.9, "aim": "facing", "range": 16.0, "role": "chain lightning",
		"desc": "A charged arrow: 100% weapon damage to the first foe it strikes, then lightning leaps on to 4 more for 70%."},
	{"id": "a_mark", "cls": "archer", "name": "Hunter's Mark", "lvl": 9, "mana": 6, "cd": 6.0, "tags": ["cc"], "aim": "point", "range": 18.0, "role": "focus a target",
		"desc": "Mark the foe under the pointer for 8 seconds: it takes 35% more damage from everyone, and your wolf hunts it down."},
	{"id": "a_barrage", "cls": "archer", "name": "Arrow Storm", "lvl": 16, "mana": 16, "cd": 0.0, "use": 1.2, "aim": "point", "range": 14.0, "role": "area rain",
		"desc": "Loose a storm of arrows into the sky: for 1.5 seconds they rain on the cursor, striking everything within 4.5 metres six times for 32% weapon damage."},
	{"id": "p_miasma", "cls": "plague", "name": "Miasma", "lvl": 1, "mana": 9, "cd": 0.0, "use": 0.9, "aim": "self", "role": "poison around him",
		"desc": "Smash a censer of plague at your feet: a cloud 4.5 metres wide hangs for 4 seconds, poisoning everything in it."},
	{"id": "p_spread", "cls": "plague", "name": "Contagion", "lvl": 9, "mana": 8, "cd": 0.0, "use": 0.8, "aim": "point", "range": 14.0, "role": "spreading curse",
		"desc": "Curse the foe nearest the pointer with a creeping plague for 6 seconds: it is poisoned, and every second its poison leaps to all within 4 metres. If it dies cursed, the plague bursts to everyone within 5 metres."},
	{"id": "k_whirl", "cls": "knight", "name": "Blade Storm", "lvl": 1, "mana": 8, "cd": 0.0, "use": 0.9, "aim": "self", "role": "spin through a crowd",
		"desc": "Spin with the sword out: everything within 3.2 metres is struck twice for 70% weapon damage. Every blow of yours leaves a Holy Brand on its foe (up to 5)."},
	{"id": "k_aegis", "cls": "knight", "name": "Aegis", "lvl": 1, "mana": 10, "cd": 10.0, "tags": ["sustain", "warcry"], "aim": "self", "role": "absorb, then answer",
		"desc": "Raise a holy ward worth 35% of your life for 5 seconds and call everything within 5 metres onto you. When it breaks or ends, it bursts: everything within 5 metres takes all the damage it soaked."},
	{"id": "k_judgment", "cls": "knight", "name": "Judgment", "lvl": 9, "mana": 12, "cd": 0.0, "use": 1.0, "aim": "point", "range": 14.0, "role": "cash in the brands",
		"desc": "Call a pillar of holy light down on the pointer: 120% weapon damage within 3 metres, +45% for every Holy Brand on each foe (the brands are spent), and holy fire burns them."},
	{"id": "k_rites", "cls": "knight", "name": "Last Rites", "lvl": 9, "mana": 10, "cd": 8.0, "tags": ["movement"], "aim": "point", "range": 9.0, "role": "execute and reset",
		"desc": "Leap at the foe nearest the pointer and bring the sword down: 150% weapon damage, +2% for every 1% of life it is missing. A kill makes Last Rites ready again."},
	{"id": "r_deathmark", "cls": "wraith", "name": "Death Mark", "lvl": 9, "mana": 10, "cd": 10.0, "tags": ["cc"], "aim": "point", "range": 12.0, "role": "burst a single target",
		"desc": "Mark the foe nearest the pointer. When the mark ends 3 seconds later it tears out half of everything you dealt it meanwhile (at least 150% weapon damage) as a soul you drink back."},
	{"id": "r_wail", "cls": "wraith", "name": "Banshee Wail", "lvl": 1, "mana": 9, "cd": 8.0, "tags": ["cc"], "aim": "self", "role": "terrify the crowd",
		"desc": "Scream: everything within 6 metres takes 60% weapon damage, is frozen in terror for 1.2 seconds and slowed by half for 2 more."},
	{"id": "r_reap", "cls": "wraith", "name": "Reaping Crescent", "lvl": 1, "mana": 8, "cd": 0.0, "use": 0.9, "aim": "facing", "range": 5.0, "role": "sweep and sustain",
		"desc": "A great crescent of soul-fire sweeps out 5 metres in front of you: 170% weapon damage, and each foe it reaps heals you 2% of your life."},
	{"id": "d_volcano", "cls": "demon", "name": "Volcano", "lvl": 9, "mana": 16, "cd": 0.0, "use": 1.2, "aim": "point", "range": 13.0, "role": "bombard an area",
		"desc": "Tear open a volcano at the pointer: it hurls five meteors onto the foes around it over two seconds, each 85% weapon damage and setting them alight."},
	{"id": "d_detonate", "cls": "demon", "name": "Hellbrand Detonation", "lvl": 1, "mana": 8, "cd": 6.0, "tags": ["cc"], "aim": "self", "role": "cash in the Brands",
		"desc": "Every Branded foe within 10 metres erupts: 160% weapon damage, thrown up for 0.8 seconds, and the fire bursts onto those beside it. The Brands are spent."},
	{"id": "d_pact", "cls": "demon", "name": "Blood Pact", "lvl": 1, "mana": 0, "cd": 12.0, "tags": ["buff"], "aim": "self", "role": "life for power",
		"desc": "Pay 15% of your life to the pit: for 8 seconds +35% damage and 6% of the damage you deal heals you."},
	{"id": "u_barrage", "cls": "doug", "name": "Pie Barrage", "lvl": 1, "mana": 10, "cd": 0.0, "use": 1.1, "aim": "point", "range": 12.0, "role": "pie a crowd",
		"desc": "Fling six cream pies at once onto the foes around the pointer: each 80% weapon damage, and the first time a foe is Pied it is stunned and slowed."},
	{"id": "u_bonanza", "cls": "doug", "name": "Banana Bonanza", "lvl": 9, "mana": 8, "cd": 9.0, "tags": ["trap"], "aim": "self", "role": "a ring of peels",
		"desc": "Scatter eight banana peels in a ring round you: whatever steps on one goes down. Your next blow on a slipped foe within 4 seconds hits twice as hard."},
	{"id": "u_cannon", "cls": "doug", "name": "Human Cannonball", "lvl": 9, "mana": 12, "cd": 8.0, "tags": ["movement"], "aim": "point", "range": 14.0, "role": "fly in, flatten",
		"desc": "Fire yourself out of a cannon onto the pointer (14 metres): you land in a belly-flop that deals 260% weapon damage within 4.5 metres and knocks them down."},
	# the dragons (DragonSkills; looks DragonRunFx)
	{"id": "s_tomb", "cls": "serpent", "name": "Glacial Tomb", "lvl": 1, "mana": 10, "cd": 9.0, "tags": ["cc"], "aim": "point", "range": 12.0, "role": "lock a pack, then shatter it",
		"desc": "Seal the foe nearest the pointer, and all within 2.5 metres of it, in ice for 1.6 seconds. Then the tomb shatters: 180% weapon damage to each sealed foe and 90% to everything else within 3 metres."},
	{"id": "s_coil", "cls": "serpent", "name": "Crushing Coil", "lvl": 1, "mana": 7, "cd": 0.0, "use": 1.0, "aim": "self", "role": "crush what surrounds you",
		"desc": "Whip your body round in a full coil: 130% weapon damage to everything within 4.2 metres, slowing them by 45% for 2 seconds. Chilled foes are crushed for 30% more."},
	{"id": "s_lance", "cls": "serpent", "name": "Rime Lance", "lvl": 9, "mana": 9, "cd": 0.0, "use": 1.0, "aim": "facing", "range": 10.0, "role": "a line of ice",
		"desc": "Breathe a line of ice spikes 10 metres ahead: 125% weapon damage to every foe on it, chilling them. A foe already chilled is frozen solid for 1 second."},
	{"id": "v_dive", "cls": "wyvern", "name": "Thunder Dive", "lvl": 1, "mana": 12, "cd": 8.0, "tags": ["movement"], "aim": "point", "range": 12.0, "role": "dive in and stun",
		"desc": "Climb on your wings and dive onto the pointer (12 metres) in a strike of lightning: 240% weapon damage within 4 metres, stunning them for 0.8 seconds."},
	{"id": "v_cloud", "cls": "wyvern", "name": "Thunderhead", "lvl": 9, "mana": 14, "cd": 0.0, "use": 1.1, "aim": "point", "range": 13.0, "role": "a storm over a crowd",
		"desc": "Roar up a storm cloud over the pointer for 4 seconds: every half second it strikes a foe beneath it (within 5 metres) for 45% weapon damage. At most two at once."},
	{"id": "v_gale", "cls": "wyvern", "name": "Gale Wings", "lvl": 1, "mana": 8, "cd": 6.0, "tags": ["cc"], "aim": "facing", "range": 6.5, "role": "blow them away",
		"desc": "One great beat of your wings: everything in a cone 6.5 metres ahead takes 100% weapon damage, is hurled back and slowed by 40% for 2.5 seconds."},
	{"id": "p_leech", "cls": "plague", "name": "Leech Jar", "lvl": 9, "mana": 10, "cd": 9.0, "tags": ["sustain"], "aim": "point", "range": 12.0, "role": "heal from foes",
		"desc": "Lob a jar of blood leeches: for 5 seconds everything within 3 metres is poisoned, and every foe in it heals you 1.5% of your life a second."},
]

static func run_skills_for(cls: String) -> Array:
	return RUN_SKILLS.filter(func(s): return s["cls"] == cls)

const SKILLS_UNLOCKED := false

## Item power (Blaine's progression overhaul, then "not 'cut' but full rework"): character
## level and skills give most of a player's power, gear a smaller but meaningful part, in PvE and PvP alike.
## Items made under these rules carry "gen": ITEM_GEN; older ones are rebuilt once on load (Items.upgrade).
const ITEM_GEN := 4            # 2: the rework's sizes; 3: the uniques' signature effects; 4: effects no longer act-scaled (uniques remade each time)
## Every affix rolls Data.AFFIXES' range times its scale here (Items.roll_affix), and an old item's affixes are
## rescaled by the same (Items.upgrade). Gold and Magic Find buy no power, so they keep their size.
const AFFIX_SCALE := {"ed": 0.2, "dmg": 0.25, "fire": 0.35, "str": 0.2, "dex": 0.2, "vit": 0.2, "ene": 0.2,
	"life": 0.22, "mana": 0.33, "ias": 0.4, "ls": 0.4, "def": 0.12, "edef": 0.15, "res": 0.45, "block": 0.5,
	"regen": 0.4, "frw": 0.25}
## Base defence (armour, helms, shields...) counts for this share (Items.defense_of).
const GEAR_ARMOR := 0.05
## Caps on the totals across all gear (Hero.recalc): +5% run speed is a standout.
const GEAR_CAP := {"frw": 5, "ias": 25, "res": 25, "ls": 4, "block": 15, "stam": 25, "cdr": 10, "pot": 40, "ten": 30}
## Each boss's own uniques (Game._boss_loot: the first kill always drops one, then bad-luck protection).
const BOSS_LOOT := {
	"goblin_king": ["cinderbrand", "skullsplitter", "bloodweave"],
	"champion": ["stormstride", "wardens_wall", "ninth_sun"],
	"bear": ["mire_heart", "bloodweave"],
	"sloth_fire": ["emberfang", "ninth_sun"],
	"sloth_ice": ["wardens_wall", "mire_heart"],
	"sloth_storm": ["stormstride", "skullsplitter"],
	"ice_troll": ["veil_locket"],
	"hermit": ["veil_locket"],
}
## The uniques' signature effects (the items rework): one per unique, everywhere (not only in a raid); two items
## with the same effect don't stack, the stronger counts (Hero.recalc). roll: a free dodge roll every N s; ward: N% of
## life as a shield that refills out of combat; burn: weapon blows set foes burning for N% of the blow a second for
## 3 s; chill: weapon blows slow foes by N% for 2 s; kill_heal: N% of life back on a kill; dash: N% faster for 2 s
## after a dodge roll.
const ITEM_EFFECTS := ["roll", "ward", "burn", "chill", "kill_heal", "dash", "phial"]
## The utility affixes: at most one of them on an item.
const UTILITY := ["frw", "stam", "cdr", "pot", "ten"]
## Rares roll this many affixes at most (magic items 1-2).
const RARE_AFFIXES := [2, 3]

## The Battlegrounds on top of that (Hero.pvp_scaled): the same items (the shares are 1 since the rework; they're
## the knobs if a raid needs gear to count for less than PvE), percentages under PVP_GEAR_CAP, act multipliers
## ignored (the weapon at its Act I strength).
const PVP_GEAR_SHARE := 1.0
const PVP_ARMOR_SHARE := 1.0
const PVP_GEAR_FLAT := ["str", "dex", "vit", "ene", "life", "mana", "fire", "dmg", "regen"]
const PVP_GEAR_CAP := {"res": 15, "ls": 4, "ias": 20, "frw": 5, "block": 15, "ed": 15}

## Class against class in PvP (the raid's pvp hits, Battlegrounds.pvp_hit, and the sandbox's, Enemy.take_damage):
## what a class deals to another player, and what it takes from one, tuned with tools/duel_sim.gd (bot duels at
## level 20, geared, every pairing). Only player-against-player blows; monsters and PvE are untouched.
const PVP_CLASS := {
	# [at level 1, at level 20] (straight between); a single number holds at every level
	"wraith": {"dmg": [0.85, 0.75], "taken": [1.05, 1.2]},
	"doug": {"dmg": [1.0, 1.25], "taken": [0.9, 0.85]},
	"warlock": {"dmg": [1.25, 1.35], "taken": [0.88, 0.85]},
	"plague": {"dmg": [0.7, 1.4], "taken": [1.1, 0.9]},
	"demon": {"dmg": [1.25, 1.35], "taken": 1.0},
	"knight": {"dmg": [1.05, 1.0], "taken": [0.9, 1.0]},
	"archer": {"dmg": [0.9, 0.8], "taken": 1.0},
}

static func _pvp_k(cls: String, key: String, level: int) -> float:
	var v = PVP_CLASS.get(cls, {}).get(key, 1.0)
	if v is Array:
		return lerpf(float(v[0]), float(v[1]), clampf((level - 1) / 19.0, 0.0, 1.0))
	return float(v)

static func pvp_scale(attacker_cls: String, target_cls: String, attacker_lvl := 20, target_lvl := 20) -> float:
	return _pvp_k(attacker_cls, "dmg", attacker_lvl) * _pvp_k(target_cls, "taken", target_lvl)

## A hero's weapon damage (Hero.recalc): the level's (about the best base a character of that level could wield),
## times the weapon's quality, 0.9 (a base far below the level) to 1.05 (the best there is) by its base damage against
## it (an A2/A3 weapon's base damage over its act multiplier `power`); then the weapon's Enhanced Damage and +Damage,
## and `mult` (its act strength; 1 in a raid; < 0 = `power`).
static func weapon_damage(level: int, base_wd: Array, power: float, ed: int, flat: int, mult := -1.0) -> Array:
	var lo := 2.5 + 0.55 * level
	var hi := 6.0 + 0.95 * level
	var q := clampf((float(base_wd[0]) + float(base_wd[1])) / maxf(0.01, power) / (lo + hi), 0.0, 1.0)
	var m := (0.9 + 0.15 * q) * (power if mult < 0.0 else mult) * (1.0 + ed / 100.0)
	return [maxi(1, int(round(lo * m)) + flat), maxi(2, int(round(hi * m)) + flat)]

## (kept for tools/pvp_sim.gd and pvp_items_test: the raid's weapon damage of a plain weapon)
static func pvp_damage(level: int, wd: Array) -> Array:
	return weapon_damage(level, wd, 1.0, 0, 0)

static func skill_locked(sk: Dictionary, level: int) -> bool:
	return not SKILLS_UNLOCKED and not sk.is_empty() and level < int(sk.get("lvl", 1))

static func skill_def(id: String) -> Dictionary:
	for s in SKILLS:
		if s["id"] == id:
			return s
	for s in RUN_SKILLS:
		if s["id"] == id:
			return s
	for s in COMMON_SKILLS:
		if s["id"] == id:
			return s
	return {}

static func xp_for_level(lvl: int) -> int:
	return int(round(120.0 * pow(float(lvl), 1.75) + 60.0 * lvl))

static func zone_level(act: int, _kind: String) -> int:
	return int(ACTS[act]["lvl"])
