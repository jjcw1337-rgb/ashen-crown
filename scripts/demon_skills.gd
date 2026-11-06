class_name DemonSkills
extends RefCounted
## The Demon's skills: one job each (PvP first, PvE kept strong). Casts, the frames their blows land on, what runs
## every frame, and their state on the hero (`Hero.dm`, cleared by `clear`). Hero.use_skill, _impact and _process call
## in. Every skill is whole-body clips of his (Demon.SHOTS: the clip and how the attack's progress 0..1 maps onto its
## seconds); a skill with stages chains them (`_next`), each stage its own style. Nothing here draws: every effect is
## an fx event (`Hero.fx`, SkillFx) that DemonFx plays on his game and on his puppet on every partner's; the damage,
## the statuses and his own movement stay here, on the caster's game.
##
## The kit (tuning in Data.SKILLS, PvP overrides in each entry's "pvp"):
##  - Molten Fists (Q, "fists", burst finisher): the heavy wedge punch on the skill format (its timing, area, damage
##    and burn are its Data.SKILLS entry, SkillSpec); a Branded target takes more and loses the Brand.
##  - Infernal Charge (E, "icharge", engage / mobility): "icharge_wind" (paws the ground; the burning line shows
##    everyone the path) -> "icharge" (the run, CHARGE_SPEED, up to CHARGE_RANGE) -> "icharge_skid" (the stop, open
##    to punishment). Stops on the first champion, boss or player: staggered and Branded. Others are bowled aside.
##  - Fault of the Pit (R, "cslam", area control): the slam splits a line FAULT_LEN long FAULT_AHEAD ahead, across
##    the aim; after FAULT_WARN it erupts (damage, thrown up, Branded) and stays molten FAULT_LIFE s (burns, slows).
##  - Brimstone Hurl (F, "hurl", ranged pressure): no cooldown, its "use" time is its limit (the Path of Exile way);
##    "hurl"/"hurl2" alternate; the boulder lands at the aim after its flight (the shadow shows where): core HURL_CORE
##    (full damage + Brand), edge HURL_R (half), then it shatters into SHARDS burning pieces. Twin Boulders
##    (hurl_twin) throws a second one TWIN_GAP beside the first.
##  - Hellgrip (G, "grip", pick / pull): "grip_throw" flings the chain (CHAIN_LEN at CHAIN_SPEED, the first body in
##    its line is hooked; monsters block it) -> "grip_haul" (the victim dragged to him, or he to a boss) -> "grip"
##    (hoisted and smashed). A miss hauls back an empty chain (the recovery). Branded: CHAIN_REFUND of the cooldown back.
##  - Wrath of the Pit (V, "wrath", defensive counter): "crucible" (wings folded, up to CRUCIBLE_MAX s, recast to end:
##    CRUCIBLE_DR less damage taken, nothing moves or stops him, the damage stored as heat) -> "wrath_roar" (the
##    eruption round him: damage + the heat, terror) -> PIT_DUR s of +damage and meteors.

## Each stage's length in seconds (before Data.ATTACK_PACE; the charge's run is set by its distance). A skill with a
## "use" in its Data.SKILLS entry (SkillSpec) takes that instead: Molten Fists is a heavy blow the Path of Exile way
## (jj, 2026-11-01: its "use" 2 s, "hit" 0.75 and damage are its data; DUR["fists"] is only the fallback), and so are
## Fault of the Pit and Brimstone Hurl (their "use" and "power").
const DUR := {"fists": 1.67, "icharge_wind": 0.32, "icharge": 0.6, "icharge_skid": 0.38, "cslam": 1.15, "hurl": 0.95,
	"hurl2": 1.0, "grip_throw": 0.55, "grip_haul": 0.45, "grip": 1.25, "crucible": 2.0, "wrath_roar": 1.1}
## The attack style each skill starts with
const STYLE := {"fists": "fists", "icharge": "icharge_wind", "cslam": "cslam", "hurl": "hurl", "grip": "grip_throw", "wrath": "crucible"}
const STAGES := ["icharge_wind", "icharge", "icharge_skid", "grip_throw", "grip_haul", "grip", "crucible", "wrath_roar"]
## Old saves: the skills these replaced, so their bindings carry over
const OLD_IDS := {"hellclaw": "fists", "summon": "icharge", "phase": "cslam", "pact": "hurl"}

const FISTS_R := 3.4           # how far ahead the cracks reach (= its data's area "r"; the effects draw with it)
const FISTS_HALF := 42.0       # half the wedge's angle (degrees; = its data's area "angle" / 2)
const BRAND_DUR := 4.0
const BRAND_BONUS := 0.3       # Molten Fists on a Branded target (PvE; the PvP share is Data's)

const CHARGE_RANGE := 9.0
const CHARGE_MIN := 3.0
const CHARGE_SPEED := 16.0
const CHARGE_HIT_R := 1.5
const HAZARD_TICK := 0.4

const FAULT_AHEAD := 3.0       # from him to the fault's middle
const FAULT_LEN := 7.0
const FAULT_W := 1.4
const FAULT_WARN := 0.4        # the glowing crack before the eruption
const FAULT_LIFE := 4.0        # molten after it
const FAULT_SLOW := 0.35

const HURL_RANGE := 14.0
const HURL_MIN := 3.0
const HURL_FLIGHT := 0.55      # + HURL_PER_M a metre: a long throw is slower to land and easier to step out of
const HURL_PER_M := 0.025
const HURL_CORE := 1.3
const HURL_R := 2.6
const TWIN_GAP := 2.2         # Twin Boulders: the second lands this far to the side of the first ...
const TWIN_LATE := 0.12        # ... and this much later
const SHARDS := 4
const SHARD_R := 0.9

const CHAIN_LEN := 7.5
const CHAIN_SPEED := 24.0
const CHAIN_HIT_W := 0.55
const CHAIN_REFUND := 0.3
const GRIP_SHOCK_R := 2.6
const GRIP_LIFT := 2.1         # how high the victim is held
const HOLD_IN := 1.5           # where a dragged victim ends up in front of him

const CRUCIBLE_MAX := 2.0
const CRUCIBLE_MIN := 0.35     # before a recast can end it
const CRUCIBLE_DR := 0.5
const HEAT_SHARE := 0.5        # of the damage stored, added to the eruption
const HEAT_CAP := 0.3          # of his maximum life
const ROAR_R := 6.0
const PIT_DUR := 6.0
const WRATH_EVERY := 0.45
const WRATH_R := 9.0
const WRATH_FALL := 0.55       # a meteor's time in the air (PvE)
const WRATH_FALL_PVP := 0.8    # ... and at a player, with its glowing circle
const METEOR_R := 2.3

static func active(h: Hero) -> bool:
	return h.is_demon()

## The magma in his blows: a part by level on top of the weapon (the same curve as the other classes' spells), so
## the skills keep their weight while the weapon is still small. k is the skill's share of it.
static func magma(h: Hero, k: float) -> float:
	return (16.0 + h.level * 4.5 + (h.dmg_min + h.dmg_max) * 0.35) * k

static func pvp(id: String, key: String, def: float) -> float:
	return float((Data.skill_def(id).get("pvp", {}) as Dictionary).get(key, def))

## A blow of one of his skills: against a player (a Battlegrounds stand-in) its PvP share applies, and the Pit-born
## bonus is the PvP one.
static func _hit(h: Hero, e, mult: float, knock: float, src: String, flat: float) -> void:
	if PvpStatus.is_player(e):
		var share := pvp(src, "dmg", 1.0)
		if h.buff_t > 0.0 and h.dm.has("pit"):
			share *= (1.0 + pvp("wrath", "bonus", 0.2)) / h.buff_mult()
		mult *= share
		flat *= share
		knock = 0.0
	h._hit_enemy(e, mult, knock, src, flat)

## Is this one too big to be stopped or dragged (bosses, the Sloths)?
static func immovable(e) -> bool:
	return bool(e.boss) or e.get("sloth") != null

## Can he be told to walk right now? Everything but the fists roots him.
static func rooted(h: Hero) -> bool:
	return h.atk_t >= 0.0 and h.atk_skill in ["icharge", "cslam", "hurl", "grip", "wrath"]

static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	return true

static func _start(h: Hero, style: String, skill: String, secs := 0.0) -> void:
	h._start_attack(style, skill)
	# (the same timing everywhere, the Battlegrounds included; a skill with a "use" in its data is retimed by
	# SkillSpec.apply_timing once its cast is done)
	var d: float = (secs if secs > 0.0 else float(DUR[style])) * Data.attack_pace(h.cls)
	if skill == "fists":
		d /= h.aspd
	h.atk_dur = d
	h.moving = false
	h.path = PackedVector3Array()

# ---------------------------------------------------------------- the Brand
## Brands a foe (Charge, Fault, Hurl). Monsters: kept here; a player: the server tells them (they see it on
## themselves) and every game draws it on their puppet from the fx event.
static func brand(h: Hero, e) -> void:
	if e == null or not is_instance_valid(e) or e.dead:
		return
	var b: Dictionary = h.dm.get("brand", {})
	b[e.get_instance_id()] = h.anim_time + BRAND_DUR
	h.dm["brand"] = b
	if PvpStatus.is_player(e):
		PvpStatus.send(h.game, e, "brand", BRAND_DUR)
		h.fx("fists", "brand", {"pid": int(e.pvp_pid), "x": BRAND_DUR})
	else:
		h.fx("fists", "brand", {"t": [e], "x": BRAND_DUR})

static func branded(h: Hero, e) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	var b: Dictionary = h.dm.get("brand", {})
	return float(b.get(e.get_instance_id(), -1.0)) > h.anim_time

static func _unbrand(h: Hero, e) -> void:
	var b: Dictionary = h.dm.get("brand", {})
	b.erase(e.get_instance_id())

## A status on a foe: a monster takes it here (stun, slow), a player through the server (PvpStatus).
static func _cc(h: Hero, e, kind: String, pve_secs: float, pvp_secs: float, data := {}) -> void:
	if e == null or not is_instance_valid(e) or e.dead:
		return
	if PvpStatus.is_player(e):
		if pvp_secs > 0.0:
			PvpStatus.send(h.game, e, kind, pvp_secs, data)
		return
	match kind:
		"slow":
			e.slow(pve_secs, float(data.get("k", 0.35)))
		_:
			if pve_secs > 0.0:
				e.stun(pve_secs)

# ---------------------------------------------------------------- casts
static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var w: Dictionary = h.dm
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	match id:
		"fists":
			_start(h, "fists", "fists")
		"icharge":
			var dir := to.normalized() if to.length() > 0.5 else h.aim_dir()
			var dist := clampf(to.length(), CHARGE_MIN, CHARGE_RANGE)
			# where he would end up (walls cut it short), so the line everyone sees is the truth
			var end: Vector3 = h.game.world.move(h.global_position, dir * dist, h.radius)
			end.y = h.game.world.height_at(end.x, end.z)
			dist = maxf(1.0, (end - h.global_position).length())
			w["charge"] = {"dir": dir, "dist": dist, "done": 0.0, "hit": {}, "stop": false}
			_start(h, "icharge_wind", "icharge")
			h.fx("icharge", "wind", {"p": h.global_position, "q": end, "d": dir, "x": h.atk_dur})
		"cslam":
			_start(h, "cslam", "cslam")
		"hurl":
			var at := h.global_position + to.limit_length(HURL_RANGE)
			if to.length() < HURL_MIN:
				at = h.global_position + h.aim_dir() * HURL_MIN
			at.y = h.game.world.height_at(at.x, at.z)
			w["hurl_at"] = at
			var second := bool(w.get("hurl_alt", false))
			w["hurl_alt"] = not second
			_start(h, "hurl2" if second else "hurl", "hurl")
		"grip":
			w.erase("chain")
			w["grip_victim"] = null
			w["grip_held"] = false
			w["grip_grabbed"] = false
			_start(h, "grip_throw", "grip")
		# a run's skills (Data.RUN_SKILLS)
		"d_volcano":
			var at2 := h.global_position + to.limit_length(13.0)
			at2.y = h.game.world.height_at(at2.x, at2.z)
			w["volcano_at"] = at2
			_start(h, "hurl", "d_volcano")
		"d_detonate":
			_start(h, "cslam", "d_detonate", 0.9)
		"d_pact":
			_start(h, "wrath_stomp", "d_pact", 0.8)
		"wrath":
			end_wrath(h, false)
			w["wrath"] = {"stage": 0, "t": 0.0, "heat": 0.0, "rain": -1.0, "next": 0.0, "n": 0, "pvp_n": 0}
			_start(h, "crucible", "wrath", CRUCIBLE_MAX)
			h.fx("wrath", "crucible", {"x": h.atk_dur})

## Hellgrip and the Crucible: pressing the key again mid-skill (Hero.use_skill asks first). True when it was taken.
static func recast(h: Hero, id: String) -> bool:
	if id == "wrath" and in_crucible(h) and h.atk_t >= CRUCIBLE_MIN * Data.attack_pace(h.cls):
		_erupt_now(h)
		return true
	return false

# ---------------------------------------------------------------- the blows
## Called from Hero._impact on the attack's impact frame; true when it was one of his.
static func impact(h: Hero) -> bool:
	if not active(h):
		return false
	if h.atk_skill.begins_with("d_") and _run_impact(h):
		return true       # (a run's skill on a borrowed style: its own impact, not the style's skill)
	match h.atk_style:
		"fists":
			_fists(h)
		"icharge_wind", "icharge", "icharge_skid", "grip_haul", "crucible":
			pass       # moved by update
		"cslam":
			_fault_open(h)
		"hurl", "hurl2":
			_throw(h)
		"grip_throw":
			_fling_chain(h)
		"grip":
			_grip_smash(h)
		"wrath_roar":
			_eruption(h)
		_:
			return h.atk_skill in STYLE
	return true

const VOLCANO_N := 5
const VOLCANO_R := 6.0
const DETONATE_R := 10.0

## A run's skills on their impact frame (the styles they borrow: hurl, stomp, roar).
static func _run_impact(h: Hero) -> bool:
	var w: Dictionary = h.dm
	match h.atk_skill:
		"d_volcano":
			var at: Vector3 = w.get("volcano_at", h.global_position)
			h.fx("d_volcano", "raise", {"p": at})
			var n := VOLCANO_N + int(h.talent("volcano_more"))
			var foes: Array = h.game.enemies_near(at, VOLCANO_R).filter(func(e): return not e.dead)
			var ms: Array = w.get("meteors", [])
			for i in n:
				var p: Vector3
				if not foes.is_empty():
					var pick = foes[i % foes.size()]
					p = pick.global_position + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
				else:
					var ang := TAU * float(i) / n
					p = at + Vector3(cos(ang), 0, sin(ang)) * randf_range(2.0, VOLCANO_R * 0.8)
				p.y = h.game.world.height_at(p.x, p.z)
				var fall := 0.6 + i * 0.35
				ms.append({"at": p, "t": fall, "src": "d_volcano"})
				h.fx("wrath", "meteor", {"p": p, "n": i, "x": fall})
			w["meteors"] = ms
		"d_detonate":
			var popped := PackedVector3Array()
			for e in h.game.enemies_near(h.global_position, DETONATE_R):
				if e.dead or not branded(h, e):
					continue
				_unbrand(h, e)
				popped.append(e.global_position)
				_hit(h, e, 1.6, 1.4, "d_detonate", magma(h, 0.5))
				if is_instance_valid(e) and not e.dead:
					_cc(h, e, "knockup", 0.8, 0.5)
				for o in h.game.enemies_near(e.global_position, 2.5):
					if o != e and not o.dead:
						_hit(h, o, 0.6, 0.6, "d_detonate", 0.0)
						if h.talent("detonate_brand") > 0.0:
							brand(h, o)
			h.fx("d_detonate", "impact", {"ps": popped})
		"d_pact":
			var cost := h.max_life * 0.15
			h.life = maxf(1.0, h.life - cost)
			RunTalents.buff(h, "blood_pact", {"dmg": 35.0 + h.talent("pact_pow"), "ls": 6.0}, 8.0)
			h.fx("d_pact", "impact", {"x": 8.0})
		_:
			return false
	return true

## Molten Fists on the skill format (jj): its area, damage and burn are its data (Data.SKILLS, SkillSpec); the magma
## is his own part on top; a Branded foe takes BRAND_BONUS more (a player: its "pvp" share) and loses the Brand.
static func _fists(h: Hero) -> void:
	var wide := h.talent("fists_wide") > 0.0
	var reach := FISTS_R + (1.0 if wide else 0.0)
	var lit := []
	for e in SkillSpec.targets(h, "fists", {"r_add": 1.0 if wide else 0.0, "angle_add": 24.0 if wide else 0.0}):
		var k := 1.0
		if branded(h, e):
			k += pvp("fists", "brand_bonus", BRAND_BONUS) if PvpStatus.is_player(e) else BRAND_BONUS
			_unbrand(h, e)
			if PvpStatus.is_player(e):
				h.fx("fists", "consume", {"pid": int(e.pvp_pid)})
			else:
				h.fx("fists", "consume", {"t": [e]})
		_strike(h, "fists", e, magma(h, 0.5), {"mult": k, "dot_secs": 2.0 if wide else 1.0})
		if is_instance_valid(e) and not e.dead and not PvpStatus.is_player(e):
			lit.append(e)
	h.fx("fists", "impact", {"y": h.rig.global_rotation.y, "r": reach, "t": lit})

## One foe struck by a skill on the skill format (SkillSpec: its "dmg", "knock", "type" and "dot" are its data; `extra`
## his magma). A player's stand-in goes through _hit (the PvP share, no knockback) and its burn through the server
## (PvpStatus, capped); a monster through SkillSpec.strike. opts: SkillSpec.strike's ("mult", "dot_secs").
static func _strike(h: Hero, id: String, e, extra: float, opts := {}) -> void:
	if not is_instance_valid(e) or e.dead:
		return
	if not PvpStatus.is_player(e):
		SkillSpec.strike(h, id, e, extra, opts)
		return
	var d := SkillSpec.of(id)
	var k := float(opts.get("mult", 1.0))
	_hit(h, e, float(d.get("dmg", 0.0)) / 100.0 * k, 0.0, id, (extra + SkillSpec.spell_damage(h, id)) * k)
	var dt: Dictionary = d.get("dot", {})
	if str(dt.get("kind", "")) == "burn" and is_instance_valid(e) and not e.dead:
		var secs := float(dt.get("secs", 3.0))
		PvpStatus.send(h.game, e, "burn", secs * float(opts.get("dot_secs", 1.0)),
			{"dps": SkillSpec.expected(h, id, extra) * k * float(dt.get("pct", 25.0)) / 100.0 / secs})

# ---------------------------------------------------------------- Infernal Charge
static func _update_charge(h: Hero, delta: float) -> void:
	var w: Dictionary = h.dm
	var c: Dictionary = w["charge"]
	if h.dead or h.atk_skill != "icharge":
		w.erase("charge")
		h.fx("icharge", "end", {"p": h.global_position})
		return
	if h.atk_style != "icharge" or bool(c["stop"]):
		return
	var dir: Vector3 = c["dir"]
	var left: float = float(c["dist"]) - float(c["done"])
	var d := minf(CHARGE_SPEED * delta, left)
	if d <= 0.0:
		return
	var np: Vector3 = h.game.world.move(h.global_position, dir * d, h.radius)
	var moved := np - h.global_position
	moved.y = 0
	h.global_position = np
	h._face(dir)
	c["done"] = float(c["done"]) + d
	for e in h.game.enemies_near(h.global_position + dir * 0.4, CHARGE_HIT_R + 0.8):
		if (c["hit"] as Dictionary).has(e.get_instance_id()):
			continue
		var to: Vector3 = e.global_position - h.global_position
		to.y = 0
		if to.length() - e.radius > CHARGE_HIT_R or (to.length() > 0.3 and dir.dot(to.normalized()) < -0.2):
			continue
		c["hit"][e.get_instance_id()] = true
		var big: bool = PvpStatus.is_player(e) or e.champion or immovable(e)
		_hit(h, e, 1.2, 0.0 if big else 2.6, "icharge", magma(h, 0.5))
		if is_instance_valid(e) and not e.dead:
			_cc(h, e, "stagger", 1.0 if big else 0.5, pvp("icharge", "stagger", 0.5))
			if big:
				brand(h, e)
		h.fx("icharge", "hit", {"p": e.global_position + Vector3(0, 0.8 * e.height, 0), "d": dir, "x": big})
		if big:
			c["stop"] = true
			SkillFx.hitstop(h, 0.06)
			break
	if moved.length() < d * 0.3:
		c["stop"] = true      # a wall
	if bool(c["stop"]) or float(c["done"]) >= float(c["dist"]) - 0.01:
		c["stop"] = true
		h.atk_t = h.atk_dur   # the run ends now: the skid follows (_next)

# ---------------------------------------------------------------- Fault of the Pit
static func _fault_open(h: Hero) -> void:
	var fwd := h.aim_dir()
	var side := fwd.cross(Vector3.UP).normalized()
	var mid := h.global_position + fwd * FAULT_AHEAD
	var half := FAULT_LEN * 0.5
	var a: Vector3 = mid - side * half
	var b: Vector3 = mid + side * half
	a.y = h.game.world.height_at(a.x, a.z)
	b.y = h.game.world.height_at(b.x, b.z)
	mid.y = h.game.world.height_at(mid.x, mid.z)
	var life := FAULT_LIFE + h.talent("trail_dur")
	h.dm["fault"] = {"a": a, "b": b, "t": 0.0, "erupted": false, "life": life, "tick": 0.0, "hit": {}}
	h.fx("cslam", "impact", {"p": h.global_position + fwd * 1.1, "q": mid, "ps": PackedVector3Array([a, b]), "y": h.rig.global_rotation.y, "x": FAULT_WARN, "r": life})
	SkillFx.hitstop(h, 0.03)

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()

static func _update_fault(h: Hero, delta: float) -> void:
	var f: Dictionary = h.dm["fault"]
	f["t"] = float(f["t"]) + delta
	var a: Vector3 = f["a"]
	var b: Vector3 = f["b"]
	if not bool(f["erupted"]):
		if float(f["t"]) < FAULT_WARN:
			return
		f["erupted"] = true
		var struck := []
		for e in h.game.enemies_near((a + b) * 0.5, FAULT_LEN * 0.5 + 1.5):
			if _seg_dist(e.global_position, a, b) - e.radius <= FAULT_W * 0.5:
				struck.append(e)
				_hit(h, e, 1.4, 0.6, "cslam", magma(h, 0.7))
				if is_instance_valid(e) and not e.dead:
					_cc(h, e, "knockup", 0.7, pvp("cslam", "knockup", 0.35))
					brand(h, e)
		h.fx("cslam", "erupt", {"ps": PackedVector3Array([a, b]), "t": struck.filter(func(x) -> bool: return not PvpStatus.is_player(x)),
			"x": not struck.is_empty()})
		f["tick"] = HAZARD_TICK
		return
	var left: float = float(f["life"]) - (float(f["t"]) - FAULT_WARN)
	if left <= 0.0:
		h.dm.erase("fault")
		return
	f["tick"] = float(f["tick"]) - delta
	if float(f["tick"]) > 0.0:
		return
	f["tick"] = HAZARD_TICK
	for e in h.game.enemies_near((a + b) * 0.5, FAULT_LEN * 0.5 + 1.5):
		if _seg_dist(e.global_position, a, b) - e.radius * 0.6 <= FAULT_W * 0.5:
			var dmg: float = magma(h, 0.22) * h.buff_mult() * h.dmg_mult("cslam") * (pvp("cslam", "dmg", 1.0) if PvpStatus.is_player(e) else 1.0)
			e.take_damage(0.0, dmg, e.global_position, 0.0, false)
			if is_instance_valid(e) and not e.dead:
				_cc(h, e, "slow", HAZARD_TICK + 0.35, HAZARD_TICK + 0.35, {"k": pvp("cslam", "slow", FAULT_SLOW)})

# ---------------------------------------------------------------- Brimstone Hurl
static func _throw(h: Hero) -> void:
	var at: Vector3 = h.dm.get("hurl_at", h.global_position + h.aim_dir() * 4.0)
	var hand := SkillFx.hand(h, true) if h.rig != null else h.global_position + Vector3(0, 1.8, 0)
	var flight := HURL_FLIGHT + at.distance_to(h.global_position) * HURL_PER_M
	var bs: Array = h.dm.get("boulders", [])
	bs.append({"at": at, "t": flight})
	h.fx("hurl", "throw", {"p": hand, "q": at, "x": flight, "n": 1 if h.atk_style == "hurl2" else 0})
	if h.talent("hurl_twin") > 0.0:
		# Twin Boulders: a second one torn loose with it, landing beside the first (on the side of the throwing arm)
		var side := (at - h.global_position).cross(Vector3.UP) * Vector3(1, 0, 1)
		side = side.normalized() if side.length() > 0.1 else h.aim_dir().cross(Vector3.UP)
		var at2: Vector3 = h.game.world.move(at, side * (TWIN_GAP if h.atk_style == "hurl" else -TWIN_GAP), 0.3)
		at2.y = h.game.world.height_at(at2.x, at2.z)
		bs.append({"at": at2, "t": flight + TWIN_LATE})
		h.fx("hurl", "throw", {"p": hand, "q": at2, "x": flight + TWIN_LATE, "n": 1 if h.atk_style == "hurl2" else 0})
	h.dm["boulders"] = bs

static func _splash(h: Hero, at: Vector3) -> void:
	var lit := []
	for e in h.game.enemies_near(at, HURL_R + 0.8):
		var to: Vector3 = e.global_position - at
		to.y = 0
		var d: float = to.length() - e.radius
		if d > HURL_R:
			continue
		var core := d <= HURL_CORE
		_hit(h, e, 1.8 if core else 0.9, 1.4 if core else 0.6, "hurl", magma(h, 1.0 if core else 0.5))
		if is_instance_valid(e) and not e.dead:
			if core:
				brand(h, e)
				var dps: float = magma(h, 0.1) * h.dmg_mult("hurl")
				if PvpStatus.is_player(e):
					PvpStatus.send(h.game, e, "burn", 3.0, {"dps": dps})
				else:
					e.ignite(dps, 3.0)
					lit.append(e)
	# the shards: four burning pieces skitter out and catch whoever stands where they stop
	var dirs := PackedVector3Array()
	var base := randf() * TAU
	for i in SHARDS:
		var ang := base + TAU * float(i) / SHARDS + randf_range(-0.3, 0.3)
		var p := at + Vector3(cos(ang), 0, sin(ang)) * randf_range(1.8, 2.4)
		p = h.game.world.move(at, p - at, 0.2)
		p.y = h.game.world.height_at(p.x, p.z)
		dirs.append(p)
		for e in h.game.enemies_near(p, SHARD_R + 0.6):
			var to: Vector3 = e.global_position - p
			to.y = 0
			if to.length() - e.radius <= SHARD_R:
				_hit(h, e, 0.25, 0.0, "hurl", magma(h, 0.15))
	h.fx("hurl", "splash", {"p": at, "ps": dirs, "t": lit})
	SkillFx.hitstop(h, 0.04 if not lit.is_empty() else 0.0)

# ---------------------------------------------------------------- Hellgrip
static func _fling_chain(h: Hero) -> void:
	var from := h.global_position + Vector3(0, 1.3, 0)
	var dir := h.aim_dir()
	h.dm["chain"] = {"from": from, "dir": dir, "len": 0.0, "state": "out", "victim": null, "t": 0.0}
	h.fx("grip", "fling", {"p": from, "d": dir, "x": CHAIN_LEN / CHAIN_SPEED, "r": CHAIN_LEN})

static func _update_chain(h: Hero, delta: float) -> void:
	var w: Dictionary = h.dm
	var c: Dictionary = w["chain"]
	if h.dead or h.atk_skill != "grip":
		w.erase("chain")
		return
	c["t"] = float(c["t"]) + delta
	match str(c["state"]):
		"out":
			var l0: float = float(c["len"])
			var l1 := minf(l0 + CHAIN_SPEED * delta, CHAIN_LEN)
			c["len"] = l1
			var dir: Vector3 = c["dir"]
			var base := h.global_position
			var hook = null
			var bd := 99.0
			for e in h.game.enemies_near(base + dir * (l1 * 0.5), l1 * 0.5 + 1.5):
				var to: Vector3 = e.global_position - base
				to.y = 0
				var along := to.dot(dir)
				if along < l0 - 0.6 or along > l1 + e.radius:
					continue
				var off := (to - dir * along).length()
				if off - e.radius > CHAIN_HIT_W:
					continue
				if along < bd:
					bd = along
					hook = e
			# the chain stops on stone too
			var tip := base + dir * l1
			var free: Vector3 = h.game.world.move(base, dir * l1, 0.2)
			var wall := (free - base).length() < l1 - 0.3
			if hook != null:
				_hooked(h, c, hook)
			elif wall or l1 >= CHAIN_LEN:
				c["state"] = "back"
				h.fx("grip", "miss", {"p": tip if not wall else free})
				_next_now(h, "grip_haul", 0.5)
		"drag":
			var v = c["victim"]
			if v == null or not is_instance_valid(v) or v.dead:
				c["state"] = "back"
				return
			var u: float = clampf(float(c["dt"]) + delta / maxf(float(c["dur"]), 0.05), 0.0, 1.0)
			c["dt"] = u
			var k := 1.0 - pow(1.0 - u, 2.0)
			if bool(c["self"]):
				# he is dragged to it
				var goal: Vector3 = (c["goal"] as Vector3)
				var want: Vector3 = (c["start"] as Vector3).lerp(goal, k)
				h.global_position = h.game.world.move(h.global_position, (want - h.global_position) * Vector3(1, 0, 1), h.radius)
			elif not PvpStatus.is_player(v) and not bool(v.remote):
				var want2: Vector3 = (c["start"] as Vector3).lerp(c["goal"], k)
				v.global_position = h.game.world.move(v.global_position, (want2 - v.global_position) * Vector3(1, 0, 1), v.radius)

static func _hooked(h: Hero, c: Dictionary, e) -> void:
	c["state"] = "drag"
	c["victim"] = e
	c["dt"] = 0.0
	var dur: float = float(DUR["grip_haul"]) * Data.attack_pace(h.cls)
	c["dur"] = dur
	var me := h.global_position
	var to: Vector3 = (e.global_position - me) * Vector3(1, 0, 1)
	var dir := to.normalized() if to.length() > 0.1 else h.aim_dir()
	# bosses, and monsters a partner's game doesn't own, drag him instead
	var self_pull: bool = immovable(e) or (not PvpStatus.is_player(e) and bool(e.remote))
	c["self"] = self_pull
	if self_pull:
		c["start"] = me
		c["goal"] = e.global_position - dir * (e.radius + h.radius + 0.6)
	else:
		c["start"] = e.global_position
		c["goal"] = me + dir * HOLD_IN
		if PvpStatus.is_player(e):
			# one hard status for the whole hold: dragged over the haul, then held till the smash
			PvpStatus.send(h.game, e, "pull", pvp("grip", "hold", 1.1), {"m": dur})
	if not PvpStatus.is_player(e):
		e.stun(dur + 1.4)
	if branded(h, e):
		h.cds["grip"] = h.cds.get("grip", 0.0) * (1.0 - CHAIN_REFUND)
		_unbrand(h, e)
	h.dm["grip_victim"] = e
	h.fx("grip", "hook", {"t": [] if PvpStatus.is_player(e) else [e], "pid": int(e.pvp_pid) if PvpStatus.is_player(e) else 0,
		"p": e.global_position + Vector3(0, e.height * 0.6, 0), "x": dur, "n": 1 if self_pull else 0})
	_next_now(h, "grip_haul", 0.0)

## Hellgrip's smash: the held foe is driven into the ground and set alight; a shockwave hits the rest.
static func _grip_smash(h: Hero) -> void:
	var w: Dictionary = h.dm
	var v = w.get("grip_victim")
	var at := h.global_position + h.aim_dir() * HOLD_IN
	at.y = h.game.world.height_at(at.x, at.z)
	var held: bool = v != null and is_instance_valid(v) and not v.dead
	if held:
		at = v.global_position
		at.y = h.game.world.height_at(at.x, at.z)
		_hit(h, v, 3.2, 0.3, "grip", magma(h, 1.6))
		if is_instance_valid(v) and not v.dead:
			var dps: float = magma(h, 0.2) * h.dmg_mult("grip")
			if PvpStatus.is_player(v):
				PvpStatus.send(h.game, v, "burn", 3.0, {"dps": dps})
			else:
				v.ignite(dps, 4.0)
				v.stun(0.6)
	for e in h.game.enemies_near(at, GRIP_SHOCK_R + 0.8):
		if e == v:
			continue
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius <= GRIP_SHOCK_R:
			_hit(h, e, 0.7, 1.5, "grip", magma(h, 0.4))
	w["grip_held"] = false
	h.fx("grip", "smash", {"p": at, "t": [v] if held and not PvpStatus.is_player(v) else [], "x": held})
	if held:
		SkillFx.hitstop(h, 0.07)

# ---------------------------------------------------------------- Wrath of the Pit
static func wrath_active(h: Hero) -> bool:
	return h.dm.has("wrath")

static func in_crucible(h: Hero) -> bool:
	return h.dm.has("wrath") and h.atk_skill == "wrath" and h.atk_style == "crucible" and h.atk_t >= 0.0

## Hero.take_hit asks: the Crucible takes CRUCIBLE_DR of the blow and stores what gets through as heat.
static func absorb(h: Hero, dmg: float) -> float:
	if not in_crucible(h):
		return dmg
	var left := dmg * (1.0 - CRUCIBLE_DR)
	var n: Dictionary = h.dm["wrath"]
	n["heat"] = minf(float(n["heat"]) + left, h.max_life * HEAT_CAP / HEAT_SHARE)
	h.fx("wrath", "heat", {"x": clampf(float(n["heat"]) * HEAT_SHARE / maxf(h.max_life * HEAT_CAP, 1.0), 0.0, 1.0)})
	return left

static func end_wrath(h: Hero, finished: bool) -> void:
	var w: Dictionary = h.dm
	w.erase("pit")
	if not w.has("wrath"):
		return
	w.erase("wrath")
	h.fx("wrath", "end", {"x": finished})

static func _erupt_now(h: Hero) -> void:
	_start(h, "wrath_roar", "wrath")
	(h.dm["wrath"] as Dictionary)["stage"] = 1

static func _eruption(h: Hero) -> void:
	var w: Dictionary = h.dm
	if not w.has("wrath"):
		return
	var n: Dictionary = w["wrath"]
	var heat: float = minf(float(n["heat"]) * HEAT_SHARE, h.max_life * HEAT_CAP)
	var at := h.global_position
	var struck := []
	for e in h.game.enemies_near(at, ROAR_R + 0.6):
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius > ROAR_R:
			continue
		struck.append(e)
		_hit(h, e, 1.0, 1.8, "wrath", magma(h, 0.8) + heat)
		if is_instance_valid(e) and not e.dead:
			_cc(h, e, "fear", 1.5, pvp("wrath", "fear", 0.75))
	h.buff_t = PIT_DUR + h.talent("buff_dur")
	w["pit"] = true
	n["rain"] = PIT_DUR + h.talent("wrath_dur")
	n["next"] = 0.35
	h.fx("wrath", "erupt", {"p": at, "x": float(n["rain"]), "r": clampf(heat / maxf(h.max_life * HEAT_CAP, 1.0), 0.0, 1.0),
		"t": struck.filter(func(x) -> bool: return not PvpStatus.is_player(x))})

## A meteor: aimed at a foe within WRATH_R (the one struck least recently), else near him. At a player (PvP) it
## falls slower under a glowing circle, and only "meteors" of them per cast.
static func _call_meteor(h: Hero) -> void:
	var w: Dictionary = h.dm
	var n: Dictionary = w["wrath"]
	var foes: Array = h.game.enemies_near(h.global_position, WRATH_R)
	var cap := int(pvp("wrath", "meteors", 3.0))
	if int(n["pvp_n"]) >= cap:
		foes = foes.filter(func(x) -> bool: return not PvpStatus.is_player(x))
	var at: Vector3
	var fall := WRATH_FALL
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
		if PvpStatus.is_player(pick):
			n["pvp_n"] = int(n["pvp_n"]) + 1
			fall = WRATH_FALL_PVP
	at.y = h.game.world.height_at(at.x, at.z)
	var k: int = int(n["n"])
	n["n"] = k + 1
	var ms: Array = w.get("meteors", [])
	ms.append({"at": at, "t": fall})
	w["meteors"] = ms
	h.fx("wrath", "meteor", {"p": at, "n": k, "x": fall})

static func _meteor_land(h: Hero, at: Vector3, src := "wrath") -> void:
	for e in h.game.enemies_near(at, METEOR_R + 0.8):
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius <= METEOR_R:
			_hit(h, e, 0.85 if src == "d_volcano" else 1.1, 1.2, src, magma(h, 0.55))
			if is_instance_valid(e) and not e.dead and not PvpStatus.is_player(e):
				e.ignite(magma(h, 0.1) * h.dmg_mult(src), 3.0)

# ---------------------------------------------------------------- every frame
static func update(h: Hero, delta: float) -> void:
	if not active(h):
		return
	var w: Dictionary = h.dm
	_stages(h)
	if w.has("charge"):
		_update_charge(h, delta)
	if w.has("chain"):
		_update_chain(h, delta)
	if w.has("fault"):
		_update_fault(h, delta)
	if w.has("grip_victim") and h.atk_skill != "grip":
		w.erase("grip_victim")
	# Hellgrip: the victim is held up over his head until the smash (shown by DemonFx)
	if h.atk_skill == "grip" and h.atk_style == "grip" and not bool(w.get("grip_grabbed", false)) and h.atk_t >= 0.0:
		w["grip_held"] = true
		w["grip_grabbed"] = true
		var v = w.get("grip_victim")
		if v != null and is_instance_valid(v) and not v.dead:
			if not PvpStatus.is_player(v):
				v.stun(2.0)
			h.fx("grip", "grab", {"t": [] if PvpStatus.is_player(v) else [v], "pid": int(v.pvp_pid) if PvpStatus.is_player(v) else 0,
				"x": Anim.impact_at("grip") * h.atk_dur})
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
	# meteors in the air
	if w.has("meteors"):
		var ms: Array = w["meteors"]
		for m in ms.duplicate():
			m["t"] = float(m["t"]) - delta
			if float(m["t"]) <= 0.0:
				ms.erase(m)
				_meteor_land(h, m["at"], str(m.get("src", "wrath")))
		if ms.is_empty():
			w.erase("meteors")
	# the Crucible: nothing moves or stops him
	if in_crucible(h):
		h.daze_t = 0.0
		h.shove = Vector3.ZERO
		h.knock_v = Vector3.ZERO
	_update_wrath(h, delta)
	if w.has("brand"):
		var b: Dictionary = w["brand"]
		for k in b.keys():
			if float(b[k]) <= h.anim_time:
				b.erase(k)

## Chained stages: when one stage's clip ends, the next starts (the charge's run, then its skid; the chain's haul,
## then the smash; the Crucible, then the eruption).
static func _stages(h: Hero) -> void:
	var w: Dictionary = h.dm
	var nxt: String = w.get("next_style", "")
	if nxt != "" and h.atk_t >= 0.0:
		return
	if nxt != "":
		w.erase("next_style")
		if h.dead:
			return
		_begin_stage(h, nxt)
		return
	if h.atk_t >= 0.0 or h.atk_skill != "":
		return

## Queue the stage after this one (it starts when this stage's clip ends); `now` ends this one at once.
static func _next_now(h: Hero, style: String, _hold: float) -> void:
	h.dm["next_style"] = style
	h.atk_t = h.atk_dur

static func _begin_stage(h: Hero, style: String) -> void:
	match style:
		"icharge":
			var c: Dictionary = h.dm.get("charge", {})
			if c.is_empty():
				return
			_start(h, "icharge", "icharge", float(c["dist"]) / CHARGE_SPEED / Data.attack_pace(h.cls) + 0.02)
			h.fx("icharge", "run", {"d": c["dir"]})
		"icharge_skid":
			_start(h, "icharge_skid", "icharge")
			h.fx("icharge", "skid", {"p": h.global_position, "d": h.dm.get("charge", {}).get("dir", h.aim_dir())})
		"grip_haul":
			var c: Dictionary = h.dm.get("chain", {})
			var dur: float = float(c.get("dur", DUR["grip_haul"])) if str(c.get("state", "")) == "drag" else 0.5
			_start(h, "grip_haul", "grip", dur / Data.attack_pace(h.cls))
		"grip":
			var v = h.dm.get("grip_victim")
			h.dm.erase("chain")
			if v == null or not is_instance_valid(v) or v.dead:
				return
			_start(h, "grip", "grip")
		"wrath_roar":
			_erupt_now(h)

## Hero._update_attack ended a stage: what follows it (called through ClassSkills when the attack finishes).
static func stage_done(h: Hero, style: String, skill: String) -> void:
	if h.dead:
		return
	match style:
		"icharge_wind":
			if skill == "icharge":
				h.dm["next_style"] = "icharge"
		"icharge":
			h.dm["next_style"] = "icharge_skid"
		"icharge_skid":
			h.dm.erase("charge")
			h.fx("icharge", "end", {"p": h.global_position})
		"grip_throw":
			var c: Dictionary = h.dm.get("chain", {})
			if not c.is_empty() and str(c["state"]) == "out":
				# the clip ended with the chain still out (it hooks nothing now): hauled back empty
				c["state"] = "back"
				h.fx("grip", "miss", {"p": h.global_position + (c["dir"] as Vector3) * float(c["len"])})
				h.dm["next_style"] = "grip_haul"
			elif c.is_empty():
				h.fx("grip", "end", {})
		"grip_haul":
			var c2: Dictionary = h.dm.get("chain", {})
			if str(c2.get("state", "")) == "drag":
				h.dm["next_style"] = "grip"
			else:
				h.dm.erase("chain")
				h.fx("grip", "end", {})
		"crucible":
			h.dm["next_style"] = "wrath_roar"

## The wrath's rain, which runs while he fights on.
static func _update_wrath(h: Hero, delta: float) -> void:
	var w: Dictionary = h.dm
	if not w.has("wrath"):
		return
	var n: Dictionary = w["wrath"]
	if h.dead:
		end_wrath(h, false)
		return
	n["t"] = float(n["t"]) + delta
	if float(n["rain"]) < 0.0:
		if h.atk_skill != "wrath" and not w.has("next_style"):
			end_wrath(h, false)       # cut short (death, a zone change) before the eruption
		return
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
## Everything of his that lingers: the fault, the chain, boulders and meteors in the air, the grip, the wrath
## (a class change, a new character, a zone change, death). Which arm throws the next boulder stays while he is
## still the Demon.
static func clear(h: Hero) -> void:
	var w: Dictionary = h.dm
	end_wrath(h, false)
	if w.has("charge"):
		w.erase("charge")
		h.fx("icharge", "end", {"p": h.global_position})
	DemonFx.clear(h)
	if h.atk_t >= 0.0 and h.atk_skill in STYLE:
		h.atk_t = -1.0
		h.atk_skill = ""
	var alt = w.get("hurl_alt")
	w.clear()
	if alt != null and h.is_demon():
		w["hurl_alt"] = alt

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
