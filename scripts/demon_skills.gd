class_name DemonSkills
extends RefCounted
## The Demon's skills: their casts, the frames their blows land on, what runs every frame (the lava he leaves on the
## ground, the fissures, the meteors, the foe in his grip) and their state on the hero (`Hero.dm`, cleared by `clear`).
## Hero.use_skill, _impact and _process call in. Every skill is a whole-body clip of his (Demon.SHOTS: the clip and
## how the attack's progress 0..1 maps onto its seconds, so the blow lands on Anim.impact_at's frame). Nothing here
## draws: every effect is an fx event (`Hero.fx`, SkillFx) that DemonFx plays on his own game and on his puppet on
## every partner's; the damage, the burning, the stuns and his own movement stay here, on the caster's game.
##  - Molten Fists (Q, "fists"): the two-fisted punch; the ground cracks open ahead of him (a wedge of FISTS_R) and
##    everything in it is hit and set alight.
##  - Infernal Charge (E, "icharge"): the head-down charge up to CHARGE_RANGE at CHARGE_SPEED; everything in his
##    way is bowled aside (damage, a knockback, a short stun), and his hooves leave a trail of lava (TRAIL_DUR s,
##    ticking on whoever stands in it).
##  - Cataclysm Slam (R, "cslam"): the ground slam: a ring round the blow, then FISSURES magma fissures race out
##    ahead in a fan and, FISSURE_DELAY later, erupt along their length in waves of lava bursts.
##  - Brimstone Hurl (F, "hurl"): a molten boulder torn out of the ground and thrown at the aim point: it lands
##    HURL_FLIGHT s later, splashes over HURL_R (damage, a knockback, fire) and leaves a lava pool (POOL_DUR s).
##  - Hellgrip (G, "grip"): the foe ahead is seized (GRIP_RANGE), lifted through the clip's hold and smashed into
##    the ground: his heaviest single blow, it burns, and a shockwave (GRIP_SHOCK_R) hits whoever stands round it.
##  - Wrath of the Pit (V, "wrath"): the ultimate, two stages chained as attacks: the roar (wings wide, his cracks
##    going white-hot; terror round him) and the stomp (a ring of lava), then for WRATH_DUR s meteors fall on the
##    foes round him (one every WRATH_EVERY s, WRATH_R out) while he fights on with +40% damage.

## Each attack's length in seconds (before Data.ATTACK_PACE; Molten Fists also by attack speed)
## Molten Fists is a heavy blow the Path of Exile way (jj, 2026-11-01): no cooldown, a 2 s use time (1.67 x the pace 1.2)
## with a 1.5 s wind-up the foes can read, and double the damage of a quick punch; the dodge roll cancels it.
const DUR := {"fists": 1.67, "icharge": 0.75, "cslam": 1.2, "hurl": 1.1, "grip": 1.7, "wrath_roar": 1.3, "wrath_stomp": 0.8}
## The attack style each skill starts with
const STYLE := {"fists": "fists", "icharge": "icharge", "cslam": "cslam", "hurl": "hurl", "grip": "grip", "wrath": "wrath_roar"}
const WRATH_STAGES := ["wrath_roar", "wrath_stomp"]
## Old saves: the skills these replaced, so their bindings carry over
const OLD_IDS := {"hellclaw": "fists", "summon": "icharge", "phase": "cslam", "pact": "hurl"}

const FISTS_R := 3.4           # how far ahead the cracks reach
const FISTS_HALF := 42.0       # half the wedge's angle (degrees)
const CHARGE_RANGE := 9.0
const CHARGE_SPEED := 16.0
const CHARGE_HIT_R := 1.9
const TRAIL_STEP := 1.1        # a lava patch every so far along the charge
const TRAIL_DUR := 4.0
const TRAIL_R := 1.3
const HAZARD_TICK := 0.4
const SLAM_R := 3.0
const FISSURES := 5
const FISSURE_LEN := 8.0
const FISSURE_HALF := 55.0     # the fan's half-angle (degrees)
const FISSURE_DELAY := 0.55    # from the slam to the first eruption
const FISSURE_WAVE := 0.12     # between the eruptions along a fissure
const FISSURE_STEP := 1.5      # between bursts along a fissure
const FISSURE_R := 1.7
const HURL_RANGE := 12.0
const HURL_FLIGHT := 0.6
const HURL_R := 2.6
const POOL_DUR := 5.0
const POOL_R := 2.2
const GRIP_RANGE := 3.6
const GRIP_SHOCK_R := 2.6
const GRIP_LIFT := 2.1         # how high the victim is held
const WRATH_DUR := 7.0
const WRATH_EVERY := 0.45
const WRATH_R := 9.0
const WRATH_FALL := 0.55       # a meteor's time in the air
const METEOR_R := 2.3
const ROAR_R := 6.0

static func active(h: Hero) -> bool:
	return h.is_demon()

## The magma in his blows: a part by level on top of the weapon (the same curve as the other classes' spells), so
## the skills keep their weight while the weapon is still small. k is the skill's share of it.
static func magma(h: Hero, k: float) -> float:
	return (16.0 + h.level * 4.5 + (h.dmg_min + h.dmg_max) * 0.35) * k

## Can he be told to walk right now? The charge, the slam, the throw, the grip and the wrath's stages root him.
static func rooted(h: Hero) -> bool:
	return h.atk_t >= 0.0 and h.atk_skill in ["icharge", "cslam", "hurl", "grip", "wrath"]

## The foe Hellgrip seizes: the nearest in the arc ahead within GRIP_RANGE (the one aimed at first).
static func grip_pick(h: Hero, aim: Vector3):
	var best = null
	var bd := 99.0
	var fwd := (aim - h.global_position) * Vector3(1, 0, 1)
	fwd = fwd.normalized() if fwd.length() > 0.3 else h.aim_dir()
	for e in h.game.enemies_near(h.global_position, GRIP_RANGE + 1.0):
		var to: Vector3 = e.global_position - h.global_position
		to.y = 0
		var d: float = to.length() - e.radius
		if d > GRIP_RANGE:
			continue
		if to.length() > 0.5 and fwd.dot(to.normalized()) < cos(deg_to_rad(70.0)):
			continue
		var score: float = d + Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length() * 0.5
		if score < bd:
			bd = score
			best = e
	return best

## ClassSkills: Hellgrip needs a foe to seize before anything is spent.
static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	if id == "grip" and grip_pick(h, aim) == null:
		h.game.ui.message("No enemy in reach", Color(0.8, 0.8, 0.8))
		return false
	return true

static func _start(h: Hero, style: String, skill: String) -> void:
	h._start_attack(style, skill)
	var d: float = DUR[style] * Data.attack_pace(h.cls)
	if skill == "fists":
		d /= h.aspd
	h.atk_dur = d
	h.moving = false
	h.path = PackedVector3Array()

# ---------------------------------------------------------------- casts
static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var w: Dictionary = h.dm
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	match id:
		"fists":
			_start(h, "fists", "fists")
		"icharge":
			var dir := to.normalized() if to.length() > 0.5 else h.aim_dir()
			w["charge"] = {"dir": dir, "a": 0.0, "dist": minf(maxf(to.length(), 3.0), CHARGE_RANGE), "hit": {}, "laid": 0.0, "ps": PackedVector3Array()}
			_start(h, "icharge", "icharge")
			h.fx("icharge", "start", {"d": dir})
		"cslam":
			_start(h, "cslam", "cslam")
		"hurl":
			var at := h.global_position + to.limit_length(HURL_RANGE)
			if to.length() < 1.5:
				at = h.global_position + h.aim_dir() * 4.0
			at.y = h.game.world.height_at(at.x, at.z)
			w["hurl_at"] = at
			_start(h, "hurl", "hurl")
		"grip":
			w["grip_victim"] = grip_pick(h, aim)
			w["grip_held"] = false
			_start(h, "grip", "grip")
		"wrath":
			end_wrath(h, false)
			w["wrath"] = {"stage": 0, "t": 0.0, "rain": -1.0, "next": 0.0, "n": 0}
			_start(h, "wrath_roar", "wrath")

# ---------------------------------------------------------------- the blows
## Called from Hero._impact on the attack's impact frame; true when it was one of his.
static func impact(h: Hero) -> bool:
	if not active(h):
		return false
	var w: Dictionary = h.dm
	match h.atk_skill:
		"fists":
			var fwd := h.aim_dir()
			var wide := h.talent("fists_wide") > 0.0
			var reach := FISTS_R + (1.0 if wide else 0.0)
			var lit := []
			for e in h.game.enemies_near(h.global_position, reach + 1.2):
				var to: Vector3 = e.global_position - h.global_position
				to.y = 0
				if to.length() - e.radius > reach:
					continue
				if to.length() < 0.6 or fwd.dot(to.normalized()) > cos(deg_to_rad(FISTS_HALF + (12.0 if wide else 0.0))):
					h._hit_enemy(e, 3.0, 0.5, "fists", magma(h, 0.5))
					if is_instance_valid(e) and not e.dead:
						e.ignite(magma(h, 0.24) * h.dmg_mult("fists"), 6.0 if wide else 3.0)
						lit.append(e)
			h.fx("fists", "impact", {"y": h.rig.global_rotation.y, "r": reach, "t": lit})
		"icharge":
			pass      # the charge itself moves and hits in update
		"cslam":
			var at := h.global_position + h.aim_dir() * 1.2
			at.y = h.game.world.height_at(at.x, at.z)
			var any := false
			for e in h.game.enemies_near(at, SLAM_R + 1.0):
				var to: Vector3 = e.global_position - at
				to.y = 0
				if to.length() - e.radius <= SLAM_R:
					h._hit_enemy(e, 1.6, 0.8, "cslam", magma(h, 0.8))
					if is_instance_valid(e) and not e.dead:
						e.stun(0.8)
					any = true
			# the fissures race out ahead in a fan; their eruptions come in waves (update)
			var fwd := h.aim_dir()
			var lines: Array = []
			var ps := PackedVector3Array()
			for i in FISSURES:
				var ang := deg_to_rad(-FISSURE_HALF + 2.0 * FISSURE_HALF * float(i) / (FISSURES - 1))
				var dir := fwd.rotated(Vector3.UP, ang)
				var pts := PackedVector3Array()
				var p := at
				var k := 0
				while k * FISSURE_STEP < FISSURE_LEN:
					var q: Vector3 = h.game.world.move(p, dir * FISSURE_STEP, 0.3)
					var moved := q - p
					moved.y = 0
					if moved.length() < FISSURE_STEP * 0.4:
						break
					q.y = h.game.world.height_at(q.x, q.z)
					pts.append(q)
					p = q
					k += 1
				if pts.is_empty():
					continue
				lines.append({"pts": pts, "hit": {}})
				ps.append_array(pts)
			w["fissures"] = {"lines": lines, "t": 0.0, "wave": 0, "next": FISSURE_DELAY}
			h.fx("cslam", "impact", {"p": at, "y": h.rig.global_rotation.y, "ps": ps, "n": lines.size(), "x": any})
			SkillFx.hitstop(h, 0.05 if any else 0.0)
		"hurl":
			var at: Vector3 = w.get("hurl_at", h.global_position + h.aim_dir() * 4.0)
			var hand := SkillFx.hand(h, true) if h.rig != null else h.global_position + Vector3(0, 1.8, 0)
			var twin := h.talent("hurl_twin") > 0.0
			var targets: Array = [at]
			if twin:
				var side := h.aim_dir().rotated(Vector3.UP, PI * 0.5) * 2.2
				var at2 := at + side
				at2.y = h.game.world.height_at(at2.x, at2.z)
				targets.append(at2)
			var flight := HURL_FLIGHT + at.distance_to(h.global_position) * 0.03
			var bs: Array = w.get("boulders", [])
			for t in targets:
				bs.append({"at": t, "t": flight})
			w["boulders"] = bs
			var ps := PackedVector3Array()
			for t in targets:
				ps.append(t)
			h.fx("hurl", "throw", {"p": hand, "ps": ps, "x": flight})
		"grip":
			_grip_smash(h)
		"wrath":
			_wrath_impact(h)
		_:
			return false
	return true

## Hellgrip's smash: the held foe is driven into the ground and set alight; a shockwave hits the rest.
static func _grip_smash(h: Hero) -> void:
	var w: Dictionary = h.dm
	var v = w.get("grip_victim")
	var at := h.global_position + h.aim_dir() * 1.6
	at.y = h.game.world.height_at(at.x, at.z)
	var held: bool = v != null and is_instance_valid(v) and not v.dead
	if held:
		at = v.global_position
		h._hit_enemy(v, 3.2, 0.3, "grip", magma(h, 1.6))
		if is_instance_valid(v) and not v.dead:
			v.ignite(magma(h, 0.2) * h.dmg_mult("grip"), 4.0)
			v.stun(0.6)
	for e in h.game.enemies_near(at, GRIP_SHOCK_R + 0.8):
		if e == v:
			continue
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius <= GRIP_SHOCK_R:
			h._hit_enemy(e, 0.7, 1.5, "grip", magma(h, 0.4))
	w["grip_held"] = false
	h.fx("grip", "smash", {"p": at, "t": [v] if held else [], "x": held})
	if held:
		SkillFx.hitstop(h, 0.07)

# ---------------------------------------------------------------- Wrath of the Pit
static func wrath_active(h: Hero) -> bool:
	return h.dm.has("wrath")

static func end_wrath(h: Hero, finished: bool) -> void:
	var w: Dictionary = h.dm
	if not w.has("wrath"):
		return
	w.erase("wrath")
	h.fx("wrath", "end", {"x": finished})

static func _wrath_impact(h: Hero) -> void:
	var w: Dictionary = h.dm
	if not w.has("wrath"):
		return
	match h.atk_style:
		"wrath_roar":
			# the terror: everything near him is hurt, thrown back and frozen
			h.fx("wrath", "roar")
			for e in h.game.enemies_near(h.global_position, ROAR_R):
				h._hit_enemy(e, 1.0, 1.8, "wrath", magma(h, 0.8))
				if is_instance_valid(e) and not e.dead:
					e.stun(1.5)
		"wrath_stomp":
			# the stomp: a ring of lava, and the rain begins
			var at := h.global_position
			h.buff_t = 8.0 + h.talent("buff_dur")
			var n: Dictionary = w["wrath"]
			n["rain"] = WRATH_DUR + h.talent("wrath_dur")
			n["next"] = 0.3
			h.fx("wrath", "stomp", {"x": float(n["rain"])})
			for e in h.game.enemies_near(at, 4.5):
				var to: Vector3 = e.global_position - at
				to.y = 0
				if to.length() - e.radius <= 4.0:
					h._hit_enemy(e, 1.2, 1.0, "wrath", magma(h, 0.6))

## A meteor: aimed at a foe within WRATH_R (the one struck least recently), else at a spot near him; the strike
## is dealt when it lands. Partners get the same spot in the event, so the sky and the crater agree everywhere.
static func _call_meteor(h: Hero) -> void:
	var w: Dictionary = h.dm
	var n: Dictionary = w["wrath"]
	var foes: Array = h.game.enemies_near(h.global_position, WRATH_R)
	var at: Vector3
	if foes.is_empty():
		var ang := randf() * TAU
		var r := randf_range(2.5, WRATH_R * 0.7)
		at = h.global_position + Vector3(cos(ang) * r, 0, sin(ang) * r)
	else:
		var last: Dictionary = n.get("last", {})
		foes.sort_custom(func(a, b) -> bool: return float(last.get(a.get_instance_id(), -9.0)) < float(last.get(b.get_instance_id(), -9.0)))
		var pick = foes[0]
		last[pick.get_instance_id()] = float(n["t"])
		n["last"] = last
		at = pick.global_position + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	at.y = h.game.world.height_at(at.x, at.z)
	var k: int = int(n["n"])
	n["n"] = k + 1
	var ms: Array = w.get("meteors", [])
	ms.append({"at": at, "t": WRATH_FALL})
	w["meteors"] = ms
	h.fx("wrath", "meteor", {"p": at, "n": k, "x": WRATH_FALL})

static func _meteor_land(h: Hero, at: Vector3) -> void:
	for e in h.game.enemies_near(at, METEOR_R + 0.8):
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius <= METEOR_R:
			h._hit_enemy(e, 1.1, 1.2, "wrath", magma(h, 0.55))
			if is_instance_valid(e) and not e.dead:
				e.ignite(magma(h, 0.1) * h.dmg_mult("wrath"), 3.0)

# ---------------------------------------------------------------- every frame
static func update(h: Hero, delta: float) -> void:
	if not active(h):
		return
	var w: Dictionary = h.dm
	var a: float = (h.atk_t / h.atk_dur) if h.atk_t >= 0.0 else -1.0
	# Infernal Charge: he goes through the wind-up's end and the clip, laying lava, bowling foes aside
	if w.has("charge"):
		_update_charge(h, a, delta)
	# Hellgrip: the foe is seized a quarter of the way in and held up until the smash
	if a >= 0.0 and h.atk_skill == "grip":
		if a >= 0.25 and not bool(w.get("grip_held", false)) and a < Anim.impact_at("grip"):
			w["grip_held"] = true
			var v = w.get("grip_victim")
			if v == null or not is_instance_valid(v) or v.dead:
				v = grip_pick(h, h.aim_ahead(GRIP_RANGE))
				w["grip_victim"] = v
			if v != null:
				v.stun(2.0)
				h.fx("grip", "grab", {"t": [v], "x": (Anim.impact_at("grip") - 0.25) * h.atk_dur})
			else:
				h.fx("grip", "grab", {"t": [], "x": 0.0})
	elif w.has("grip_victim") and h.atk_t < 0.0:
		w.erase("grip_victim")
	# boulders in the air land where they were thrown
	if w.has("boulders"):
		var bs: Array = w["boulders"]
		for b in bs.duplicate():
			b["t"] = float(b["t"]) - delta
			if float(b["t"]) <= 0.0:
				bs.erase(b)
				_splash(h, b["at"])
		if bs.is_empty():
			w.erase("boulders")
	# the fissures erupt in waves out from the slam
	if w.has("fissures"):
		var f: Dictionary = w["fissures"]
		f["next"] = float(f["next"]) - delta
		if float(f["next"]) <= 0.0:
			var wave: int = int(f["wave"])
			var ps := PackedVector3Array()
			var more := false
			for ln in f["lines"]:
				var pts: PackedVector3Array = ln["pts"]
				if wave < pts.size():
					more = true
					var p: Vector3 = pts[wave]
					ps.append(p)
					for e in h.game.enemies_near(p, FISSURE_R + 0.8):
						if (ln["hit"] as Dictionary).has(e.get_instance_id()):
							continue
						var to: Vector3 = e.global_position - p
						to.y = 0
						if to.length() - e.radius <= FISSURE_R:
							ln["hit"][e.get_instance_id()] = true
							h._hit_enemy(e, 1.1, 0.9, "cslam", magma(h, 0.5))
							if is_instance_valid(e) and not e.dead:
								e.ignite(magma(h, 0.08) * h.dmg_mult("cslam"), 2.5)
			if not ps.is_empty():
				h.fx("cslam", "erupt", {"ps": ps, "n": wave})
			f["wave"] = wave + 1
			f["next"] = FISSURE_WAVE
			if not more:
				w.erase("fissures")
	# the lava on the ground (the charge's trail, the boulders' pools) burns whoever stands in it
	if w.has("lava"):
		var lv: Array = w["lava"]
		for patch in lv.duplicate():
			patch["t"] = float(patch["t"]) - delta
			patch["tick"] = float(patch["tick"]) - delta
			if float(patch["t"]) <= 0.0:
				lv.erase(patch)
				continue
			if float(patch["tick"]) > 0.0:
				continue
			patch["tick"] = HAZARD_TICK
			var p: Vector3 = patch["p"]
			var r: float = patch["r"]
			for e in h.game.enemies_near(p, r + 0.8):
				var to: Vector3 = e.global_position - p
				to.y = 0
				if to.length() - e.radius * 0.5 <= r:
					e.take_damage(0.0, magma(h, 0.2) * h.buff_mult() * h.dmg_mult(str(patch["s"])), p, 0.0, false)
		if lv.is_empty():
			w.erase("lava")
	# meteors in the air
	if w.has("meteors"):
		var ms: Array = w["meteors"]
		for m in ms.duplicate():
			m["t"] = float(m["t"]) - delta
			if float(m["t"]) <= 0.0:
				ms.erase(m)
				_meteor_land(h, m["at"])
		if ms.is_empty():
			w.erase("meteors")
	_update_wrath(h, delta)

## The charge: from a little into the attack to its end he covers the distance at CHARGE_SPEED (less where
## something solid stops him), bowling foes aside and laying lava every TRAIL_STEP.
static func _update_charge(h: Hero, a: float, delta: float) -> void:
	var w: Dictionary = h.dm
	var c: Dictionary = w["charge"]
	if a < 0.0 or h.atk_skill != "icharge" or h.dead:
		w.erase("charge")
		_lay_trail(h, c, true)
		h.fx("icharge", "end")
		return
	var t0 := 0.1
	var t1 := 0.85
	var f0 := clampf((float(c["a"]) - t0) / (t1 - t0), 0.0, 1.0)
	var f1 := clampf((a - t0) / (t1 - t0), 0.0, 1.0)
	c["a"] = a
	var d := (f1 - f0) * float(c["dist"])
	if d > 0.0:
		var dir: Vector3 = c["dir"]
		var np: Vector3 = h.game.world.move(h.global_position, dir * d, h.radius)
		var moved := np - h.global_position
		moved.y = 0
		h.global_position = np
		h._face(dir)
		c["laid"] = float(c["laid"]) + moved.length()
		if float(c["laid"]) >= TRAIL_STEP:
			c["laid"] = 0.0
			var p := h.global_position
			p.y = h.game.world.height_at(p.x, p.z)
			# (a PackedVector3Array is copied out of a Dictionary: append to a copy and put it back)
			var laid: PackedVector3Array = c["ps"]
			laid.append(p)
			c["ps"] = laid
			var lv: Array = w.get("lava", [])
			lv.append({"p": p, "r": TRAIL_R, "t": TRAIL_DUR + h.talent("trail_dur"), "tick": 0.3, "s": "icharge"})
			w["lava"] = lv
			if laid.size() % 2 == 0:
				_lay_trail(h, c, false)
		for e in h.game.enemies_near(h.global_position, CHARGE_HIT_R + 0.6):
			if (c["hit"] as Dictionary).has(e.get_instance_id()):
				continue
			var to: Vector3 = e.global_position - h.global_position
			to.y = 0
			if to.length() - e.radius <= CHARGE_HIT_R:
				c["hit"][e.get_instance_id()] = true
				h._hit_enemy(e, 1.2, 2.6, "icharge", magma(h, 0.5))
				if is_instance_valid(e) and not e.dead:
					e.stun(0.5)
				h.fx("icharge", "hit", {"p": e.global_position + Vector3(0, 0.8 * e.height, 0), "d": dir})
		if moved.length() < d * 0.3 and f1 < 1.0:
			# something solid: the charge ends here
			c["dist"] = 0.0
	if a >= t1 and not bool(c.get("done", false)):
		c["done"] = true
		_lay_trail(h, c, true)

## The lava patches laid since the last word go out to the fx (in twos, and whatever is left at the end).
static func _lay_trail(h: Hero, c: Dictionary, _final: bool) -> void:
	var ps: PackedVector3Array = c["ps"]
	if ps.is_empty():
		return
	h.fx("icharge", "trail", {"ps": ps, "x": TRAIL_DUR + h.talent("trail_dur")})
	c["ps"] = PackedVector3Array()

## A boulder lands: the splash and its pool.
static func _splash(h: Hero, at: Vector3) -> void:
	var lit := []
	for e in h.game.enemies_near(at, HURL_R + 0.8):
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius <= HURL_R:
			h._hit_enemy(e, 1.8, 1.2, "hurl", magma(h, 1.0))
			if is_instance_valid(e) and not e.dead:
				e.ignite(magma(h, 0.1) * h.dmg_mult("hurl"), 3.0)
				lit.append(e)
	var lv: Array = h.dm.get("lava", [])
	var dur := POOL_DUR + h.talent("trail_dur")
	lv.append({"p": at, "r": POOL_R, "t": dur, "tick": 0.5, "s": "hurl"})
	h.dm["lava"] = lv
	h.fx("hurl", "splash", {"p": at, "x": dur, "t": lit})
	SkillFx.hitstop(h, 0.05 if not lit.is_empty() else 0.0)

## The wrath's stages, chained as attacks; then the rain, which runs while he fights on.
static func _update_wrath(h: Hero, delta: float) -> void:
	var w: Dictionary = h.dm
	if not w.has("wrath"):
		return
	var n: Dictionary = w["wrath"]
	if h.dead:
		end_wrath(h, false)
		return
	n["t"] = float(n["t"]) + delta
	var stage: int = n["stage"]
	if stage < WRATH_STAGES.size():
		if h.atk_t >= 0.0 and h.atk_skill != "wrath":
			end_wrath(h, false)      # cut short by another skill
			return
		if h.atk_t < 0.0:
			stage += 1
			if stage < WRATH_STAGES.size():
				n["stage"] = stage
				_start(h, WRATH_STAGES[stage], "wrath")
			else:
				n["stage"] = stage
		return
	# the rain
	var rain: float = float(n["rain"])
	if rain <= 0.0:
		end_wrath(h, true)
		return
	n["rain"] = rain - delta
	n["next"] = float(n["next"]) - delta
	if float(n["next"]) <= 0.0:
		n["next"] = WRATH_EVERY
		_call_meteor(h)
		if h.talent("wrath_double") > 0.0:
			_call_meteor(h)

# ---------------------------------------------------------------- housekeeping
## Everything of his that lingers: the lava on the ground, fissures, boulders and meteors in the air, the grip,
## the wrath (a class change, a new character, a zone change, death).
static func clear(h: Hero) -> void:
	var w: Dictionary = h.dm
	end_wrath(h, false)
	if w.has("charge"):
		w.erase("charge")
		h.fx("icharge", "end")
	DemonFx.clear(h)
	if h.atk_t >= 0.0 and h.atk_skill in STYLE:
		h.atk_t = -1.0
		h.atk_skill = ""
	w.clear()

static func died(h: Hero) -> void:
	clear(h)

## His casts' sounds are played by his skills and effects themselves (DemonFx), none at the cast's start.
static func sound(_h: Hero, _skill: String, _at: float) -> bool:
	return false

## Old saves bound the skills these replaced: the binding carries over.
static func migrate_binds(binds: Dictionary) -> void:
	for k in binds.keys():
		var id := str(binds[k])
		if OLD_IDS.has(id):
			binds[k] = OLD_IDS[id]
