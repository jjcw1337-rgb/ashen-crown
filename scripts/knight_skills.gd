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
		_:
			return false
	return true

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

static func update(_h: Hero, _delta: float) -> void:
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
