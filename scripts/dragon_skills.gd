class_name DragonSkills
extends RefCounted
## The dragon classes' skills (Obsidian Wyrm "wyrm", Frost Serpent "serpent", Storm Wyvern "wyvern"). The Storm
## Wyvern's Storm Arc (jj): it rears and breathes chain lightning from its jaws (SharedSkills.chain, WYVERN_JUMPS
## leaps; the look is ArcFx's, its wings crackling); the others have none yet.
## For now a dragon has only the common Attack (left mouse: the hero's three-swipe combo, which Dragon.pose shows as
## a foreclaw rake, a bite and a tail spin) and Block; this script plays their own sounds for the attack.
##
## Ready for skills (see CLAUDE.md "Adding a class"): add Data.SKILLS entries with "cls" set to the dragon's id and
## an "aim", then handle their ids below (cast -> h._start_attack(style, id, seconds); impact on Anim.impact_at of
## the style; state on the hero in one dictionary, e.g. `h.set_meta("drg", {...})` or a new `Hero.dg`); Dragon.pose
## already plays any unknown attack style as a roar with the wings flared, so a new skill animates before it has a
## pose of its own. Effects go in a DragonFx.play(h, ev) handler added to SkillFx.play's match.

static func is_mine(h: Hero) -> bool:
	return Dragon.is_dragon(h.cls)

static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	return true

const WYVERN_JUMPS := 4
## Frost Breath: its ticks while the jaws are open (of the breath's progress), every BREATH_TICK s
const BREATH_OPEN := Vector2(0.15, 0.9)
const BREATH_TICK := 0.2

## ---- the run-only skills (Data.RUN_SKILLS; a run's chests give them): the Frost Serpent's Glacial Tomb, Crushing Coil
## and Rime Lance, the Storm Wyvern's Thunder Dive, Thunderhead and Gale Wings. State in h's meta "drg"; what is seen
## is fx events (DragonRunFx).
const TOMB_T := 1.6          # sealed this long (bosses a third, Enemy.stun), then it shatters
const TOMB_R := 2.5          # those round the first foe are sealed with it
const TOMB_BURST := 3.0      # the shatter's reach
const COIL_R := 4.2
const LANCE_LEN := 10.0
const LANCE_W := 1.3
const DIVE_RANGE := 12.0
const DIVE_R := 4.0
const DIVE_FLY := Vector2(0.12, 0.8)    # of the dive's progress: off the ground .. down (the impact)
const CLOUD_T := 4.0
const CLOUD_R := 5.0
const CLOUD_EVERY := 0.5
const CLOUD_MAX := 2
const GALE_R := 6.5
const GALE_HALF := 40.0      # degrees either side

static func drg(h: Hero) -> Dictionary:
	if not h.has_meta("drg"):
		h.set_meta("drg", {"tombs": [], "clouds": [], "dive": {}})
	return h.get_meta("drg")

static func _alive(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead and e.pvp_obj == 0

static func _clamp_aim(h: Hero, aim: Vector3, reach: float) -> Vector3:
	var off := aim - h.global_position
	off.y = 0
	if off.length() > reach:
		aim = h.global_position + off.normalized() * reach
	aim.y = h.game.world.height_at(aim.x, aim.z)
	return aim

static func cast(h: Hero, id: String, _aim: Vector3) -> void:
	match id:
		"s_tomb", "v_cloud", "v_gale":
			h._start_attack("cast", id)
			h.moving = false
			h.path = PackedVector3Array()
			drg(h)["aim"] = _aim
			return
		"s_coil":
			h._start_attack("swipe3", id)
			return
		"s_lance":
			h._start_attack("breath", id)
			h.moving = false
			h.path = PackedVector3Array()
			return
		"v_dive":
			h._start_attack("dive", id)
			h.moving = false
			h.path = PackedVector3Array()
			var to := _clamp_aim(h, _aim, DIVE_RANGE)
			if h.game.world.is_blocked(to.x, to.z):
				to = h.game.world.free_spot_near(to, 1.5)
			drg(h)["dive"] = {"from": h.global_position, "to": to}
			h.fx("v_dive", "start", {"p": h.global_position, "q": to, "x": h.atk_dur})
			return
	if id == "storm_arc":
		h._start_attack("cast", id)
		h.moving = false
		h.path = PackedVector3Array()
	elif id == "frost_breath":
		h._start_attack("breath", id)
		h.moving = false
		h.path = PackedVector3Array()
		h.set_meta("breath_tick", 0.0)

static func impact(h: Hero) -> bool:
	if is_mine(h) and _run_impact(h):
		return true
	if is_mine(h) and h.atk_skill == "frost_breath":
		return true         # (its damage comes in ticks while it breathes: update)
	if not is_mine(h) or h.atk_skill != "storm_arc":
		return false
	var pts := SharedSkills.chain(h, "storm_arc", jaws(h), WYVERN_JUMPS)
	h.fx("storm_arc", "impact", {"ps": pts, "d": h.aim_dir()})
	return true

static func _run_impact(h: Hero) -> bool:
	var s := drg(h)
	var me := h.global_position
	match h.atk_skill:
		"s_tomb":
			var at := _clamp_aim(h, s.get("aim", me + h.aim_dir() * 6.0), 12.0)
			var first = null
			var bd := 3.5
			for e in h.game.enemies_near(at, 3.5):
				if _alive(e) and e.global_position.distance_to(at) < bd:
					bd = e.global_position.distance_to(at)
					first = e
			var sealed: Array = []
			if first != null:
				sealed.append(first)
				for e in h.game.enemies_near(first.global_position, TOMB_R * (1.0 + h.talent("tomb_r") / 100.0)):
					if _alive(e) and e != first and sealed.size() < 6:
						sealed.append(e)
			var secs := TOMB_T + h.talent("tomb_t")
			Hero.striker = h
			for e in sealed:
				e.stun(secs)
				e.chill(0.6, secs + 2.0)
			var c: Vector3 = first.global_position if first != null else at
			(s["tombs"] as Array).append({"p": c, "t": secs, "es": sealed})
			h.fx("s_tomb", "seal", {"p": c, "t": sealed, "x": secs})
		"s_coil":
			var r := COIL_R * (1.0 + h.talent("coil_r") / 100.0)
			var hit: Array = []
			for e in h.game.enemies_near(me, r):
				if not _alive(e):
					continue
				var chilled: bool = e.chill_t > 0.0
				h._hit_enemy(e, 1.3 * (1.3 if chilled else 1.0), 1.5, "s_coil")
				if not e.dead:
					Hero.striker = h
					e.slow(2.0, 0.45)
				hit.append(e)
			if hit.size() > 0 and h.talent("coil_shield") > 0.0:
				h.life = minf(h.max_life, h.life + h.max_life * h.talent("coil_shield") / 100.0 * mini(hit.size(), 5))
			h.fx("s_coil", "crush", {"p": me, "r": r, "t": hit})
		"s_lance":
			var d := h.aim_dir()
			var ln := LANCE_LEN * (1.0 + h.talent("lance_len") / 100.0)
			var hit2: Array = []
			for e in h.game.enemies_near(me + d * ln * 0.5, ln * 0.5 + 1.5):
				if not _alive(e):
					continue
				var to: Vector3 = e.global_position - me
				to.y = 0
				var along := to.dot(d)
				if along < -0.5 or along > ln + 0.5:
					continue
				if (to - d * along).length() > LANCE_W + float(e.radius):
					continue
				var was_chilled: bool = e.chill_t > 0.0
				h._hit_enemy(e, 1.25, 0.6, "s_lance")
				if not e.dead:
					if was_chilled:
						RunTalents._freeze(h, e, 1.0 + h.talent("lance_freeze"))
					else:
						Hero.striker = h
						e.chill(0.45, 3.0)
				hit2.append(e)
			h.fx("s_lance", "spikes", {"p": me, "d": d, "x": ln, "t": hit2})
		"v_dive":
			var dv: Dictionary = s["dive"]
			if not dv.is_empty():
				h.global_position = h.game.world.move(h.global_position, dv["to"] - h.global_position, h.radius)
			s["dive"] = {}
			var r2 := DIVE_R * (1.0 + h.talent("dive_r") / 100.0)
			var hit3: Array = []
			for e in h.game.enemies_near(h.global_position, r2):
				if not _alive(e):
					continue
				h._hit_enemy(e, 2.4, 2.5, "v_dive")
				if not e.dead:
					Hero.striker = h
					e.stun(0.8)
				hit3.append(e)
			h.fx("v_dive", "land", {"p": h.global_position, "r": r2, "t": hit3})
			if h.talent("dive_reset") > 0.0 and hit3.any(func(e): return e.dead):
				h.cds["v_dive"] = 0.0      # (Eye of the Storm)
		"v_cloud":
			var at2 := _clamp_aim(h, s.get("aim", me + h.aim_dir() * 6.0), 13.0)
			var clouds: Array = s["clouds"]
			while clouds.size() >= CLOUD_MAX:
				var old: Dictionary = clouds.pop_front()
				h.fx("v_cloud", "end", {"p": old["p"]})
			var secs2 := CLOUD_T + h.talent("cloud_t")
			clouds.append({"p": at2, "t": secs2, "tick": 0.25})
			h.fx("v_cloud", "form", {"p": at2, "x": secs2, "r": CLOUD_R})
		"v_gale":
			var d2 := h.aim_dir()
			var r3 := GALE_R * (1.0 + h.talent("gale_r") / 100.0)
			var hit4: Array = []
			for e in h.game.enemies_near(me, r3):
				if not _alive(e):
					continue
				var to2: Vector3 = e.global_position - me
				to2.y = 0
				if to2.length() > 1.2 and d2.dot(to2.normalized()) < cos(deg_to_rad(GALE_HALF)):
					continue
				h._hit_enemy(e, 1.0, 5.0, "v_gale")
				if not e.dead:
					Hero.striker = h
					e.slow(2.5, 0.4)
				hit4.append(e)
			h.fx("v_gale", "gust", {"p": me, "d": d2, "r": r3, "t": hit4})
		_:
			return false
	return true

## Every frame on the dragon's own game: the dive's flight, the tombs' shatter, the clouds' bolts.
static func _run_update(h: Hero, delta: float) -> void:
	if not h.has_meta("drg"):
		return
	var s := drg(h)
	var dv: Dictionary = s["dive"]
	if not dv.is_empty():
		if h.atk_skill == "v_dive" and h.atk_t >= 0.0:
			var a := clampf((h.atk_t / maxf(h.atk_dur, 0.01) - DIVE_FLY.x) / (DIVE_FLY.y - DIVE_FLY.x), 0.0, 1.0)
			var p: Vector3 = (dv["from"] as Vector3).lerp(dv["to"], smoothstep(0.0, 1.0, a))
			var step := p - h.global_position
			step.y = 0
			h.global_position = h.game.world.move(h.global_position, step, h.radius * 0.5)
		else:
			s["dive"] = {}
	var tombs: Array = s["tombs"]
	for i in range(tombs.size() - 1, -1, -1):
		var tb: Dictionary = tombs[i]
		tb["t"] = float(tb["t"]) - delta
		if float(tb["t"]) > 0.0:
			continue
		tombs.remove_at(i)
		var struck: Array = []
		var c: Vector3 = tb["p"]
		for e in tb["es"]:
			if _alive(e):
				h._hit_enemy(e, 1.8, 1.5, "s_tomb")
				struck.append(e)
				c = e.global_position if struck.size() == 1 else c
		for e in h.game.enemies_near(c, TOMB_BURST):
			if _alive(e) and not (tb["es"] as Array).has(e):
				h._hit_enemy(e, 0.9, 1.0, "s_tomb")
				struck.append(e)
		h.fx("s_tomb", "shatter", {"p": c, "r": TOMB_BURST, "t": tb["es"]})
	var clouds: Array = s["clouds"]
	for i in range(clouds.size() - 1, -1, -1):
		var cl: Dictionary = clouds[i]
		cl["t"] = float(cl["t"]) - delta
		cl["tick"] = float(cl["tick"]) - delta
		if float(cl["t"]) <= 0.0:
			clouds.remove_at(i)
			h.fx("v_cloud", "end", {"p": cl["p"]})
			continue
		if float(cl["tick"]) > 0.0:
			continue
		cl["tick"] = CLOUD_EVERY * (1.0 - h.talent("cloud_rate") / 100.0)
		var foes: Array = h.game.enemies_near(cl["p"], CLOUD_R).filter(func(e): return _alive(e))
		if foes.is_empty():
			continue
		var e = foes[randi() % foes.size()]
		h._hit_enemy(e, 0.45, 0.0, "v_cloud")
		if not e.dead and h.talent("cloud_stun") > 0.0 and randf() < h.talent("cloud_stun") / 100.0:
			Hero.striker = h
			e.stun(0.5)
		h.fx("v_cloud", "bolt", {"p": cl["p"], "q": e.global_position, "t": [e]})

## Where a dragon's breath leaves it: in front of its head.
static func jaws(h: Hero) -> Vector3:
	var J: Dictionary = h.rig.get_meta("j") if h.rig != null and h.rig.has_meta("j") else {}
	var hd = J.get("at_head", J.get("head"))
	if hd is Node3D and is_instance_valid(hd):
		return (hd as Node3D).global_position + h.facing() * 0.5
	return h.global_position + Vector3(0, 2.0, 0) + h.facing() * 1.2

## Frost Breath's ticks: cold damage and a chill on everything in the cone (SkillSpec: its "area" and "dot"), every
## BREATH_TICK s while the jaws are open. Only the breather's own game deals it (a puppet has no attack running).
static func update(h: Hero, delta: float) -> void:
	if not h.puppet and is_mine(h):
		_run_update(h, delta)
	if h.puppet or not is_mine(h) or h.atk_t < 0.0 or h.atk_skill != "frost_breath":
		return
	var a := h.atk_t / maxf(h.atk_dur, 0.001)
	if a < BREATH_OPEN.x or a > BREATH_OPEN.y:
		return
	var tk: float = float(h.get_meta("breath_tick", 0.0)) - delta
	if tk <= 0.0:
		tk = BREATH_TICK
		for e in SkillSpec.targets(h, "frost_breath"):
			SkillSpec.strike(h, "frost_breath", e)
	h.set_meta("breath_tick", tk)

static func rooted(_h: Hero) -> bool:
	return false

static func clear(h: Hero) -> void:
	if h.has_meta("drg"):
		h.remove_meta("drg")

static func died(h: Hero) -> void:
	if is_mine(h) and h.rig != null and h.rig.is_inside_tree():
		Sfx.play_at(h.cls + "_roar", h.global_position, -6.0, 0.8)    # a last roar under the death cry

## The basic attack's sounds, each landing on its impact frame: claw, bite, tail spin.
static func sound(h: Hero, skill: String, at: float) -> bool:
	if is_mine(h):
		match skill:
			"s_tomb":
				Sfx.play(h.cls + "_roar", -8.0, 1.1)
				Sfx.play_synced("ice_form", at, -1.0)
				return true
			"s_coil":
				Sfx.play_synced(h.cls + "_tail", at, -1.0, 0.85)
				Sfx.play(h.cls + "_roar", -10.0, 0.9)
				return true
			"s_lance":
				Sfx.play(h.cls + "_roar", -9.0, 1.2)
				Sfx.play_synced("frost_spread", at, -2.0, 1.1)
				return true
			"v_dive":
				Sfx.play(h.cls + "_roar", -6.0, 1.05)
				Sfx.play_synced("wyvern_dive", at, -1.0)
				return true
			"v_cloud":
				Sfx.play(h.cls + "_roar", -8.0, 0.9)
				Sfx.play_synced("sigil_charge", at, -4.0)
				return true
			"v_gale":
				Sfx.play_synced("wyvern_flap", at, -3.0, 0.75)
				Sfx.play(h.cls + "_roar", -9.0, 1.0)
				return true
	if is_mine(h) and skill == "storm_arc":
		Sfx.play(h.cls + "_roar", -8.0, 1.15)
		Sfx.play_synced("arc_zap", at, -2.0)
		return true
	if not is_mine(h) or skill != "":
		return false
	match h.atk_style:
		"swipe1":
			Sfx.play_synced(h.cls + "_claw", at, -2.0)
		"swipe2":
			Sfx.play_synced(h.cls + "_bite", at, -2.0)
		"swipe3":
			Sfx.play_synced(h.cls + "_tail", at, -1.0)
			Sfx.play(h.cls + "_roar", -12.0, 1.1)
		_:
			return false
	return true
