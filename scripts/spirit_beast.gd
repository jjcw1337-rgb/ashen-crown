class_name SpiritBeast
extends Node3D
## The archer's Spirit Beast (archer.gd): a spectral beast (the arena lion's body, pale and glowing; the
## code-built crawler without it) that hunts beside its master for Archer.BEAST_TIME seconds: it runs at
## the monster nearest its master, mauls it, and otherwise trots at his side. Monsters ignore it.

var master: Hero
var game: Node
var slot := 0
var rig: Node3D
var target = null
var atk_t := -1.0
var atk_dur := 0.8
var hit_done := false
var phase := 0.0
var move_amt := 0.0
var anim_time := 0.0
var life_t := Archer.BEAST_TIME
var lion := false

const SPEED := 7.0
const LEASH := 11.0
const HEIGHT := 1.2

func setup(m: Hero, g: Node, s: int) -> void:
	master = m
	game = g
	slot = s
	lion = Lion.ok()
	if lion:
		rig = Lion.build()
		rig.scale = Vector3.ONE * 0.85
	else:
		rig = Models.crawler({"skin": Color(0.5, 0.7, 0.65), "shell": Color(0.4, 0.6, 0.55), "legs": 4, "size": 1.0, "eyes": Archer.HUNTER})
	add_child(rig)
	# ghostly: a pale glow over the body and a light that goes with it
	var ghost := Mats.glow(Archer.HUNTER, 0.9, 0.0, 1.0)
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = ghost
		(mi as MeshInstance3D).transparency = 0.25
	var l := OmniLight3D.new()
	l.light_color = Archer.HUNTER
	l.light_energy = 0.8
	l.omni_range = 4.0
	l.position = Vector3(0, 1.0, 0)
	add_child(l)
	var trail := Fx.aura(self, Archer.HUNTER, 20, 0.4, 0.1, 0.9, 0.3, 0.5, 60.0, Vector3(0, 0.7, 0))
	trail.name = "trail"

func dismiss() -> void:
	if game and game.world:
		Fx.burst(game.world.fx_root, global_position + Vector3(0, 0.7, 0), Archer.HUNTER, 26, 3.0, 0.14, 0.8, true, 1.5)
	queue_free()

func _side_spot() -> Vector3:
	var back: Vector3 = master.rig.global_transform.basis.z
	var side := Vector3(back.z, 0, -back.x) * (1.4 if slot == 0 else -1.4)
	return master.global_position + side + back * 0.6

func _process(delta: float) -> void:
	if not is_instance_valid(master) or master.dead or game == null or game.world == null or game._busy:
		return
	anim_time += delta
	life_t -= delta
	if life_t <= 0.0:
		master.beasts.erase(self)
		dismiss()
		return
	if global_position.distance_to(master.global_position) > 24.0:
		global_position = _side_spot()
	if target != null and (not is_instance_valid(target) or target.dead or target.global_position.distance_to(master.global_position) > LEASH + 3.0):
		target = null
	if target == null:
		var best = null
		var bd := LEASH
		for e in game.enemies_near(master.global_position, LEASH):
			var d: float = e.global_position.distance_to(global_position)
			if not e.dead and d < bd:
				bd = d
				best = e
		target = best
	var vel := Vector3.ZERO
	if atk_t >= 0.0:
		atk_t += delta
		if not hit_done and atk_t / atk_dur >= Anim.impact_at("feral_swipe"):
			hit_done = true
			_strike()
		if atk_t >= atk_dur:
			atk_t = -1.0
	if target != null:
		var to: Vector3 = target.global_position - global_position
		to.y = 0
		if to.length() > target.radius + 1.1:
			vel = to.normalized() * SPEED
		elif atk_t < 0.0:
			atk_t = 0.0
			hit_done = false
		_face(to)
	else:
		var to2 := _side_spot() - global_position
		to2.y = 0
		if to2.length() > 0.6:
			vel = to2.normalized() * SPEED * clampf(to2.length() / 2.5, 0.4, 1.3)
			_face(vel)
	if vel.length() > 0.01:
		global_position = game.world.move(global_position, vel * delta)
		move_amt = move_toward(move_amt, clampf(vel.length() / SPEED, 0.0, 1.2), delta * 6.0)
		phase += delta * vel.length() * (1.6 / HEIGHT)
	else:
		move_amt = move_toward(move_amt, 0.0, delta * 6.0)
	global_position.y = game.world.height_at(global_position.x, global_position.z)
	var st := {"time": anim_time, "phase": phase, "move": move_amt, "atk": (atk_t / atk_dur) if atk_t >= 0.0 else -1.0, "style": "feral_swipe", "hit": 0.0}
	if lion:
		Lion.pose(rig, st, HEIGHT)
	else:
		Anim.pose(rig, st)

func _face(d: Vector3) -> void:
	d.y = 0
	if d.length() > 0.01:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-d.x, -d.z), 0.3)

## A maul: half its master's weapon damage and more with his level, with his Spirit Bond talents.
func _strike() -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var avg: float = (master.dmg_min + master.dmg_max) * 0.5
	var d := (avg * 0.5 + master.level * 3.0 + 5.0) * master.dmg_mult("beast")
	target.take_damage(d, 0.0, global_position, 0.5, false)
	Fx.burst(game.world.fx_root, target.global_position + Vector3(0, target.height, 0), Archer.HUNTER, 12, 3.0, 0.08, 0.35, true, -3.0)
