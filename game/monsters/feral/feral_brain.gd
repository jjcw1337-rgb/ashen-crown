class_name FeralBrain
extends RefCounted
## The Feral's brain (host side): it waits perched on a tree trunk (perch, till a hero comes near: then the whole pack
## drops, a beat apart), and in a fight the pack circles and lunges one at a time (combat). Enemy calls it for a Feral.

static func perch(en: Enemy, delta: float, hero: Node3D, dist: float) -> void:
	if en.atk_style == "perch":
		var near: bool = dist < 10.0 and not hero.dead and hero.get("phased") != true and en.game.world.los(en.global_position, hero.global_position)
		if near or en.aggro:
			FeralBrain.drop(en)
			for e in en.game.enemies_near(en.global_position, 32.0):
				if e != en and e.pack_id == en.pack_id and e.perch_h > 0.0 and e.atk_style == "perch":
					e.f_t = -randf_range(0.1, 0.6)      # a beat apart, not all at once
					FeralBrain.drop(e)
	else:
		en.atk_t += delta
		if en.atk_t >= en.atk_dur:
			en.perch_h = 0.0
			en.atk_t = -1.0
			en.atk_dur = en.def["atk_time"]
			en.atk_style = en.def["atk"]
			en.rig.rotation.x = 0.0
			# off the bark and clear of the trunk's footprint
			en.global_position = en.game.world.free_spot_near(en.global_position + en.perch_dir * 0.9, 1.2)
			en.global_position.y = en.game.world.height_at(en.global_position.x, en.global_position.z)
			en.aggro = true
			en.cooldown = 0.4
			return
	var a := maxf(en.atk_t, 0.0) / en.atk_dur
	var y: float = en.game.world.height_at(en.global_position.x, en.global_position.z)
	en.global_position.y = y + Feral.perch_pose(en.rig, en.atk_style, a)
	en._pose({"time": en.anim_time, "atk": a, "style": en.atk_style, "phase": en.phase})

static func drop(en: Enemy) -> void:
	en.atk_style = "descend"
	en.atk_dur = Feral.DESCEND_T
	en.atk_t = minf(en.f_t, 0.0)
	en.f_t = 0.0
	en.aggro = true
	Sfx.play_at("growl", en.global_position, -10.0, randf_range(1.15, 1.35))

## Fast, and coming at you from its own side. The pack circles about 4.5 m out; one at a time lunges,
## backs off a few steps ("back"), darts in for a rake or two with its claws ("in"), then backs out to
## the circle again ("out") for the next one's turn.
static func combat(en: Enemy, delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	en.lunge_cd -= delta
	# outrun for 6 s: it gives up and slinks back to its tree
	en.f_chase = en.f_chase + delta if dist > 9.0 else 0.0
	if en.f_chase > 6.0:
		en.f_chase = 0.0
		en.f_state = ""
		en.aggro = false
		en.f_calm = 8.0
		en.wander_to = en.home
		en.wander_t = 4.0
		return Vector3.ZERO
	match en.f_state:
		"back", "out":
			en.f_t -= delta
			if en.f_t <= 0.0:
				en.f_state = "in" if en.f_state == "back" else ""
				en.f_n = 0
			return -to.normalized() * en.speed * 0.5
		"in":
			if dist <= en.def["range"] + hero.radius * 0.5:
				if en.cooldown <= 0.0:
					if en.f_n >= 2 or (en.f_n >= 1 and randf() < 0.5):
						en.f_state = "out"
						en.f_t = randf_range(0.8, 1.2)
						return Vector3.ZERO
					en.f_n += 1
					en._face(to)
					en.atk_dur = en.def["atk_time"]
					en._begin_attack("")
				return Vector3.ZERO
			return en.go_to(delta, hero.global_position, en.speed)
	# circling: anyone who ends up right on top of you claws anyway
	if dist <= en.def["range"] + hero.radius * 0.5 and en.cooldown <= 0.0:
		en.f_state = "in"
		en.f_n = 0
		return Vector3.ZERO
	if en.lunge_cd <= 0.0 and dist > 3.2 and dist < 7.5 and not FeralBrain.pack_lunging(en) and en.game.world.los(en.global_position, hero.global_position):
		en.lunge_cd = 5.0
		en._face(to)
		en.rig.rotation.y = atan2(-to.x, -to.z)
		en.lunge_from = en.global_position
		en.lunge_to = hero.global_position - to.normalized() * (en.radius + hero.radius + 0.3)
		en._begin_special("feral_lunge")
		return Vector3.ZERO
	var from_hero := (-to).normalized().rotated(Vector3.UP, en.slot_a)
	return en.go_to(delta, hero.global_position + from_hero * 4.5, en.speed)

static func pack_lunging(en: Enemy) -> bool:
	for e in en.game.enemies_near(en.global_position, 16.0):
		if e != en and e.pack_id == en.pack_id and e.special == "feral_lunge" and e.atk_t >= 0.0:
			return true
	return false
