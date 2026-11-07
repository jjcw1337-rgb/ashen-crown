class_name Camps
extends RefCounted
## Camps: a map's encounters (the Verdant Reach's are its CAMPS table). A camp is a place, a tier (1-3, 4 = a
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
const BOSS_LIFE := 0.8
const BOSS_DMG := 0.4
## and its experience (a boss's own is the whole act's worth: six levels at once in a run)
const BOSS_XP := 0.35
## How near a hero must be when a camp falls to share its experience (the fighters, not the whole map).
const SHARE_R := 30.0
const FIRST_PACK := 2000      # (clear of every map's own pack numbers)

## The colours of a camp chest's opening (Game.chest_lid, _burst_seals): its lid's light, the sparks at its hasp and
## its seals' flash, sparks and trails.
const CHEST_COLS := {"lid": Color(1.0, 0.5, 0.2), "spark": Color(0.95, 0.42, 0.08, 1.0), "flash": Color(1.0, 0.42, 0.1),
		"jet": [Color(1.0, 0.72, 0.3, 1.0), Color(0.95, 0.38, 0.06, 0.9), Color(0.35, 0.06, 0.02, 0.0)],
		"ring": Color(0.7, 0.2, 0.03), "burst": Color(0.9, 0.3, 0.04, 1.0), "fire": "brazier", "fire_col": Color(1.0, 0.5, 0.18), "pal": "",
		"seal": Color(1.0, 0.62, 0.18), "seal_light": Color(1.0, 0.68, 0.25), "seal_flash": Color(1.0, 0.62, 0.2),
		"seal_spark": Color(1.0, 0.75, 0.3, 1.0), "seal_trail": Color(0.95, 0.55, 0.12)}

static func chest_col(key: String):
	return CHEST_COLS[key]

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

## The leash (on whoever runs the monsters: the raid server, a host, a solo game): a camp's monster dragged more than
## LEASH metres past its camp's edge with no hero within LEASH_CLEAR goes home whole, so a camp is never left with a
## straggler no one can reach, and a pulled camp resets like an MMO's. Checked every LEASH_EVERY seconds.
const LEASH := 14.0
const LEASH_CLEAR := 12.0
const LEASH_EVERY := 1.0
static var _leash_t := 0.0

static func leash(g, delta: float) -> void:
	_leash_t -= delta
	if _leash_t > 0.0 or g.world == null or not g.world.has_meta("camps"):
		return
	_leash_t = LEASH_EVERY
	var heroes: Array = g.all_heroes() if g.has_method("all_heroes") else [g.hero]
	for c in all(g.world):
		if c["cleared"]:
			continue
		var cp: Vector3 = c["pos"]
		for e in g.world.enemies_root.get_children():
			if not (e is Enemy) or e.dead or e.pack_id != int(c["pack"]) or e.boss:
				continue
			if Vector2(e.global_position.x - cp.x, e.global_position.z - cp.z).length() < float(c["r"]) + LEASH:
				continue
			var near := false
			for h in heroes:
				if is_instance_valid(h) and not h.dead and h.global_position.distance_to(e.global_position) < LEASH_CLEAR:
					near = true
					break
			if near:
				continue
			var back: Vector3 = g.world.free_spot_near(e.home if e.home != Vector3.ZERO else cp, 2.0)
			back.y = g.world.height_at(back.x, back.z)
			e.global_position = back
			e.life = e.max_life
			e.aggro = false
			e.atk_t = -1.0

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
