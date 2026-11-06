class_name Camps
extends RefCounted
## Camps: the Battlegrounds' encounters (Blaine's overhaul, 2026-11-06). A camp is a place, a tier (1-3, 4 = a
## boss), the monsters that belong to it and a chest that stays sealed until every one of them is dead. Its monsters
## carry the camp's pack id (Enemy.pack_id), so completion counts who belongs to it, wherever they wander or die, and
## a camp never mixes with a neighbour's monsters. Clearing one unseals its chest: the first to open it rolls its gear
## and potions for everyone (the host), and each run character takes its own upgrade from it (RunUI.open_offer, one
## of three, once). A map lists its camps with `add`; the encounter (who and how many) can be swapped without
## touching the place.
## Every peer works completion out from the monsters it has (Enemy.die_visual -> Game.camp_check), as boss seals do;
## the host's word decides the chest (Net.sv_inter refuses a sealed one).

## A tier's monster level (their life and damage) and its chest's loot rolls.
const MON_LEVEL := {1: 1, 2: 5, 3: 10, 4: 15}
const CHEST_ROLLS := {1: 2, 2: 2, 3: 3, 4: 4}
## A chest's chance of a class unique for someone in the raid (Game._run_class_unique)
const UNIQUE_CHANCE := {3: 0.25, 4: 1.0}
const TIER_NAMES := {1: "Tier I", 2: "Tier II", 3: "Tier III", 4: "Boss"}
## A boss camp's boss against a run character (bosses are tuned for the whole act's heroes): its life and damage
## scaled, so a level-15 run character with a fair build can take it alone in about a minute, and a party faster.
## Measured with tools/run_playthrough.gd.
const BOSS_LIFE := 0.45
const BOSS_DMG := 0.33
## and its experience (a boss's own is the whole act's worth: six levels at once in a run)
const BOSS_XP := 0.35
## How near a hero must be when a camp falls to share its experience (the fighters, not the whole map).
const SHARE_R := 30.0
const FIRST_PACK := 2000      # (clear of every map's own pack numbers)

## Add a camp to a map being built: its monsters (`foes`: [{kind, count, champ?, at: offset from `pos`}]) join
## w.enemy_spawns at the tier's level under the camp's own pack id, and its chest stands at `chest` (an offset).
static func add(w: World, id: String, title: String, tier: int, pos: Vector3, r: float, foes: Array, chest := Vector3(0, 0, -2.5)) -> Dictionary:
	tier = clampi(tier, 1, 4)
	var list: Array = w.get_meta("camps") if w.has_meta("camps") else []
	var pack := FIRST_PACK + list.size()
	var camp := {"id": id, "name": title, "tier": tier, "pos": pos, "r": r, "pack": pack, "cleared": false}
	for f in foes:
		var at: Vector3 = f.get("at", Vector3.ZERO)
		var boss: bool = bool(Data.ENEMIES.get(str(f["kind"]), {}).get("boss", false))
		w.enemy_spawns.append({"kind": str(f["kind"]), "pos": pos + at, "count": int(f.get("count", 1)),
			"champ": bool(f.get("champ", false)), "pack": pack, "level": int(f.get("level", MON_LEVEL[tier])),
			"life_k": float(f.get("life_k", BOSS_LIFE if boss else 1.0)), "dmg_k": float(f.get("dmg_k", BOSS_DMG if boss else 1.0)),
			"xp_k": float(f.get("xp_k", BOSS_XP if boss else 1.0))})
	var ch := w._chest(pos + chest)
	if ch != null:
		ch.data["camp"] = id
		ch.data["tier"] = tier
		ch.label = "%s chest" % title
		camp["chest_node"] = ch
	list.append(camp)
	w.set_meta("camps", list)
	return camp

static func all(w: World) -> Array:
	return w.get_meta("camps") if w != null and w.has_meta("camps") else []

static func by_id(w: World, id: String) -> Dictionary:
	for c in all(w):
		if c["id"] == id:
			return c
	return {}

static func by_pack(w: World, pack: int) -> Dictionary:
	for c in all(w):
		if int(c["pack"]) == pack:
			return c
	return {}

## The camp's monsters still standing on this peer.
static func alive(w: World, camp: Dictionary) -> int:
	if camp.is_empty() or w == null:
		return 0
	var n := 0
	for e in w.enemies_root.get_children():
		if e is Enemy and not e.dead and e.pack_id == int(camp["pack"]):
			n += 1
	return n

## The camp a point is in (the nearest whose radius holds it), or {}.
static func at(w: World, p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for c in all(w):
		var d := Vector2(p.x - c["pos"].x, p.z - c["pos"].z).length()
		if d < float(c["r"]) and d < bd:
			bd = d
			best = c
	return best

## The run's offer key for a camp: the camp and the raid's round, so a camp's upgrade is one per round.
static func offer_key(g, camp: Dictionary) -> String:
	return "%s@%s" % [camp["id"], str(g.bg_raid.get("round", 0)) if g.bg_raid is Dictionary else "0"]
