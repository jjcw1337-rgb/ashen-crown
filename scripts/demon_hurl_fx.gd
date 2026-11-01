class_name DemonHurlFx
extends RefCounted
## Brimstone Hurl's look, "Shatterstone" (the Demon's F; the gameplay is DemonSkills).
##
##  The tear ("cast"): his hand rips into the ground: it splits under him, glowing, earth and embers thrown up.
##  The throw ("throw" {p: the hand, q: where it lands, x: the flight, n: which throw}): a real boulder (the Meshy
##  rock, cracked black basalt with lava in its seams) leaves his hand trailing fire and smoke, tumbling on a high
##  arc; on the ground where it will land a mark closes in and fills as it falls, for everyone (the counterplay).
##  The landing ("splash" {p, ps: where the shards stop, t: the foes set alight}): the boulder bursts into burning
##  pieces, a molten splash, a white flash, a crater of cracked lava, a shock ring and a smoke column; four big
##  shards skitter out along the ground trailing fire and stop burning where the edge damage lands.
## State: h.fxs["shatter"] (each boulder in the air with its mark), flown by `update`.

const SIZE := 0.82

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"cast":
			_tear(h)
		"throw":
			_throw(h, ev)
		"splash":
			_land(h, ev)
		_:
			return false
	return true

static func _tear(h: Hero) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var p := h.global_position + h.facing() * 0.7 + h.facing().cross(Vector3.UP) * 0.35
	p.y = world.height_at(p.x, p.z)
	var dc := DemonFx.lava_decal(root, p, 0.9, 2.4, 0.35, h.rig.global_rotation.y)
	dc.scale = Vector3(0.75, 1, 0.95)
	var tw := root.create_tween()
	tw.tween_interval(0.18)
	tw.tween_callback(func():
		Fx.burst(root, p + Vector3(0, 0.15, 0), Color(0.24, 0.19, 0.15, 0.8), [8, 12, 16, 20][tr], 3.0, 0.32, 0.7, false, -6.0, 50.0, Vector3.UP)
		DemonKitFx.debris(root, p + Vector3(0, 0.1, 0), [2, 4, 5, 6][tr], Vector3.UP, 2.8, 0.1)
		DemonKitFx.embers(root, p + Vector3(0, 0.2, 0), [8, 12, 18, 22][tr], 30.0, Vector2(1.5, 3.5)))
	SkillFx.snd(h, "impact_bone", -9.0, 0.5)
	SkillFx.snd(h, "growl", -11.0, 0.75)

static func _throw(h: Hero, ev: Dictionary) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var from: Vector3 = ev["p"]
	var to: Vector3 = ev["q"]
	var flight: float = float(ev.get("x", DemonSkills.HURL_FLIGHT))
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = from
	var rock := DemonKitFx.model(DemonKitFx.BOULDER)
	if rock != null:
		DemonKitFx.heat_model(rock, 1.6)
		rock.position = Vector3(0, -SIZE * 0.45, 0)
		var holder := Node3D.new()
		holder.add_child(rock)
		holder.scale = Vector3.ONE * SIZE
		n.add_child(holder)
		n.set_meta("spin", holder)
	else:
		var b := DemonFx.boulder(n, 0.42)
		n.set_meta("spin", b)
	var fire := InfernalFx.ready_fire(InfernalFx.fire(n, from, 0.9, 70.0, tr, true, true))
	var l := OmniLight3D.new()
	l.light_color = InfernalFx.MOLTEN
	l.light_energy = 1.8
	l.omni_range = 4.5
	l.shadow_enabled = false
	n.add_child(l)
	var trail: GPUParticles3D = null
	if tr >= 1:
		var q := QuadMesh.new()
		q.size = Vector2(0.7, 0.7)
		q.material = InfernalFx.smoke_mat(0.9, 0.6)
		trail = InfernalFx.particles(n, from, {"amount": [0, 10, 16, 22][tr], "life": 0.9, "one_shot": false, "shape": "sphere",
			"r": 0.25, "dir": Vector3.UP, "spread": 40.0, "vel": [0.2, 0.6], "gravity": 0.3, "scale": [0.6, 1.1],
			"grow": [0.5, 1.6], "angle": true, "spin": 30.0, "mesh": q,
			"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.2, Color(1, 1, 1, 0.8)], [1.0, Color(1, 1, 1, 0.0)]]})
	var mk := DemonKitFx.target_mark(root, world, to, DemonSkills.HURL_R, InfernalFx.CRIMSON)
	var bs: Array = h.fxs.get("shatter", [])
	bs.append({"node": n, "from": from, "to": to, "t": 0.0, "dur": flight, "fire": fire, "trail": trail, "mark": mk[0], "mark_mat": mk[1],
		"spin": Vector3(randf_range(5.0, 8.0), randf_range(-3.0, 3.0), randf_range(-2.0, 2.0))})
	h.fxs["shatter"] = bs
	DemonKitFx.embers(root, from, [8, 12, 16, 20][tr], 60.0, Vector2(1.5, 4.0), (to - from).normalized())
	SkillFx.snd(h, "cleave_swing", -2.0, 0.6)
	SkillFx.snd(h, "fireball", -7.0, 0.65)

static func _land(h: Hero, ev: Dictionary) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var at: Vector3 = ev["p"]
	at.y = world.height_at(at.x, at.z)
	# the boulder still in the air on this game lands now (a partner's may lag a frame)
	var bs: Array = h.fxs.get("shatter", [])
	for b in bs.duplicate():
		if (b["to"] as Vector3).distance_to(at) < 0.8:
			_drop(b)
			bs.erase(b)
	# the flash, the splash of molten rock, the boulder's pieces
	var gm := InfernalFx.glow_mat(InfernalFx.WHITEHOT, 2.2, 2.4, 0.6)
	var g := InfernalFx.glow(root, at + Vector3(0, 0.7, 0), 0.9, gm)
	g.create_tween().tween_property(g, "scale", Vector3.ONE * 3.4, 0.2).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, gm, "alpha", 1.0, 0.0, 0.25)
	Fx._free_later(g, 0.3)
	DemonKitFx.flash_light(root, at + Vector3(0, 1.0, 0), InfernalFx.MOLTEN, 5.0, 8.0, 0.5)
	InfernalFx.particles(root, at + Vector3(0, 0.3, 0), {"amount": [18, 28, 40, 50][tr], "life": 0.65, "explosive": 1.0,
		"dir": Vector3.UP, "spread": 70.0, "vel": [3.0, 8.0], "gravity": -11.0, "damping": [0.5, 1.0], "scale": [0.5, 1.2], "size": 0.09,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.3, InfernalFx.MOLTEN], [0.8, InfernalFx.BLOODFIRE], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	DemonKitFx.debris(root, at + Vector3(0, 0.4, 0), [4, 6, 8, 10][tr], Vector3.UP, 4.5, 0.2)
	# the crater
	var cr := DemonFx.lava_decal(root, at, DemonSkills.HURL_CORE * 1.15, 3.2, 0.75)
	cr.scale = Vector3(DemonSkills.HURL_CORE * 1.15, 1, DemonSkills.HURL_CORE * 1.15)
	var rift := MeshInstance3D.new()
	var rm := InfernalFx.rift_mat()
	rift.mesh = InfernalFx.disc_mesh(world, at, DemonSkills.HURL_R, 32, 5, 0.045)
	rift.material_override = rm
	rift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rift)
	rift.global_position = at
	InfernalFx.tween_param(rift, rm, "front", 0.0, 1.05, 0.12)
	InfernalFx.tween_param(rift, rm, "heat", 1.2, 0.0, 1.0, 0.1)
	InfernalFx.tween_param(rift, rm, "life", 1.0, 0.0, 1.0, 1.0)
	Fx._free_later(rift, 2.2)
	DemonKitFx.shock_ring(root, h.game, at, DemonSkills.HURL_R * 1.3, 0.3)
	InfernalFx.smoke(root, at + Vector3(0, 0.6, 0), [4, 7, 10, 12][tr], Vector3(0.6, 0.2, 0.6), Vector3.UP, 1.8, 2.2, 1.2, 0.8)
	DemonKitFx.flare_fire(root, at, 1.4, 0.0, 0.5, tr)
	# the shards skittering out
	var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
	for i in ps.size():
		_shard(h, root, at, ps[i], tr, i)
	for e in ev.get("t", []):
		DemonFx.ignite(root, e)
	Sfx.play_at("boom", at, -1.0, 0.85)
	Sfx.play_at("ice_shatter", at, -8.0, 0.5)
	Sfx.play_at("fire_erupt", at, -6.0, 0.85)
	SkillFx.shake(h, 0.3)

## A big burning shard tumbling out along the ground, bouncing, a fire left where it stops.
static func _shard(h: Hero, root: Node3D, from: Vector3, to: Vector3, tr: int, i: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = InfernalFx.shard_mesh(i + 2)
	var m := InfernalFx.shard_mat()
	m.set_shader_parameter("heat", 1.4)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.scale = Vector3(0.28, 0.42, 0.28)
	mi.global_position = from + Vector3(0, 0.4, 0)
	var dur := 0.32 + 0.05 * i
	var mid := (from + to) * 0.5 + Vector3(0, 0.7, 0)
	var tw := mi.create_tween()
	tw.tween_method(func(u: float):
		if is_instance_valid(mi):
			var a := from.lerp(mid, u)
			var b := mid.lerp(to, u)
			mi.global_position = a.lerp(b, u) + Vector3(0, 0.15, 0)
			mi.rotation = Vector3(u * 14.0, u * 6.0 + i, 0.0), 0.0, 1.0, dur)
	tw.tween_callback(func():
		if is_instance_valid(mi):
			DemonKitFx.flare_fire(root, to, 0.6, 0.0, 0.7, tr, false)
			Fx.burst(root, to + Vector3(0, 0.1, 0), Color(0.22, 0.17, 0.14, 0.7), 5, 1.6, 0.25, 0.5, false, -4.0, 60.0, Vector3.UP)
			var dc := DemonFx.lava_decal(root, to, 0.5, 1.6, 0.4)
			dc.scale = Vector3(0.45, 1, 0.45))
	InfernalFx.tween_param(mi, m, "heat", 1.4, 0.3, 1.6, dur)
	tw.tween_interval(1.4)
	tw.tween_property(mi, "global_position", to - Vector3(0, 0.5, 0), 0.4)
	tw.tween_callback(mi.queue_free)
	var trail := InfernalFx.particles(mi, mi.global_position, {"amount": [4, 6, 9, 12][tr], "life": 0.4, "one_shot": false,
		"dir": Vector3.UP, "spread": 50.0, "vel": [0.3, 1.0], "gravity": 0.8, "scale": [0.5, 1.0], "size": 0.06,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.4, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	var tw2 := trail.create_tween()
	tw2.tween_interval(dur + 0.1)
	tw2.tween_callback(func(): trail.emitting = false)

static func _drop(b: Dictionary) -> void:
	for key in ["node", "mark"]:
		var n = b.get(key)
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()

## Every frame: the boulders fly their arcs (a lob: high, tumbling), the marks close in under them.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("shatter"):
		return
	var bs: Array = h.fxs["shatter"]
	for b in bs.duplicate():
		var n = b["node"]
		if n == null or not is_instance_valid(n):
			_drop(b)
			bs.erase(b)
			continue
		b["t"] = float(b["t"]) + delta
		var u := clampf(float(b["t"]) / maxf(float(b["dur"]), 0.01), 0.0, 1.0)
		var from: Vector3 = b["from"]
		var to: Vector3 = b["to"]
		var p := from.lerp(to, u)
		p.y += sin(u * PI) * (2.6 + from.distance_to(to) * 0.2)
		(n as Node3D).global_position = p
		var sp = (n as Node).get_meta("spin") if (n as Node).has_meta("spin") else null
		if sp != null and is_instance_valid(sp):
			(sp as Node3D).rotation += (b["spin"] as Vector3) * delta
		var mm: ShaderMaterial = b["mark_mat"]
		mm.set_shader_parameter("k", u)
		if u >= 1.0 and float(b["t"]) > float(b["dur"]) + 0.4:
			_drop(b)          # a landing that never came (a partner's lost event)
			bs.erase(b)
	if bs.is_empty():
		h.fxs.erase("shatter")

static func clear(h: Hero) -> void:
	for b in h.fxs.get("shatter", []):
		_drop(b)
	h.fxs.erase("shatter")
