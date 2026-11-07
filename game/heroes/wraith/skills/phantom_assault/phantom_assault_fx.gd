class_name PhantomAssaultFx
extends RefCounted
## Phantom Assault's look on every game (PhantomAssault is its rules, whose own phantoms deal the blows). Draws only:
##  "split" {d: ahead, n: how many}: afterimages of him split off and streak out in a fan, flown here
##    (h.fxs["phantoms"], `update`) the way its rules fly theirs, coming apart at their range or a wall;
##  "hit" {p, d}: a phantom tearing through a foe; "strike" {y}: his own claws after them.

const SPIRIT := SpiritFx.SPIRIT
const VIOLET := SpiritFx.VIOLET
const PALE := SpiritFx.PALE

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var pos := h.global_position
	match str(ev["e"]):
		"cast":
			pass
		"split":
			var fwd: Vector3 = ev["d"]
			var count: int = int(ev.get("n", 3))
			var spread := deg_to_rad(Skill.num("phantom", "spread", 22.0))
			var reach := _reach()
			var ps: Array = h.fxs.get("phantoms", [])
			for i in count:
				var ang := (float(i) - (count - 1) * 0.5) * spread
				var dir := fwd.rotated(Vector3.UP, ang)
				var g := SpiritFx.afterimage(h.rig, root, VIOLET.lerp(SPIRIT, 0.3), reach / _speed() + 0.25, 0.2)
				if g == null:
					continue
				g.rotation.y = atan2(-dir.x, -dir.z)
				g.rotation.x = 0.0
				var tr := SpiritFx.trail(VIOLET, 0.16, 30, 0.45)
				tr.position = Vector3(0, 1.0, 0)
				g.add_child(tr)
				ps.append({"node": g, "dir": dir, "left": reach, "lean": 0.0})
			h.fxs["phantoms"] = ps
			split(root, pos)
			SkillFx.snd(h, "host_summon", -5.0, 1.15)
			SkillFx.shake(h, 0.18)
		"hit":
			var p: Vector3 = ev["p"]
			phantom_hit(root, p, ev["d"])
			Sfx.play_at("spirit_dart", p, -5.0)
		"strike":
			SpiritFx.rake(root, pos, float(ev["y"]), 2.8, true)
			SkillFx.shake(h, 0.15)
		_:
			return false
	return true

static func _reach() -> float:
	return float(Data.skill_def("phantom").get("range", 8.0))

static func _speed() -> float:
	return Skill.num("phantom", "speed", 15.0)

## Every frame (his own game and his puppet's): the phantoms streak on until their range or a wall, and come apart.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("phantoms"):
		return
	var ps: Array = h.fxs["phantoms"]
	var world = h.game.world
	for p in ps.duplicate():
		var g = p["node"]
		if not is_instance_valid(g):
			ps.erase(p)
			continue
		var step := _speed() * delta
		var pos: Vector3 = g.global_position
		var np: Vector3 = world.move(pos, (p["dir"] as Vector3) * step, 0.3)
		var moved := np - pos
		moved.y = 0
		np.y = world.height_at(np.x, np.z)
		g.global_position = np
		p["lean"] = lerpf(float(p["lean"]), 0.45, clampf(delta * 8.0, 0.0, 1.0))
		g.rotation.x = -float(p["lean"])
		p["left"] -= step
		if p["left"] <= 0.0 or moved.length() < step * 0.3:
			ps.erase(p)
			for m in g.get_meta("mats", []):
				(m as ShaderMaterial).set_shader_parameter("phase_amt", 1.0)
			SpiritFx.burst(world.fx_root, np + Vector3(0, 1.0, 0), VIOLET, 12, 2.5, 0.1, 0.4, true, 0.0)
	if ps.is_empty():
		h.fxs.erase("phantoms")

static func clear(h: Hero) -> void:
	if h.fxs.has("phantoms"):
		for p in h.fxs["phantoms"]:
			if is_instance_valid(p["node"]):
				(p["node"] as Node).queue_free()
		h.fxs.erase("phantoms")

## Where a phantom tears through a foe: a pale crescent and a spray.
static func phantom_hit(root: Node3D, pos: Vector3, dir: Vector3) -> void:
	SpiritFx.burst(root, pos, PALE, 14, 4.0, 0.08, 0.35, true, 0.0, 70.0, dir)
	Fx.flash(root, pos, VIOLET, 1.4, 0.15, 3.5)

## The split: a violet flash and a ring where the phantoms leave him.
static func split(root: Node3D, pos: Vector3) -> void:
	Fx.flash(root, pos + Vector3(0, 1.2, 0), VIOLET, 3.0, 0.35, 6.0)
	SpiritFx.burst(root, pos + Vector3(0, 1.0, 0), VIOLET, 26, 3.5, 0.1, 0.5, true, 0.0)
	SpiritFx.ring(root, pos, 2.0, VIOLET, 0.3, 0.2)
