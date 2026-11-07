class_name KnightSkills
extends RefCounted
## The Knight's skills (tuning in Data.SKILLS, effects in KnightFx). ClassSkills calls in; see class_skills.gd.
##  - Holy Slam (Q, "cleave"): he leaps toward the cursor (up to Hero.SLAM_RANGE) and brings the blade down
##    about Hero.SLAM_REACH ahead; everything round the blow is hit, thrown back and stunned.
##  - Holy Nova (E, "nova"): a ring of holy fire round him.
##  - Charge (R, "charge"): a dash through enemies, each smashed once and stunned. The dash replaces his walking
##    while it lasts (Hero._process calls `update_charge` while charge_t >= 0).
##  - Battle Cry (F, "cry"): +40% damage and defense for 12 s, and everything near is stunned.
## His state on the hero: slam_reach / slam_leap (the slam's lunge, Hero._swipe_lunge), charge_t / charge_dir /
## charge_hit (the dash).

static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	return true

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	match id:
		"cleave":
			# Holy Slam lands on the cursor (up to SLAM_RANGE away): he leaps far enough that the
			# blade, which strikes about SLAM_REACH in front of him, comes down right there
			var to := (aim - h.global_position) * Vector3(1, 0, 1)
			var dist := minf(to.length(), Hero.SLAM_RANGE)
			h.slam_reach = minf(dist, Hero.SLAM_REACH)
			h.slam_leap = dist - h.slam_reach
			h._start_attack("cleave", "cleave", 0.95)      # crouch, leap, slam, hold the blow, rise
		"nova":
			h._start_attack("cast", "nova")
			h.atk_dur = 0.55 * Data.attack_pace(h.cls)
		"charge":
			var d := aim - h.global_position
			d.y = 0
			h.charge_dir = d.normalized() if d.length() > 0.1 else h.aim_dir()
			h.charge_t = 0.0
			h.charge_hit = {}
			h.path = PackedVector3Array()
			h.moving = false
		"cry":
			h._start_attack("cast", "cry")
			h.atk_dur = 0.6 * Data.attack_pace(h.cls)
		# a run's skills (Data.RUN_SKILLS)
		"k_whirl":
			h._start_attack("swipe3", "k_whirl")
		"k_aegis":
			h._start_attack("cast", "k_aegis")
			h.atk_dur = 0.5 * Data.attack_pace(h.cls)
		"k_judgment":
			var to2 := (aim - h.global_position) * Vector3(1, 0, 1)
			h.atk_aim = h.global_position + to2.limit_length(14.0)
			h._start_attack("cast", "k_judgment")
		"k_rites":
			# a leap like Holy Slam's onto the foe nearest the pointer
			var foe = null
			var fd := 3.5
			for e in h.game.enemies_near(aim, 3.5):
				var dd: float = e.global_position.distance_to(aim)
				if not e.dead and dd < fd:
					fd = dd
					foe = e
			var tgt: Vector3 = foe.global_position if foe != null else aim
			var to3 := (tgt - h.global_position) * Vector3(1, 0, 1)
			var dist := minf(to3.length(), 9.0)
			h._face(to3)
			h.atk_aim = h.global_position + to3.normalized() * dist if to3.length() > 0.1 else aim
			h.slam_reach = minf(dist, Hero.SLAM_REACH)
			h.slam_leap = dist - h.slam_reach
			h._start_attack("cleave", "k_rites", 0.85)

## The impact frame of one of his skills (Hero then refreshes the stats); false when it isn't his.
static func impact(h: Hero) -> bool:
	var fwd := h.aim_dir()
	match h.atk_skill:
		"cleave":
			# Holy Slam: the slam lands just ahead; everything around the blow is hit and thrown back
			var at := h.global_position + fwd * h.slam_reach
			at.y = h.game.world.height_at(at.x, at.z)
			var any := false
			var ps := PackedVector3Array()
			for e in h.game.enemies_near(at, 3.6):
				var to: Vector3 = e.global_position - at
				to.y = 0
				if to.length() - e.radius <= 2.6:
					h._hit_enemy(e, 1.6, 0.6)     # knocked back a little
					if is_instance_valid(e) and not e.dead:
						e.stun(1.0)
					ps.append(e.global_position + Vector3(0, 1.0, 0))
					any = true
			h.fx("cleave", "slam", {"p": at, "ps": ps, "x": any})
		"nova":
			var nd := 18.0 + h.level * 5.0 + (h.dmg_min + h.dmg_max) * 0.4
			h.fx("nova", "impact")
			nd *= h.buff_mult() * h.dmg_mult("nova")
			var burned := 0
			for e in h.game.enemies_near(h.global_position, 7.0):
				e.take_damage(0.0, nd, h.global_position, 1.2, false)
				burned += 1
			if h.talent("nova_heal") > 0.0 and burned > 0:
				h.life = minf(h.max_life, h.life + h.max_life * h.talent("nova_heal") / 100.0 * mini(burned, 5))
		"cry":
			h.buff_t = 12.0 + h.talent("buff_dur")
			if h.talent("cry_heal") > 0.0:
				h.life = minf(h.max_life, h.life + h.max_life * h.talent("cry_heal") / 100.0)
			h.fx("cry", "impact")
			for e in h.game.enemies_near(h.global_position, 6.0):
				e.stun(2.0)
		"k_whirl":
			var spins := 2 + int(h.talent("whirl_more"))
			h.fx("k_whirl", "impact", {"n": spins})
			for i in spins:
				if i == 0:
					_whirl_hit(h)
				else:
					h.get_tree().create_timer(0.22 * i).timeout.connect(func():
						if is_instance_valid(h) and not h.dead:
							_whirl_hit(h))
		"k_aegis":
			var pct := 35.0 + h.talent("aegis_pct")
			RunTalents.buff(h, "aegis", {"ward_bonus": pct}, AEGIS_T)
			h.ward = h.ward_max
			h.set_meta("aegis", {"ward0": h.ward, "t": AEGIS_T})
			var near: Array = h.game.enemies_near(h.global_position, 5.0).filter(func(e): return not e.dead)
			h.fx("k_aegis", "impact", {"t": near})
			for e in near:
				e.taunt = h
				e.taunt_t = 4.0
		"k_judgment":
			var g := h.atk_aim
			g.y = h.game.world.height_at(g.x, g.z)
			var pts := [g]
			for i in int(h.talent("judgment_more")):
				var a := TAU * float(i) / maxf(1.0, h.talent("judgment_more")) + 0.6
				var q := g + Vector3(cos(a), 0, sin(a)) * 3.2
				q.y = h.game.world.height_at(q.x, q.z)
				pts.append(q)
			var avg: float = (h.dmg_min + h.dmg_max) * 0.5
			var struck := {}
			var lit := PackedVector3Array()
			for q in pts:
				for e in h.game.enemies_near(q, JUDGE_R):
					if e.dead or struck.has(e):
						continue
					struck[e] = true
					var n := brands(e)
					if n > 0:
						lit.append(e.global_position + Vector3(0, 1.2, 0))
					e.set_meta("brand", 0)
					h._hit_enemy(e, 1.2 + JUDGE_PER_BRAND * n, 0.5, "k_judgment")
					if not e.dead:
						e.ignite(avg * 0.3 * h.buff_mult() * h.dmg_mult("k_judgment"), 3.0)
			h.fx("k_judgment", "impact", {"ps": PackedVector3Array(pts), "q": lit[0] if not lit.is_empty() else g, "n": lit.size()})
		"k_rites":
			var at: Vector3 = h.global_position + h.aim_dir() * h.slam_reach
			at.y = h.game.world.height_at(at.x, at.z)
			var killed := false
			var hit_any := false
			for e in h.game.enemies_near(at, 2.8):
				if e.dead:
					continue
				var missing: float = 1.0 - e.life / maxf(1.0, e.max_life)
				h._hit_enemy(e, 1.5 + 2.0 * missing, 0.4, "k_rites")
				hit_any = true
				if e.dead:
					killed = true
			h.fx("k_rites", "impact", {"p": at, "x": killed})
			if killed:
				h.cds["k_rites"] = 0.0
				if h.talent("rites_buff") > 0.0:
					RunTalents.buff(h, "no_quarter", {"dmg": 30.0, "frw": 20.0}, 4.0)
		_:
			return false
	return true

const JUDGE_R := 3.0
const JUDGE_PER_BRAND := 0.45
const WHIRL_R := 3.2
const AEGIS_T := 5.0
const AEGIS_R := 5.0
const BRAND_MAX := 5
const BRAND_T := 6.0

## Holy Brands (a run knight's mark, Judgment's fuel): every blow of his leaves one on its foe, up to BRAND_MAX
## (+ Searing Brands), each lasting BRAND_T; shown as gold motes over it.
static func brand(h: Hero, e) -> void:
	if e == null or not is_instance_valid(e) or e.dead or e.pvp_obj > 0:
		return
	var now := Time.get_ticks_msec()
	var n := brands(e)
	var most := BRAND_MAX + int(h.talent("brand_max"))
	n = mini(most, n + 1)
	e.set_meta("brand", n)
	e.set_meta("brand_until", now + int(BRAND_T * 1000.0))
	if h.talent("brand_burn") > 0.0:
		e.ignite((h.dmg_min + h.dmg_max) * 0.04 * n, 2.0)
	if not e.has_node("brand_fx"):
		var a := Fx.aura(e, HolyFx.GOLD, 10, 0.2, 0.07, 0.9, 0.4, 0.35, 30.0, Vector3(0, float(e.get("height")) * 2.0 + 0.3, 0))
		a.name = "brand_fx"
		Fx._free_later(a, BRAND_T)

static func brands(e) -> int:
	if not e.has_meta("brand") or Time.get_ticks_msec() > int(e.get_meta("brand_until", 0)):
		return 0
	return int(e.get_meta("brand"))

## Aegis: the ward running out or broken bursts for what it soaked (Hero._process, through update).
static func aegis_update(h: Hero, delta: float) -> void:
	var a: Dictionary = h.get_meta("aegis")
	a["t"] = float(a["t"]) - delta
	if float(a["t"]) > 0.0 and h.ward > 0.5:
		return
	h.remove_meta("aegis")
	var soaked := maxf(0.0, float(a["ward0"]) - h.ward) * (2.0 if h.talent("aegis_pct") > 0.0 else 1.0)
	h.fx("k_aegis", "burst", {"p": h.global_position, "x": soaked})
	Hero.striker = h
	for e in h.game.enemies_near(h.global_position, AEGIS_R):
		if not e.dead:
			e.take_damage(0.0, soaked * h.buff_mult(), h.global_position, 1.0, false)

## One turn of Blade Storm: everything round him.
static func _whirl_hit(h: Hero) -> void:
	Hero.striker = h
	for e in h.game.enemies_near(h.global_position, WHIRL_R):
		if not e.dead:
			h._hit_enemy(e, 0.7, 0.3, "k_whirl")

## Charge: replaces his walking while it lasts (Hero._process).
static func update_charge(h: Hero, delta: float) -> void:
	h.charge_t += delta
	var dist := 18.0 * delta
	var np: Vector3 = h.game.world.move(h.global_position, h.charge_dir * dist)
	var moved := np - h.global_position
	moved.y = 0
	h.global_position = np
	h._face(h.charge_dir)
	h.phase += delta * 20.0
	for e in h.game.enemies_near(h.global_position, 1.6):
		if not h.charge_hit.has(e.get_instance_id()):
			h.charge_hit[e.get_instance_id()] = true
			h._hit_enemy(e, 1.3, 2.5, "charge")
			e.stun(0.8)
			# Relentless: each enemy smashed takes time off the other cooldowns
			if h.talent("charge_cdr") > 0.0:
				for k in h.cds:
					if k != "charge":
						h.cds[k] = maxf(0.0, h.cds[k] - h.talent("charge_cdr"))
			h.fx("charge", "hit", {"p": e.global_position, "x": h.charge_hit.size() == 1})
	if h.charge_t > 0.5 or moved.length() < dist * 0.3:
		h.charge_t = -1.0
		h.fx("charge", "end")

static func update(h: Hero, delta: float) -> void:
	if h.has_meta("aegis") and not h.puppet:
		aegis_update(h, delta)
	pass

static func rooted(_h: Hero) -> bool:
	return false

static func clear(_h: Hero) -> void:
	pass

static func died(_h: Hero) -> void:
	pass

static func sound(_h: Hero, skill: String, at: float) -> bool:
	match skill:
		"cleave":
			Sfx.play_synced("cleave_swing", at, -2.0)
		"nova":
			Sfx.play_synced("holy_nova", at, 0.0)
			Sfx.duck(-8.0, 1.0)
		_:
			return false
	return true
