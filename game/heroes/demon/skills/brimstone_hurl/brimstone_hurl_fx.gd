class_name BrimstoneHurlFx
extends RefCounted
## Brimstone Hurl's look, "Shatterstone" (the Demon's F; the gameplay is BrimstoneHurl). Earth and stone, not hellfire:
## nothing here is Molten Fists'.
##
##  The tear ("cast"): his hand rips into the ground: the earth there is crushed in (a Meshy-painted mark), clods and
##  torn chunks of ground fly up, a puff of simulated dust.
##  The throw ("throw" {p: the hand, q: where it lands, x: the flight, n: which throw}): the Meshy boulder (cracked
##  basalt, lava in its seams) tumbles on a high arc, its seams glowing, dragging a trail of simulated fire and smoke
##  (the comet sim, one looping card lying along its flight) and leaving soot hanging in the air behind it, a few
##  sparks; a light rides with it. On the ground where it will land a mark closes in and fills as it falls, for
##  everyone (the counterplay).
##  The landing ("splash" {p, ps: where the shards stop, t: the foes struck}): it breaks into its real pieces (the
##  same rock cut into Voronoi chunks in Blender), their broken faces molten and cooling as they bounce away; the
##  simulated impact cloud (a hot flash, then dirt and ash thrown out and up, a skirt of dust racing along the ground);
##  a crater (Meshy-painted, projected on the terrain) with its molten heart; a shock ring; clods; four big chunks
##  skitter out to where the shards' damage lands, each kicking up its own puff and mark.
## State: h.fxs["shatter"] (each boulder in the air with its mark and trail), flown by `update`.

const SIZE := 0.82
const TRAIL_LEN := 3.0       # the boulder's comet trail, metres
const PUFF_EVERY := 0.07     # soot left hanging behind a flying rock
const IMPACT_TINT := Color(0.86, 0.8, 0.72, 0.92)   # the dust a shade darker and warmer: the moor's dusk, not daylight

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
	DemonKitFx.decal(root, p, "crush", Vector2(1.6, 1.6), randf() * TAU, 3.0, 0.2)
	var tw := root.create_tween()
	tw.tween_interval(0.18)
	tw.tween_callback(func():
		DemonKitFx.smoke(root, p, "ash", 1.5, 1.0)
		DemonKitFx.clods(root, p + Vector3(0, 0.15, 0), [8, 12, 16, 20][tr], 3.0)
		DemonKitFx.pieces(root, world, p + Vector3(0, 0.1, 0), DemonFx.ROCK_PIECES, 0.22, 2.4, 0.0, 1.4, 1.2))
	SkillFx.snd(h, "impact_bone", -9.0, 0.5)
	SkillFx.snd(h, "growl", -11.0, 0.75)

static func _throw(h: Hero, ev: Dictionary) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var from: Vector3 = ev["p"]
	var to: Vector3 = ev["q"]
	var flight: float = float(ev.get("x", Skill.num("hurl", "flight", 0.55)))
	var n := rock(root, DemonFx.ROCK, SIZE, 1.4)
	n.global_position = from
	var mk := DemonKitFx.target_mark(root, world, to, Skill.num("hurl", "radius", 2.6), Color(0.6, 0.18, 0.06))
	var bs: Array = h.fxs.get("shatter", [])
	bs.append({"node": n, "from": from, "to": to, "t": 0.0, "dur": flight, "mark": mk[0], "mark_mat": mk[1], "trail": 0.0,
		"spin": Vector3(randf_range(5.0, 8.0), randf_range(-3.0, 3.0), randf_range(-2.0, 2.0)), "last": from,
		"comet": trail(root, from, (to - from).normalized() + Vector3(0, 0.6, 0), TRAIL_LEN)})
	h.fxs["shatter"] = bs
	DemonKitFx.clods(root, from, 8, 2.5, (to - from).normalized())
	SkillFx.snd(h, "cleave_swing", -2.0, 0.6)
	SkillFx.snd(h, "fireball", -8.0, 0.55)

## A burning rock in flight: the model (or a stand-in), its seams glowing, a light riding with it.
static func rock(root: Node3D, path: String, size: float, heat: float) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	var m := DemonKitFx.model(path)
	var spin := Node3D.new()
	n.add_child(spin)
	if m != null:
		DemonKitFx.heat_model(m, heat)
		m.position = Vector3(0, -size * 0.45, 0)
		spin.add_child(m)
		spin.scale = Vector3.ONE * size
	else:
		DemonFx.boulder(spin, size * 0.5)
	n.set_meta("spin", spin)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.16)
	l.light_energy = 1.6
	l.omni_range = 4.5
	l.shadow_enabled = false
	n.add_child(l)
	return n

## The trail a burning rock drags: the comet sim (fire at the rock, smoke torn back by its flight) looping on one card
## that lies along the way it flies; `fly_trail` keeps it on the rock, `end_trail` lets it go.
static func trail(root: Node3D, at: Vector3, dir: Vector3, length: float) -> MeshInstance3D:
	return DemonKitFx.smoke(root, at, "comet", length, 1.2, true, Color.WHITE, dir)

## Every frame of a rock's flight (b: its state): the trail on it, soot left hanging in the air behind, a few sparks.
static func fly_trail(root: Node3D, b: Dictionary, p: Vector3, vel: Vector3, delta: float, length: float) -> void:
	DemonKitFx.aim_smoke(b.get("comet"), p, vel)
	b["trail"] = float(b["trail"]) - delta
	if float(b["trail"]) > 0.0:
		return
	b["trail"] = PUFF_EVERY
	DemonKitFx.smoke(root, p - vel.normalized() * length * 0.15, "ash", length * 0.3, 1.2, false, Color(0.85, 0.8, 0.76, 0.45))
	if randf() < 0.5:
		DemonKitFx.sparks(root, p, -vel, 3, 30.0, Vector2(1.0, 3.0), 0.35)

static func end_trail(b: Dictionary) -> void:
	DemonKitFx.smoke_out(b.get("comet"), 0.12)
	b.erase("comet")

static func _land(h: Hero, ev: Dictionary) -> void:
	var at: Vector3 = ev["p"]
	at.y = h.game.world.height_at(at.x, at.z)
	var bs: Array = h.fxs.get("shatter", [])
	for b in bs.duplicate():
		if (b["to"] as Vector3).distance_to(at) < 0.8:
			_drop(b)
			bs.erase(b)
	impact(h, at, DemonFx.ROCK_PIECES, SIZE, Skill.num("hurl", "radius", 2.6), 1.0)
	# the four big chunks skittering out to the shards' spots
	var world = h.game.world
	var root: Node3D = world.fx_root
	var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
	for i in ps.size():
		_shard(h, root, world, at, ps[i], i)
	Sfx.play_at("boom", at, -1.0, 0.85)
	Sfx.play_at("impact_bone", at, -5.0, 0.55)
	Sfx.play_at("slam", at, -8.0, 0.7)

## A rock hitting the ground (Shatterstone and the wrath's meteors): its real pieces, the simulated impact cloud, the
## crater, the shock, the clods. k scales it all (a meteor is bigger).
static func impact(h: Hero, at: Vector3, pieces_path: String, size: float, r: float, k: float) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	DemonKitFx.pieces(root, world, at + Vector3(0, size * 0.35, 0), pieces_path, size, 6.5 * k, 3.2, 2.8, 0.9, Vector3.ZERO, tr >= 2)
	DemonKitFx.smoke(root, at, "impact", r * 2.0 * k, 1.9, false, IMPACT_TINT)
	DemonKitFx.decal(root, at, "crater", Vector2(r * 1.9, r * 1.9) * k, randf() * TAU, 6.0, 3.0)
	DemonKitFx.flash_light(root, at + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 5.0 * k, 8.0 * k, 0.45)
	DemonKitFx.shock_ring(root, h.game, at, r * 1.4 * k, 0.32)
	DemonKitFx.clods(root, at + Vector3(0, 0.2, 0), [14, 22, 30, 38][tr], 6.0 * k)
	DemonKitFx.sparks(root, at + Vector3(0, 0.3, 0), Vector3.UP, [6, 10, 14, 18][tr], 70.0, Vector2(4.0, 9.0))
	SkillFx.shake(h, 0.3 * k)

## A big chunk thrown low along the ground, bouncing to where a shard's damage lands, a puff and a scuff there.
static func _shard(h: Hero, root: Node3D, world, from: Vector3, to: Vector3, i: int) -> void:
	var dir := (to - from) * Vector3(1, 0, 1)
	var dur := 0.34 + 0.05 * i
	var tw := root.create_tween()
	tw.tween_interval(0.02)
	tw.tween_callback(func():
		DemonKitFx.pieces(root, world, from + dir.normalized() * 0.5 + Vector3(0, 0.3, 0), DemonFx.ROCK_PIECES, 0.3, dir.length() / dur * 0.6, 2.0, 1.6, 0.35, dir.normalized()))
	tw.tween_interval(dur)
	tw.tween_callback(func():
		DemonKitFx.smoke(root, to, "ash", 1.1, 0.8)
		DemonKitFx.decal(root, to, "crush", Vector2(0.9, 0.9), randf() * TAU, 2.5, 0.25)
		DemonKitFx.clods(root, to + Vector3(0, 0.1, 0), 5, 2.0))

static func _drop(b: Dictionary) -> void:
	end_trail(b)
	for key in ["node", "mark"]:
		var n = b.get(key)
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()

## Every frame: the boulders fly their arcs (a lob: high, tumbling, trailing smoke), the marks close in under them.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("shatter"):
		return
	var root: Node3D = h.game.world.fx_root
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
		var vel: Vector3 = (p - (b["last"] as Vector3)) / maxf(delta, 0.001)
		b["last"] = p
		(n as Node3D).global_position = p
		var sp = (n as Node).get_meta("spin") if (n as Node).has_meta("spin") else null
		if sp != null and is_instance_valid(sp):
			(sp as Node3D).rotation += (b["spin"] as Vector3) * delta
		fly_trail(root, b, p, vel, delta, TRAIL_LEN)
		(b["mark_mat"] as ShaderMaterial).set_shader_parameter("k", u)
		if u >= 1.0 and float(b["t"]) > float(b["dur"]) + 0.4:
			_drop(b)          # a landing that never came (a partner's lost event)
			bs.erase(b)
	if bs.is_empty():
		h.fxs.erase("shatter")

static func clear(h: Hero) -> void:
	for b in h.fxs.get("shatter", []):
		_drop(b)
	h.fxs.erase("shatter")
