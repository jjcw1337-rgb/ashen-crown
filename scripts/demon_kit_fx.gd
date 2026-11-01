class_name DemonKitFx
extends RefCounted
## Pieces the Demon's overhauled skills share (on top of InfernalFx, his visual language): ground strips that
## follow the terrain (the charge's path, the fault, skid grooves), the landing marks (Shatterstone's shadow, a
## meteor's circle at a player), the Meshy props (the boulder, the obsidian plates, the chain's claw) with stand-ins
## when a file is missing, and finding a player's body from the id in an event.

const BOULDER := "res://assets/models/fx/demon/boulder.glb"
const PLATE := "res://assets/models/fx/demon/fault_plate.glb"
const CLAW := "res://assets/models/fx/demon/hellclaw.glb"

static var _scenes := {}
static var _target_shader: Shader

## A player's body on this game: his own hero if it is him, else his puppet.
static func by_pid(h: Hero, pid: int) -> Node3D:
	if pid <= 0 or h.game.net == null:
		return null
	if h.game.multiplayer.has_multiplayer_peer() and pid == h.game.multiplayer.get_unique_id():
		return h.game.hero
	var p = h.game.net.players.get(pid)
	if p is Dictionary and is_instance_valid(p.get("hero")):
		return p["hero"]
	return null

## The bodies an event names: its monsters ("t") and its player ("pid").
static func targets(h: Hero, ev: Dictionary) -> Array:
	var out: Array = []
	for e in ev.get("t", []):
		if e != null and is_instance_valid(e):
			out.append(e)
	var b := by_pid(h, int(ev.get("pid", 0)))
	if b != null:
		out.append(b)
	return out

static func height_of(n: Node) -> float:
	var v = n.get("height")
	return float(v) if v != null and float(v) > 0.2 else 1.9

static func chest(n: Node3D, k := 0.6) -> Vector3:
	return n.global_position + Vector3(0, height_of(n) * k, 0)

## His head, roughly (the horns' fire rides it): above his shoulders and a little forward of his facing.
static func head(h: Hero) -> Vector3:
	return h.global_position + Vector3(0, 2.15 * Demon.SCALE, 0) + h.facing() * 0.32

static func model(path: String) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var ps = _scenes[path]
	if ps == null:
		return null
	var n: Node3D = (ps as PackedScene).instantiate()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

## Gives every mesh of a model a heat glow over its own texture (the props' lava seams flare, then cool).
static func heat_model(n: Node3D, heat: float) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D)
		for i in m.get_surface_override_material_count():
			var base = m.get_active_material(i)
			if base is StandardMaterial3D:
				var c := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.emission_enabled = true
				c.emission = InfernalFx.MOLTEN
				c.emission_energy_multiplier = heat
				if c.emission_texture == null and c.albedo_texture != null:
					c.emission_texture = c.albedo_texture
					c.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				m.set_surface_override_material(i, c)

static func set_heat(n: Node3D, heat: float) -> void:
	if n == null or not is_instance_valid(n):
		return
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D)
		for i in m.get_surface_override_material_count():
			var c = m.get_surface_override_material(i)
			if c is StandardMaterial3D:
				(c as StandardMaterial3D).emission_energy_multiplier = heat

## A ground strip from a to b following the terrain, width w: UV.x across (0..1), UV.y along (0 at a .. 1 at b),
## vertices relative to a. The rift shader reads it as a crack running from a to b.
static func strip_mesh(world, a: Vector3, b: Vector3, w: float, segs := 24, lift := 0.05) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d := (b - a) * Vector3(1, 0, 1)
	var side := d.normalized().cross(Vector3.UP) * w * 0.5 if d.length() > 0.01 else Vector3.RIGHT * w * 0.5
	var rows: Array = []
	for i in segs + 1:
		var u := float(i) / segs
		var row: Array = []
		for j in 3:
			var v := float(j) / 2.0
			var p := a + d * u + side * (v * 2.0 - 1.0)
			p.y = world.height_at(p.x, p.z) + lift
			row.append([p - a, Vector2(v, u)])
		rows.append(row)
	for i in segs:
		for j in 2:
			var q := [rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i][j], rows[i + 1][j + 1], rows[i + 1][j]]
			for k in q:
				st.set_uv(k[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(k[0])
	return st.commit()

## A rift crack laid along a strip (InfernalFx's rift shader): opened with `front`, cooled with `heat`, gone with `life`.
static func crack(root: Node3D, world, a: Vector3, b: Vector3, w: float) -> Array:
	var rm := InfernalFx.rift_mat()
	rm.set_shader_parameter("span", maxf(1.0, a.distance_to(b) / 3.4))
	var mi := MeshInstance3D.new()
	mi.mesh = strip_mesh(world, a, b, w, maxi(8, int(a.distance_to(b) * 3.0)))
	mi.material_override = rm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = a
	return [mi, rm]

## A landing mark on the ground: a ring closing in to the size it will hit, filling as the moment comes (k 0..1).
static func target_mark(root: Node3D, world, at: Vector3, r: float, col: Color) -> Array:
	if _target_shader == null:
		_target_shader = Shader.new()
		_target_shader.code = TARGET_SHADER
	var m := ShaderMaterial.new()
	m.shader = _target_shader
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("hot", InfernalFx.MOLTEN)
	var mi := MeshInstance3D.new()
	mi.mesh = InfernalFx.disc_mesh(world, at, r * 1.25, 36, 4, 0.06)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = at
	return [mi, m]

## A ring of air bending outward (heat haze from High; on Low/Medium a faint glowing ring instead).
static func shock_ring(root: Node3D, game, at: Vector3, r: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.82
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 6
	mi.mesh = tm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hz: ShaderMaterial
	if InfernalFx.haze_ok(game):
		hz = InfernalFx.haze_mat(0.05, false)
		mi.material_override = hz
	else:
		hz = InfernalFx.glow_mat(InfernalFx.BLOODFIRE, 1.2, 1.2)
		mi.material_override = hz
	root.add_child(mi)
	mi.global_position = at + Vector3(0, 0.3, 0)
	mi.scale = Vector3(0.3, 0.6, 0.3)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(r, 1.4, r), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	InfernalFx.tween_param(mi, hz, "life", 1.0, 0.0, dur)
	InfernalFx.tween_param(mi, hz, "alpha", 0.8, 0.0, dur)
	Fx._free_later(mi, dur + 0.05)

## A short-lived light (a flash that falls off through `dur`).
static func flash_light(root: Node3D, at: Vector3, col: Color, energy: float, rng: float, dur: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)
	return l

## Hot debris: n obsidian chips flung from `at` (dir biased), cooling as they fly.
static func debris(root: Node3D, at: Vector3, n: int, dir: Vector3, speed: float, size: float) -> void:
	var fm := InfernalFx.shard_mat(true)
	for j in n:
		var fr := MeshInstance3D.new()
		fr.mesh = InfernalFx.shard_mesh(j)
		fr.material_override = fm
		fr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fr)
		var s := size * randf_range(0.6, 1.3)
		fr.scale = Vector3(s, s * randf_range(0.8, 1.5), s)
		fr.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		fr.global_position = at + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.3), randf_range(-0.2, 0.2))
		var ang := randf() * TAU
		var v := (dir * speed * randf_range(0.5, 1.0)) + Vector3(cos(ang), 0, sin(ang)) * speed * 0.45 + Vector3(0, speed * randf_range(0.5, 1.0), 0)
		InfernalFx.fly(fr, v, Vector3(randf_range(-12, 12), randf_range(-9, 9), randf_range(-12, 12)), randf_range(0.5, 0.9), -15.0)
	var holder := Node.new()
	root.add_child(holder)
	Fx._free_later(holder, 1.2)
	InfernalFx.tween_param(holder, fm, "heat", 1.6, 0.0, 1.1)

## Embers in a burst (one shot).
static func embers(root: Node3D, at: Vector3, n: int, spread: float, vel: Vector2, dir := Vector3.UP, box := Vector3.ZERO) -> void:
	var d := {"amount": n, "life": 1.0, "explosive": 0.85, "dir": dir, "spread": spread, "vel": [vel.x, vel.y],
		"gravity": 1.0, "damping": [0.6, 1.4], "scale": [0.4, 1.0], "size": 0.06, "turb": 1.5,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.25, InfernalFx.MOLTEN], [0.7, InfernalFx.BLOODFIRE], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]}
	if box != Vector3.ZERO:
		d["shape"] = "box"
		d["box"] = box
	InfernalFx.particles(root, at, d)

## A fire that flares up, burns `hold` s and dies (the fissures, the cracks).
static func flare_fire(root: Node3D, at: Vector3, size: float, delay: float, hold: float, tr: int, soot := true) -> Node3D:
	var fr := InfernalFx.fire(root, at, size, 45.0, tr, soot, true)
	InfernalFx.fire_on(fr, false)
	var tw := fr.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): InfernalFx.fire_on(fr, true))
	tw.tween_interval(hold)
	tw.tween_callback(func(): InfernalFx.fire_on(fr, false))
	tw.tween_interval(1.1)
	tw.tween_callback(fr.queue_free)
	return fr

const TARGET_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float k = 0.0;          // 0 thrown .. 1 landing now
uniform float life = 1.0;
uniform vec3 col : source_color = vec3(0.78, 0.035, 0.05);
uniform vec3 hot : source_color = vec3(1.0, 0.42, 0.07);
void fragment() {
	vec2 q = (UV - 0.5) * 2.0 * 1.25;
	float r = length(q);
	if (r > 1.25) { discard; }
	// the closing ring: it starts wide and tightens to the edge of the blow (r = 1) as the moment comes
	float ring_r = mix(1.22, 1.0, k);
	float ring = 1.0 - smoothstep(0.0, 0.045, abs(r - ring_r));
	// the edge it will hit, faint but always there
	float edge = (1.0 - smoothstep(0.0, 0.02, abs(r - 1.0))) * 0.5;
	// the inside darkens and reddens as it fills (a shadow coming down)
	float fill = (1.0 - smoothstep(0.92, 1.0, r)) * k * k * 0.35;
	// ticks round the rim
	float a = atan(q.y, q.x);
	float ticks = step(0.9, fract(a * 12.0 / 6.2831853 + TIME * 0.3)) * (1.0 - smoothstep(0.0, 0.08, abs(r - 1.07)));
	float pulse = 0.8 + 0.2 * sin(TIME * 18.0 * (0.4 + k));
	vec3 c = mix(col, hot, k);
	vec3 o = c * (ring * 1.6 * pulse + edge + ticks * 0.6) + col * fill;
	ALBEDO = o * life;
	ALPHA = 1.0;
}
"""
