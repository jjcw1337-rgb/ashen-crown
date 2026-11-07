class_name BoneBoltFx
extends Node3D
## What Bone Bolt looks like, on every game: the "loose" event {p, d} makes a flying shard of bone (its Meshy model,
## a green soul trail) flown by its own copy of the rules' Missile (BoneBolt.flight), so it goes where the real one
## goes; where it passes a foe, a crack of bone splinters; where it ends, a puff of bone dust. It hurts nothing.

const SHARD := "res://game/heroes/necromancer/skills/bone_bolt/bone_shard.glb"
const SOUL := Color(0.45, 1.0, 0.6)
const BONE := Color(0.92, 0.88, 0.76)

var game: Node
var m: Missile
var pierce := 1

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev.get("e", "")):
		"loose":
			var n := BoneBoltFx.new()
			n.game = h.game
			n.m = BoneBolt.flight(ev["p"], ev["d"])
			n.pierce = int(Skill.num("bone_bolt", "pierce", 1.0))
			h.game.world.fx_root.add_child(n)
			n.global_position = ev["p"]
			n._dress(ev["d"])
			SkillFx.snd(h, "bone_bolt" if Sfx.bank.has("bone_bolt") else "spirit_dart", -4.0, randf_range(0.9, 1.05))
			return true
	return false

func _dress(dir: Vector3) -> void:
	var body: Node3D = ResCache.inst(SHARD) as Node3D if ResourceLoader.exists(SHARD) else null
	if body == null:
		var mi := MeshInstance3D.new()
		mi.mesh = Geo.cone(0.05, 0.5, 6)
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.material_override = Mats.mat(BONE, 0.7)
		body = mi
	add_child(body)
	if body.get_child_count() > 0 or not (body is MeshInstance3D):
		body.rotation_degrees = Vector3(-90, 0, 0)      # (the model stands up its length: laid along the flight)
		body.position = Vector3(0, 0, 0.27)
	look_at(global_position + dir, Vector3.UP)
	Fx.aura(self, SOUL, 14, 0.35, 0.05, 0.3, 0.0, 0.05)

func _process(delta: float) -> void:
	if m == null or game == null or game.world == null:
		queue_free()
		return
	var was := m.pos
	var hits := 0
	m.step(game, delta, func(e): return is_instance_valid(e) and not e.dead, func(e):
		hits += 1
		Fx.burst(game.world.fx_root, e.global_position + Vector3(0, 1.0, 0), BONE, 10, 3.0, 0.04, 0.35, false, -6.0, 120.0)
		Fx.sparks(game.world.fx_root, e.global_position + Vector3(0, 1.0, 0), SOUL)
		if int(m.data["hits"]) + hits > pierce:
			m.done = true)
	m.data["hits"] = int(m.data["hits"]) + hits
	global_position = m.pos
	rotate_object_local(Vector3.FORWARD, delta * 14.0)
	if m.done:
		Fx.burst(game.world.fx_root, m.pos, Color(BONE.r, BONE.g, BONE.b, 0.6), 12, 1.6, 0.05, 0.4, false, -2.0, 180.0)
		queue_free()
	elif was == m.pos:
		queue_free()
