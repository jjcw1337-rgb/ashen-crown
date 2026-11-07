class_name LastExperiment
extends PlagueSkill
## V The Last Experiment ("experiment"): the vat slammed down (its full ring shown at once), cranked (the crank is an
## attack of its own, "crank": a stun, another move or walking away from the vat interrupts it, and it bursts small),
## then the homunculus bursts out and the ring becomes a quarantine: spore rain, Blight and a slow inside, the
## creature lumbering at the nearest foe and spewing telegraphed cones. It collapses at the end.
## His own game cranks (`cranking`) and decides when it bursts; the vat, the quarantine and the creature are the
## rules' (`lab`), here or on the match server's copy of him. The creature's walk is plain data here (`_creature`);
## every game's look walks its own copy the same way, and the spews come from where the rules have it.
## PvP (PvpObjects): the vat while he cranks it (broken: the experiment fails, no quarantine) and the creature
## (killed: the quarantine ends). His own game counts the blows (`owned`, `obj_hit`), as Corpse Bloom's.
## Its look: PlagueExperimentFx ("vat" {p, r, n: its id}, "burst" {r, n: the creature's id, x: seconds}, "spew"
## {p: from, q: toward}, "end", "obj" {n, x: blows left}). Codex "k": cast_s, crank_s, radius (Bigger Experiment adds
## to it), small_r (interrupted), walk (metres he may stray from the vat), secs (Longer Experiment adds), slow (%),
## slow_s, every (seconds between its rot's hits), burst_flat/lvl/wpn, rot_flat/lvl/wpn, creature_speed, spew_every,
## spew_warn, spew_len, spew_half (radians each side), spew_flat/lvl/wpn, spew_poison_s.

var lab := {}          # the rules': {stage, pos, r, t, tick, spew, oid, coid, c_pos, c_age, spew_at}
var cranking := {}     # his game: {from, r, oid}
var owned := {}        # his game: id -> [blows left, "vat" | "creature", seconds it stands]

func cast(aim: Vector3) -> void:
	hero.atk_aim = within_range(aim, 7.0)
	hero._start_attack("pd_slam", id)
	hero.atk_dur = cast_secs(0.9)

func radius() -> float:
	return val("radius", 8.0) * (1.0 + hero.talent("exp_size") / 100.0)

func secs() -> float:
	return val("secs", 7.0) + hero.talent("exp_dur")

## The slam's release puts the vat down and starts the crank; the crank's own release bursts it.
func impact() -> void:
	if hero.atk_skill == "crank":
		if not cranking.is_empty():
			_burst(float(cranking["r"]))
		return
	var h := hero
	var g := ground(h.atk_aim)
	var r := radius()
	var oid := Plague.new_oid(h)
	reveal_if_fogged()
	owned[oid] = [int(PvpObjects.HITS["vat"]), "vat", val("crank_s", 2.5) + 3.0]
	h.fx(id, "vat", {"p": g, "r": r, "n": oid})
	make("vat", {"g": g, "r": r, "n": oid})
	# stage 2: cranking it (an attack of its own, so a stun or another skill interrupts it)
	cranking = {"from": h.global_position, "r": r, "oid": oid}
	h._start_attack("pd_crank", "crank")
	h.atk_dur = val("crank_s", 2.5) * (PvpStatus.act_mult(h) if not h.pvs.is_empty() else 1.0)

## His game: the crank done (or interrupted: smaller), the experiment bursts, seen at once, dealt by the rules.
func _burst(r: float) -> void:
	var coid := Plague.new_oid(hero)
	owned.erase(int(cranking.get("oid", 0)))
	cranking = {}
	owned[coid] = [int(PvpObjects.HITS["creature"]), "creature", secs() + 1.0]
	hero.fx(id, "burst", {"r": r, "n": coid, "x": secs()})
	make("burst", {"r": r, "n": coid})

## Server: the vat within its range of where it has him, no wider than his; a burst no wider than its vat.
func server_ok(kind: String, d: Dictionary) -> bool:
	match kind:
		"vat":
			if not near_him(d.get("g"), float(Data.skill_def(id).get("range", 7.0)) + 4.0):
				return false
			d["r"] = clampf(float(d.get("r", 0.0)), 0.0, radius())
			return true
		"burst":
			if lab.is_empty() or int(lab["stage"]) != 1:
				return false
			d["r"] = clampf(float(d.get("r", 0.0)), 0.0, float(lab["r"]))
			return true
		"break":
			return obj_pos(int(d.get("n", 0))) is Vector3
	return false

func made(kind: String, d: Dictionary) -> void:
	match kind:
		"vat":
			if not lab.is_empty():
				_end()
			lab = {"stage": 1, "pos": d["g"], "r": float(d["r"]), "t": 0.0, "tick": 0.0, "spew": val("spew_every", 2.4) * 0.5,
				"oid": int(d.get("n", 0))}
		"burst":
			_burst_rules(float(d["r"]), int(d.get("n", 0)))
		"break":
			var n := int(d.get("n", 0))
			if not lab.is_empty() and ((int(lab["stage"]) == 1 and int(lab["oid"]) == n) or (int(lab["stage"]) == 2 and int(lab.get("coid", 0)) == n)):
				lab = {}      # (the vat broken: the experiment fails; the creature killed: the quarantine ends)

## Stage 2: the quarantine opens, everything in it hurt and Blighted; the creature crawls out of the vat.
func _burst_rules(r: float, coid: int) -> void:
	if lab.is_empty() or int(lab["stage"]) != 1:
		return
	lab["stage"] = 2
	lab["r"] = r
	lab["t"] = secs()
	lab["tick"] = 0.0
	lab["coid"] = coid
	lab["c_pos"] = lab["pos"]
	lab["c_age"] = 0.0
	var pos: Vector3 = lab["pos"]
	var dmg := base_k("burst", 20.0, 3.0, 0.4)
	var a := aff()
	for e in foes(pos, r):
		damage(e, dmg, pos, true)
		a.blight(e, id)

func update(delta: float) -> void:
	for k in owned.keys():
		owned[k][2] = float(owned[k][2]) - delta
		if float(owned[k][2]) <= 0.0:
			owned.erase(k)
	if not cranking.is_empty():
		_check_crank()
	if lab.is_empty() or int(lab["stage"]) != 2:
		return
	lab["t"] = float(lab["t"]) - delta
	if float(lab["t"]) <= 0.0:
		_end()
		return
	var pos: Vector3 = lab["pos"]
	var r: float = lab["r"]
	_creature(delta, pos, r)
	lab["tick"] = float(lab["tick"]) - delta
	var a := aff()
	if float(lab["tick"]) <= 0.0:
		lab["tick"] = a.tick()
		for e in foes(pos, r):
			PvpStatus.send(hero.game, e, "slow", val("slow_s", 0.7), val("slow", 20.0) / 100.0)
			if fmod(float(lab["t"]), val("every", 2.0)) < a.tick():
				damage(e, base_k("rot", 8.0, 1.21, 0.16), pos, false)
				a.blight(e, id)
	# the creature spews at the nearest foe: a telegraphed cone, then the hit
	lab["spew"] = float(lab["spew"]) - delta
	if float(lab["spew"]) <= 0.0:
		lab["spew"] = val("spew_every", 2.4)
		var near := _creature_foes(pos, r)
		var from := _creature_pos()
		if not near.is_empty():
			near.sort_custom(func(x, y) -> bool: return x.global_position.distance_to(from) < y.global_position.distance_to(from))
			var toward: Vector3 = near[0].global_position
			hero.fx(id, "spew", {"p": from, "q": toward})
			lab["spew_at"] = [from, toward, val("spew_warn", 1.0)]
	if lab.has("spew_at"):
		var sp: Array = lab["spew_at"]
		sp[2] = float(sp[2]) - delta
		if float(sp[2]) <= 0.0:
			lab.erase("spew_at")
			var from2: Vector3 = sp[0]
			var dir := ((sp[1] as Vector3) - from2) * Vector3(1, 0, 1)
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
			for e in foes(from2, val("spew_len", 4.0)):
				var to_e: Vector3 = (e.global_position - from2) * Vector3(1, 0, 1)
				if to_e.length() < 0.3 or absf(dir.signed_angle_to(to_e.normalized(), Vector3.UP)) < val("spew_half", 0.45):
					damage(e, base_k("spew", 16.0, 2.2, 0.3), from2, true)
					a.poison(e, "toxic", val("spew_poison_s", 2.0))

## His game, every frame he cranks: a stun, another move, or walking away from the vat bursts it early and small.
func _check_crank() -> void:
	var h := hero
	var on: bool = h.atk_t >= 0.0 and h.atk_skill == "crank"
	if on and h.daze_t <= 0.0 and h.global_position.distance_to(cranking["from"]) <= val("walk", 1.5):
		return
	if h.atk_skill == "crank":
		h.atk_t = -1.0
	_burst(val("small_r", 5.0))

## What the creature lumbers after: the foes in the zone that aren't players' things.
func _creature_foes(pos: Vector3, r: float) -> Array:
	return foes(pos, r).filter(func(e) -> bool: return e.pvp_obj <= 0)

func _creature_pos() -> Vector3:
	return (lab["c_pos"] as Vector3) + Vector3(0, 1.1, 0)

## The creature lumbers after the nearest foe inside the zone (never leaving it), once it has crawled out
## (PlagueExperimentFx.Vat.creature_step walks the look's copy the same way).
func _creature(delta: float, center: Vector3, radius_: float) -> void:
	lab["c_age"] = float(lab["c_age"]) + delta
	lab["c_pos"] = creature_walk(hero.game.world, lab["c_pos"], float(lab["c_age"]), delta,
		_creature_foes(center, radius_), center, radius_, val("creature_speed", 2.5))

## One frame of the creature's walk from `at`, `age` seconds after the burst (it screams first): toward the nearest of
## `near` until it is upon it, never past nine tenths of the zone. Its new place.
static func creature_walk(w, at: Vector3, age: float, delta: float, near: Array, center: Vector3, radius_: float, speed: float) -> Vector3:
	if age < 0.9:
		return at
	var best: Node3D = null
	var bd := 1e9
	for e in near:
		var d := (e as Node3D).global_position.distance_to(at)
		if d < bd:
			bd = d
			best = e
	if best == null or bd <= 1.6:
		return at
	var dir := (best.global_position - at) * Vector3(1, 0, 1)
	var np := at + dir.normalized() * speed * delta
	var off := (np - center) * Vector3(1, 0, 1)
	if off.length() > radius_ * 0.9:
		np = center + off.normalized() * radius_ * 0.9
	return Vector3(np.x, w.height_at(np.x, np.z), np.z)

func _end() -> void:
	if lab.is_empty():
		return
	lab = {}
	hero.fx(id, "end")

## Where his vat (while he cranks) or his creature `oid` is in the rules, or null.
func obj_pos(oid: int) -> Variant:
	if lab.is_empty() or oid <= 0:
		return null
	if int(lab["stage"]) == 1 and int(lab.get("oid", 0)) == oid:
		return lab["pos"]
	if int(lab["stage"]) == 2 and int(lab.get("coid", 0)) == oid:
		return lab["c_pos"]
	return null

## Another player's blow on his vat or creature (counted on his own game, through the server): everyone sees it, and
## the last one breaks it everywhere: a broken vat stops his crank. True if it was one of his experiment's.
func obj_hit(oid: int, _attacker: int) -> bool:
	if not owned.has(oid):
		return false
	var left: int = int(owned[oid][0]) - 1
	owned[oid][0] = left
	hero.fx(id, "obj", {"n": oid, "x": left})
	if left <= 0:
		var was_vat: bool = str(owned[oid][1]) == "vat"
		owned.erase(oid)
		if was_vat and int(cranking.get("oid", -1)) == oid:
			cranking = {}
			if hero.atk_t >= 0.0 and hero.atk_skill == "crank":
				hero.atk_t = -1.0
		make("break", {"n": oid})
	return true

func clear() -> void:
	lab = {}
	cranking = {}
	owned.clear()
