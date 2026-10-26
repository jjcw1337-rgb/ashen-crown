class_name DemonMinion
extends Node3D
## A demon summoned by the Demon class. It fights beside its master: picks the nearest monster
## near its master, runs in, claws it, and otherwise trails behind in formation. Monsters do not
## target it. It lasts until replaced, its master dies, or it is dismissed.

var master: Node3D           # the Hero that summoned it
var game: Node
var slot := 0                # formation slot 0..2
var rig: Node3D
var target = null
var atk_t := -1.0
var atk_dur := 0.8
var hit_done := false
var phase := 0.0
var move_amt := 0.0
var anim_time := 0.0
var rise := 0.0              # 0 = still climbing out of the ground, 1 = up
var empowered := 0.0         # seconds left of Blood Pact's boost
var aura: GPUParticles3D

const SPEED := 5.6
const LEASH := 9.0

func setup(m: Node3D, g: Node, s: int) -> void:
	master = m
	game = g
	slot = s
	var look := {"skin": Color(0.36, 0.04, 0.03), "cloth": Color(0.06, 0.03, 0.03), "armor": Color(0.06, 0.05, 0.055),
		"height": 0.95, "bulk": 1.05, "head": "demon", "eyes": Color(1.0, 0.7, 0.15), "wings": true, "tail": true, "spikes": true}
	rig = Models.humanoid(look)
	rig.set_meta("pers", "fallen")
	add_child(rig)
	_ember_edges()
	rig.position.y = -1.9
	aura = DemonFx.ember_aura()
	aura.position = Vector3(0, 0.1, 0)
	add_child(aura)

## Claws and horn tips glow ember like the master's gear.
func _ember_edges() -> void:
	var J: Dictionary = rig.get_meta("j")
	var col := Demon.EMBER
	for hand in ["hand_r", "hand_l"]:
		var hn: Node3D = J[hand]
		for i in 3:
			var c := Models.P(hn, Geo.cone(0.009, 0.08, 6), Demon.edge_mat(col, -0.01, 0.04), Vector3((i - 1) * 0.018, -0.09, -0.02), Vector3(180 + 20, 0, (i - 1) * 9.0))
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hd: Node3D = J["head"]
	for sx in [-1, 1]:
		var tip := Models.P(hd, Geo.cone(0.014, 0.05, 6), Mats.glow(col, 4.0), Vector3(sx * 0.15, 0.24, 0.02), Vector3(0, 0, -sx * 50))
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sh in ["sh_r", "sh_l"]:
		var sx: float = 1.0 if sh == "sh_r" else -1.0
		var sp := Models.P(J[sh], Geo.cone(0.025, 0.14, 7), Demon.edge_mat(col, 0.0, 0.07), Vector3(sx * 0.07, 0.08, 0), Vector3(0, 0, -sx * 35))
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func dismiss() -> void:
	if game and game.world:
		Fx.burst(game.world.fx_root, global_position + Vector3(0, 0.9, 0), Color(1.0, 0.3, 0.05), 24, 3.0, 0.12, 0.6, true, 1.0)
		Fx.burst(game.world.fx_root, global_position + Vector3(0, 0.6, 0), Color(0.08, 0.02, 0.02, 0.8), 14, 1.6, 0.3, 0.8, false, 1.5)
	queue_free()

func _formation_spot() -> Vector3:
	var back: Vector3 = (master as Node3D).get("rig").global_transform.basis.z
	var side := Vector3(back.z, 0, -back.x)
	var offs := [Vector3.ZERO, side * 1.3, -side * 1.3]
	return master.global_position + back * (1.6 if slot == 0 else 1.1) + offs[slot]

func _process(delta: float) -> void:
	if not is_instance_valid(master) or master.get("dead") or game == null or game.world == null or game._busy:
		return
	anim_time += delta
	empowered = maxf(0.0, empowered - delta)
	aura.emitting = empowered > 0.0
	if rise < 1.0:
		rise = minf(1.0, rise + delta * 1.6)
		rig.position.y = -1.9 * pow(1.0 - rise, 2.0)
		Anim.pose(rig, {"time": anim_time, "phase": phase, "move": 0.0, "atk": -1.0, "style": "claw"})
		global_position.y = game.world.height_at(global_position.x, global_position.z)
		return
	# a master who walked through a portal: catch up
	if global_position.distance_to(master.global_position) > 22.0:
		global_position = _formation_spot()
	if target != null and (not is_instance_valid(target) or target.dead or target.global_position.distance_to(master.global_position) > LEASH + 3.0):
		target = null
	if target == null:
		var best = null
		var bd := LEASH
		for e in game.enemies_near(master.global_position, LEASH):
			var d: float = e.global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = e
		target = best
	var vel := Vector3.ZERO
	if atk_t >= 0.0:
		atk_t += delta
		var a := atk_t / atk_dur
		if not hit_done and a >= Anim.impact_at("claw"):
			hit_done = true
			_strike()
		if atk_t >= atk_dur:
			atk_t = -1.0
	if target != null:
		var to: Vector3 = target.global_position - global_position
		to.y = 0
		var reach: float = target.radius + 0.95
		if to.length() > reach:
			vel = to.normalized() * SPEED * (1.25 if empowered > 0.0 else 1.0)
		elif atk_t < 0.0:
			atk_t = 0.0
			hit_done = false
			atk_dur = 0.8 if empowered <= 0.0 else 0.6
		_face(to)
	else:
		var to2 := _formation_spot() - global_position
		to2.y = 0
		if to2.length() > 0.6:
			vel = to2.normalized() * SPEED * clampf(to2.length() / 2.0, 0.4, 1.3)
			_face(vel)
	if vel.length() > 0.01:
		global_position = game.world.move(global_position, vel * delta)
		move_amt = move_toward(move_amt, clampf(vel.length() / SPEED, 0.0, 1.2), delta * 6.0)
		phase += delta * vel.length() * 1.7
	else:
		move_amt = move_toward(move_amt, 0.0, delta * 6.0)
	global_position.y = game.world.height_at(global_position.x, global_position.z)
	Anim.pose(rig, {"time": anim_time, "phase": phase, "move": move_amt, "atk": (atk_t / atk_dur) if atk_t >= 0.0 else -1.0, "style": "claw", "hit": 0.0})

func _face(d: Vector3) -> void:
	d.y = 0
	if d.length() > 0.01:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-d.x, -d.z), 0.3)

## Claw hit: part of the master's weapon damage plus fire, more under Blood Pact.
func _strike() -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var avg: float = (float(master.get("dmg_min")) + float(master.get("dmg_max"))) * 0.5
	var lvl: int = int(master.get("level"))
	var d := avg * 0.45 + lvl * 2.5 + 4.0
	if empowered > 0.0:
		d *= 1.6
	target.take_damage(d, d * 0.35, global_position, 0.4, false)
	Fx.burst(game.world.fx_root, target.global_position + Vector3(0, 1.0 * target.height, 0), Color(1.0, 0.45, 0.1), 12, 3.5, 0.08, 0.3, true, -4.0)
	Sfx.play("hit", -7.0, randf_range(1.2, 1.4))
