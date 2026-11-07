class_name FallenBrain
extends RefCounted
## The three Fallen's brains (host side): the skirmisher's darting, the reaver's charge, the stalker's flanking, and the
## lunge path they share (path). Enemy calls them for a fallen_skirmisher, fallen_reaver or fallen_stalker.

## Each signature attack's path, from where it starts toward its target: the Skirmisher launches at you and
## stumbles on through; the Reaver plants his feet (no path); the Stalker shifts sideways, darts in at an
## angle and pulls back out.
static func path(en: Enemy, sp: String) -> void:
	en.atk_path = []
	var hero: Node3D = en.game.target_for(en)
	if hero == null:
		return
	var hp: Vector3 = hero.global_position
	var p0 := en.global_position
	var to := hp - p0
	to.y = 0
	var dir := to.normalized() if to.length() > 0.05 else -en.rig.global_transform.basis.z
	var reach: float = en.radius + hero.radius
	match sp:
		"skirm_lunge":
			var land := p0 + dir * clampf(to.length() - reach - 0.15, 0.0, 4.5)
			en.atk_path = [[0.3, 0.5, p0, land], [0.5, 0.62, land, land + dir * 0.45]]
		"stalk_hook":
			var side := Vector3(-dir.z, 0, dir.x) * en.fv_side
			var p1 := p0 + side * 1.5
			var from_h := (p1 - hp)
			from_h.y = 0
			var app := from_h.normalized().rotated(Vector3.UP, en.fv_side * 0.7) if from_h.length() > 0.05 else -dir
			var p2 := hp + app * (reach + 0.3)
			var out := (p2 - hp)
			out.y = 0
			var p3 := p2 + (out.normalized() if out.length() > 0.05 else -dir) * 1.5
			en.atk_path = [[0.0, 0.25, p0, p1], [0.25, 0.44, p1, p2], [0.55, 1.0, p2, p3]]

## The Skirmisher: comes straight in, fast; from about 5 m it coils and launches the Savage Lunge, then
## stands a moment (the opening); too close to lunge, it hops back a step first.
static func skirmisher(en: Enemy, delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	if en.f_state == "recover":
		en.f_t -= delta
		if en.f_t > 0.0:
			en._face(to)
			return Vector3.ZERO
		en.f_state = ""
	var reach: float = en.radius + hero.radius
	if en.cooldown <= 0.0 and dist < 5.2 and dist > reach + 0.5 and en.game.world.los(en.global_position, hero.global_position):
		en._face(to)
		en._begin_special("skirm_lunge")
		return Vector3.ZERO
	if dist < reach + 0.5:
		return -to.normalized() * en.speed * 0.7
	return en.go_to(delta, hero.global_position, en.speed * 1.1)

## The Reaver: walks in steadily, slow to get going and slow to turn; in reach he plants and cleaves, then
## stands for a second with the axe low.
static func reaver(en: Enemy, delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	if en.f_state == "rest":
		en.f_t -= delta
		if en.f_t > 0.0:
			return Vector3.ZERO
		en.f_state = ""
	if dist <= 2.4 + hero.radius * 0.5 and en.cooldown <= 0.0:
		en._begin_special("reaver_cleave")
		return Vector3.ZERO
	if dist < en.radius + hero.radius + 0.2:
		return Vector3.ZERO
	en.rv_spd = move_toward(en.rv_spd, en.speed, delta * 1.8)
	return en.go_to(delta, hero.global_position, en.rv_spd)

## The Stalker: circles 4-6 m out on a side it picks (switching now and then), weaving as it goes, edging in
## on an arc; when ready it shifts, darts in at an angle and hooks, then pulls out and circles again.
static func stalker(en: Enemy, delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	en.fv_flip -= delta
	if en.fv_flip <= 0.0:
		en.fv_flip = randf_range(1.0, 2.0)
		if randf() < 0.45:
			en.fv_side = -en.fv_side
	en.f_t -= delta
	var reach: float = en.radius + hero.radius
	if en.cooldown <= 0.0 and en.f_t <= 0.0 and dist < 6.0 and dist > reach + 0.3 and en.game.world.los(en.global_position, hero.global_position):
		en._begin_special("stalk_hook")
		return Vector3.ZERO
	var ring := 5.0 if (en.cooldown > 0.0 or en.f_t > 0.0) else 3.8
	var from_h := en.global_position - hero.global_position
	from_h.y = 0
	var base := atan2(from_h.z, from_h.x)
	var want := base + en.fv_side * 0.55
	var tgt: Vector3 = hero.global_position + Vector3(cos(want), 0, sin(want)) * ring
	var v := en.go_to(delta, tgt, en.speed)
	# the weave: a smooth sideways sway over the arc (its side flips with fv_side, so it reads as intent)
	en.fv_weave += delta * 2.6
	var side := Vector3(-to.z, 0, to.x).normalized() if to.length() > 0.05 else Vector3.ZERO
	return v + side * sin(en.fv_weave) * en.speed * 0.3 * en.fv_side

# ---------------------------------------------------------------- their moves (Monsters.begin_move ... finish_move)
## Each signature attack moves the body along its own path (no snapping into range).
static func begin(en: Enemy, sp: String) -> void:
	en.atk_style = sp
	en.atk_dur = en.def["atk_time"]
	en.tele_done = false
	en.begin_attack(sp)
	path(en, sp)

static func during(en: Enemy, a: float, hero: Node3D) -> void:
	match en.special:
		"skirm_lunge":
			if a < 0.3:
				en._face(hero.global_position - en.global_position)
		"reaver_cleave":
			if a < 0.15:
				en._face(hero.global_position - en.global_position)
			elif not en.tele_done:
				en.tele_done = true
				en._fx("reaver_tele")
		"stalk_hook":
			if a > 0.22 and a < 0.45:
				en._face(hero.global_position - en.global_position)

static func impact(en: Enemy, hero: Node3D, _dist: float) -> void:
	var fwd := -en.rig.global_transform.basis.z
	match en.special:
		"skirm_lunge", "stalk_hook":
			# one blow, on the target, only if it is still there and in front
			if is_instance_valid(hero) and not hero.dead:
				var th: Vector3 = hero.global_position - en.global_position
				th.y = 0
				var reach: float = en.radius + hero.radius + (1.0 if en.special == "skirm_lunge" else 1.1)
				if th.length() <= reach and fwd.dot(th.normalized()) > (0.3 if en.special == "skirm_lunge" else 0.2):
					hero.take_hit(en.roll(), en.global_position, "melee")
		"reaver_cleave":
			# everyone in the 120-degree arc out to 2.6 m is caught
			for h in en.game.all_heroes():
				if h.dead:
					continue
				var tc: Vector3 = h.global_position - en.global_position
				tc.y = 0
				if tc.length() < 2.6 + en.radius * 0.5 and (tc.length() < 0.3 or fwd.dot(tc.normalized()) > 0.5):
					h.take_hit(en.roll(), en.global_position, "melee")
			en.game.add_shake(0.15)

## Committed: a real opening after each move.
static func finish(en: Enemy) -> void:
	match en.special:
		"skirm_lunge":
			en.cooldown = randf_range(1.3, 1.7)
			en.f_state = "recover"
			en.f_t = randf_range(0.45, 0.65)
		"reaver_cleave":
			en.cooldown = randf_range(1.1, 1.5)
			en.f_state = "rest"
			en.f_t = 1.0
			en.rv_spd = en.speed * 0.3
		"stalk_hook":
			en.cooldown = randf_range(1.6, 2.2)
			en.f_t = 1.0
			en.fv_side = -en.fv_side if randf() < 0.5 else en.fv_side
