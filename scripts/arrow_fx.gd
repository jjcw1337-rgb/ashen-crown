class_name ArrowFx
extends RefCounted
## The Archer's arrow effects, data-driven per arrow kind (PRESETS), so every bow skill gets the same layered
## treatment with its own identity (docs/archer_vfx_standard.md): a new skill is mostly a new preset.
## Everything here only DRAWS: it is called from ArcherFx (the "loose" event, the draw charge) and from
## Archer.update (the flight, each foe pierced, the end of the flight) on the caster's game and on his
## puppet's alike, so partners see the same arrow from the one "loose" event. Nothing here touches gameplay.
##
## A kind's preset:
##   "model"    the Meshy arrow (assets/models/arrows/<model>.glb, Archer._arrow_mesh)
##   "core"     {col, size, tip}: the hot glow on the head and the spark at the tip
##   "flames"   [{len, r, energy, speed, scale, core, mid, edge, tip, seed}, ...]: flame sheaths round the shaft
##              (FLAME_SHADER: scrolling noise, a gradient core -> mid -> edge -> tip, soft edges)
##   "wings"    {tex, cards, span, tilt, flap, tint, energy}: feather cards each side that unfurl behind the head
##   "trail"    {len, width, energy, head, mid, tail, smoke}: the ribbon behind it (TRAIL_SHADER, rebuilt from the
##              last positions every frame, flame at the head fading into smoke at the tail)
##   "embers"   {tex, amount, life, size, speed, gravity, colors}: textured embers peeling off the wings
##   "sparks"   {amount, life, size, speed, gravity, col}: hot sparks
##   "smoke"    {tex, amount, life, size, col}: alpha-blended smoke wisps (none on Low / web)
##   "light"    {col, energy, range}: the moving light (at most LIGHT_CAP arrows lit at once)
##   "shimmer"  the heat haze behind the head (Forward+ only)
##   "release"  {col, embers, light}: the bow flaring as the arrow leaves
##   "pierce"   {col, embers, sparks, light, scorch}: the entry flash and the cone out of a foe's back
##   "end"      {col, embers, sparks, light, ring, chunks, flames, smoke, scorch}: the burst where the flight ends
##   "burn"     {tex, amount, col}: the body flames on a foe set alight (one system per foe)
##   "draw"     {col, energy}: the fire gathering on the nocked arrow during the draw
##   "sounds"   {cast, release, flight, pierce, end}: [name, dB, pitch] layers, through SkillFx.snd / Sfx.play_at

const TEX := {"feathers": "res://assets/textures/fx/phoenix_feathers.png", "flames": "res://assets/textures/fx/phoenix_flames.png",
	"smoke": "res://assets/textures/fx/phoenix_smoke.png", "scorch": "res://assets/textures/fx/phoenix_scorch.png",
	"burst": "res://assets/textures/fx/holy_slam_burst.png"}
const FRAMES := {"feathers": 8, "flames": 8, "smoke": 4}
const LIGHT_CAP := 3
const TRAIL_STEP := 0.22

const GOLD := Color(1.0, 0.86, 0.55)
const ORANGE := Color(1.0, 0.46, 0.08)
const CRIMSON := Color(0.85, 0.1, 0.04)
const VIOLET := Color(0.55, 0.2, 0.95)

const PRESETS := {
	## Fire Arrow: the Phoenix (concepts/archer_fire/concept_b_phoenix.png). A white-gold core wrapped in flame
	## shaped into folded wings of fiery feathers that unfurl behind the head, a sweeping trail of glowing
	## feather embers and dark smoke, a warm light moving over the ground, a flash where it enters a foe and a cone
	## of fire out of his back, a phoenix burst where the flight ends.
	"fire": {
		"model": "fire",
		"core": {"col": Color(1.0, 0.85, 0.6), "size": 0.26, "tip": Color(0.8, 0.9, 1.0), "tip_size": 0.07},
		"flames": [
			{"len": 1.05, "r": 0.1, "energy": 2.2, "speed": 7.0, "scale": 3.0, "core": Color(1.0, 0.96, 0.82), "mid": Color(1.0, 0.55, 0.1), "edge": Color(0.9, 0.15, 0.03), "tip": Color(0.55, 0.2, 0.9), "seed": 0.0},
			{"len": 1.35, "r": 0.17, "energy": 1.1, "speed": 4.5, "scale": 2.2, "core": Color(1.0, 0.7, 0.3), "mid": Color(1.0, 0.35, 0.05), "edge": Color(0.7, 0.08, 0.05), "tip": Color(0.5, 0.15, 0.95), "seed": 4.7}],
		"wings": {"tex": "feathers", "cards": 3, "span": 1.25, "tilt": 30.0, "flap": 7.0, "tint": Color(1.0, 0.9, 0.8), "energy": 1.6},
		"trail": {"len": 4.6, "width": 0.5, "energy": 1.9, "head": Color(1.0, 0.9, 0.6), "mid": Color(1.0, 0.42, 0.06), "tail": Color(0.5, 0.12, 0.6), "smoke": Color(0.1, 0.06, 0.12)},
		"embers": {"tex": "feathers", "amount": 36, "life": 1.1, "size": Vector2(0.09, 0.34), "speed": 1.6, "gravity": -0.9,
			"colors": [Color(1.0, 0.95, 0.75), Color(1.0, 0.55, 0.12), Color(0.85, 0.12, 0.06), Color(0.5, 0.15, 0.9)]},
		"sparks": {"amount": 24, "life": 0.5, "size": 0.035, "speed": 3.5, "gravity": -7.0, "col": Color(1.0, 0.72, 0.35)},
		"smoke": {"tex": "smoke", "amount": 14, "life": 1.6, "size": 0.45, "col": Color(0.16, 0.1, 0.18, 0.4)},
		"light": {"col": Color(1.0, 0.6, 0.25), "energy": 2.6, "range": 7.5},
		"shimmer": true,
		"release": {"col": Color(1.0, 0.7, 0.3), "embers": 18, "light": 3.0},
		"pierce": {"col": Color(1.0, 0.75, 0.35), "embers": 22, "sparks": 30, "light": 4.5, "scorch": true},
		"end": {"col": Color(1.0, 0.72, 0.3), "embers": 44, "sparks": 40, "light": 7.0, "ring": 3.2, "chunks": true, "flames": true, "smoke": 10, "scorch": true},
		"burn": {"tex": "flames", "amount": 9, "col": Color(1.0, 0.55, 0.15)},
		"draw": {"col": Color(1.0, 0.7, 0.3), "energy": 1.8},
		"sounds": {"cast": [["fuse", -13.0, 1.15]], "release": [["fireball", -4.0, 1.08], ["burn_item", -14.0, 1.25]],
			"pierce": [["impact_flesh", -4.0, 1.0], ["fire_erupt", -9.0, 1.45]], "end": [["boom", -7.0, 1.15], ["fire_erupt", -4.0, 0.9]]},
	},
	## the plain war arrow: a faint streak, sparks on the hit (what the basic attack had)
	"war": {"model": "war", "core": {"col": Color(0.9, 0.85, 0.7), "size": 0.0, "tip": Color(0, 0, 0), "tip_size": 0.0},
		"sounds": {"pierce": [["impact_flesh", -6.0, 1.0]]}},
}

static var _shaders := {}
static var _tex := {}
static var _tube_cache := {}
static var _lights := 0

static func preset(kind: String) -> Dictionary:
	return PRESETS.get(kind, PRESETS["war"])

## Fewer particles, no smoke or haze: the browser build or the Low preset.
static func cheap(game) -> bool:
	return OS.has_feature("web") or (game != null and int(game.get("quality")) <= 0)

static func shimmer_ok() -> bool:
	return RenderingServer.get_rendering_device() != null and not OS.has_feature("web")

static func tex(key: String) -> Texture2D:
	if not _tex.has(key):
		_tex[key] = load(TEX[key]) if ResourceLoader.exists(TEX[key]) else null
	return _tex[key]

static func shader(key: String) -> Shader:
	if _shaders.has(key):
		return _shaders[key]
	var s := Shader.new()
	match key:
		"flame": s.code = FLAME_SHADER % Mats.NOISE_LIB
		"card": s.code = CARD_SHADER
		"trail": s.code = TRAIL_SHADER % Mats.NOISE_LIB
		"shimmer": s.code = SHIMMER_SHADER % Mats.NOISE_LIB
		"scorch": s.code = SCORCH_SHADER
		"sprite": s.code = SPRITE_SHADER
	_shaders[key] = s
	return s

# ---------------------------------------------------------------- the projectile
## The layered arrow of this kind, ready to be placed and flown (`fly` every frame). Its state is in metas.
static func projectile(kind: String, game) -> Node3D:
	var p := preset(kind)
	var root: Node3D = Archer._arrow_mesh(str(p.get("model", "war")), p.has("flames"))
	root.set_meta("kind", kind)
	root.set_meta("age", 0.0)
	var lite := cheap(game)
	var core: Dictionary = p.get("core", {})
	if float(core.get("size", 0.0)) > 0.0:
		var cq := _glow_quad(core["col"], float(core["size"]), 2.6)
		cq.position = Vector3(0, 0, -0.1)
		root.add_child(cq)
		var tq := _glow_quad(core["tip"], float(core["tip_size"]), 4.0)
		tq.position = Vector3(0, 0, -0.42)
		tq.name = "Tip"
		root.add_child(tq)
	var mats: Array = []
	for f in p.get("flames", []):
		var fl := MeshInstance3D.new()
		fl.mesh = _tube(float(f["len"]), float(f["r"]))
		var m := ShaderMaterial.new()
		m.shader = shader("flame")
		for k in ["energy", "speed", "scale", "seed"]:
			m.set_shader_parameter(k, float(f[k]))
		for k in ["core", "mid", "edge", "tip"]:
			m.set_shader_parameter("c_" + k, f[k])
		fl.material_override = m
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fl)
		mats.append(m)
	if p.has("wings"):
		_wings(root, p["wings"], mats)
	root.set_meta("mats", mats)
	if p.has("embers"):
		var e: Dictionary = p["embers"]
		var n := int(e["amount"]) / (2 if lite else 1)
		var pe := _textured_particles(str(e["tex"]), n, float(e["life"]), e["size"], true)
		var pm := pe.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.35, 0.12, 0.3)
		pm.direction = Vector3(0, 0.6, 1)
		pm.spread = 55.0
		pm.initial_velocity_min = float(e["speed"]) * 0.3
		pm.initial_velocity_max = float(e["speed"])
		pm.gravity = Vector3(0, float(e["gravity"]), 0)
		pm.angular_velocity_min = -180.0
		pm.angular_velocity_max = 180.0
		pm.damping_min = 1.0
		pm.damping_max = 2.5
		pm.color_ramp = _ramp(e["colors"], true)
		pm.scale_curve = _curve_tex([[0.0, 0.5], [0.15, 1.0], [1.0, 0.25]])
		pe.position = Vector3(0, 0, 0.35)
		pe.name = "Embers"
		root.add_child(pe)
	if p.has("sparks"):
		var s: Dictionary = p["sparks"]
		var ps := Fx.aura(root, s["col"], int(s["amount"]) / (2 if lite else 1), float(s["speed"]), float(s["size"]), float(s["life"]), float(s["gravity"]), 0.12, 70.0, Vector3(0, 0, -0.2))
		(ps.process_material as ParticleProcessMaterial).direction = Vector3(0, 0.3, 1)
		(ps.process_material as ParticleProcessMaterial).scale_min = 0.2
		(ps.process_material as ParticleProcessMaterial).scale_max = 0.6
		ps.name = "Sparks"
	if p.has("smoke") and not lite:
		var sm: Dictionary = p["smoke"]
		var psm := _textured_particles(str(sm["tex"]), int(sm["amount"]), float(sm["life"]), Vector2.ONE * float(sm["size"]), false)
		var spm := psm.process_material as ParticleProcessMaterial
		spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		spm.emission_sphere_radius = 0.15
		spm.direction = Vector3(0, 1, 0.6)
		spm.spread = 35.0
		spm.initial_velocity_min = 0.3
		spm.initial_velocity_max = 0.9
		spm.gravity = Vector3(0, 0.5, 0)
		spm.angular_velocity_min = -40.0
		spm.angular_velocity_max = 40.0
		var sc: Color = sm["col"]
		spm.color_ramp = _ramp([Color(sc.r, sc.g, sc.b, 0.0), sc, Color(sc.r * 0.8, sc.g * 0.8, sc.b * 0.8, sc.a * 0.6), Color(sc.r, sc.g, sc.b, 0.0)], false)
		spm.scale_curve = _curve_tex([[0.0, 0.3], [0.4, 1.0], [1.0, 1.6]])
		psm.position = Vector3(0, 0.1, 0.9)
		psm.name = "Smoke"
		root.add_child(psm)
	if p.has("light") and _lights < LIGHT_CAP:
		var l: Dictionary = p["light"]
		var lt := OmniLight3D.new()
		lt.light_color = l["col"]
		lt.light_energy = float(l["energy"])
		lt.omni_range = float(l["range"])
		lt.omni_attenuation = 1.4
		lt.shadow_enabled = false
		lt.position = Vector3(0, 0.15, 0.2)
		lt.name = "Light"
		root.add_child(lt)
		_lights += 1
		lt.tree_exited.connect(func(): _lights = maxi(0, _lights - 1))
	if p.get("shimmer", false) and shimmer_ok() and not lite:
		var sh := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.6, 1.2)
		sh.mesh = q
		var m := ShaderMaterial.new()
		m.shader = shader("shimmer")
		sh.material_override = m
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sh.position = Vector3(0, 0.1, 0.6)
		sh.name = "Shimmer"
		root.add_child(sh)
	return root

## The feather wings: `cards` feathers a side, fanned from the shaft just behind the head, folded along it as the
## arrow leaves and unfurling over the first stretch of flight (`fly`), beating gently.
static func _wings(root: Node3D, w: Dictionary, mats: Array) -> void:
	var t := tex(str(w["tex"]))
	if t == null:
		return
	var piv := Node3D.new()
	piv.name = "Wings"
	piv.position = Vector3(0, 0.02, 0.12)
	root.add_child(piv)
	var cards: int = int(w["cards"])
	var frames: int = FRAMES.get(str(w["tex"]), 1)
	for side in [-1.0, 1.0]:
		for k in cards:
			var c := MeshInstance3D.new()
			var q := QuadMesh.new()
			var L: float = float(w["span"]) * (1.0 - k * 0.18)
			q.size = Vector2(L * 0.3, L)
			q.center_offset = Vector3(0, L * 0.5 - 0.06, 0)
			c.mesh = q
			var m := ShaderMaterial.new()
			m.shader = shader("card")
			m.set_shader_parameter("tex", t)
			m.set_shader_parameter("frames", float(frames))
			m.set_shader_parameter("frame", float((k * 3 + int(side > 0.0) * 2) % frames))
			m.set_shader_parameter("tint", w["tint"])
			m.set_shader_parameter("energy", float(w["energy"]) * (1.0 - k * 0.15))
			m.set_shader_parameter("seed", float(k) * 2.1 + side)
			c.material_override = m
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.set_meta("side", side)
			c.set_meta("k", k)
			piv.add_child(c)
			mats.append(m)

## Every frame of the flight (Archer.update, both games): the wings unfurl and beat, the trail ribbon is rebuilt
## behind the head, the light flickers, the haze follows.
static func fly(a: Dictionary, n: Node3D, delta: float, game) -> void:
	var age: float = float(n.get_meta("age", 0.0)) + delta
	n.set_meta("age", age)
	var p := preset(str(n.get_meta("kind", "war")))
	var t: float = Time.get_ticks_msec() / 1000.0
	if p.has("wings"):
		var w: Dictionary = p["wings"]
		var piv := n.get_node_or_null("Wings") as Node3D
		if piv != null:
			var open := smoothstep(0.0, 0.22, age)
			var flap := sin(age * 25.0) * deg_to_rad(float(w["flap"])) * open
			var cam := n.get_viewport().get_camera_3d() if n.is_inside_tree() else null
			for c in piv.get_children():
				var side: float = float(c.get_meta("side"))
				var k: int = int(c.get_meta("k"))
				# fanned: the first feather sweeps furthest out and back, the inner ones higher and closer to the shaft
				var sweep := lerpf(deg_to_rad(12.0), deg_to_rad(68.0 - k * 17.0), open) + flap * (1.0 - k * 0.3)
				var tilt := deg_to_rad(float(w["tilt"]) + k * 14.0) * open
				# the tip direction: back along the shaft (+z), out to the side, lifted by the tilt
				var d := Vector3(side * sin(sweep) * cos(tilt), sin(tilt), cos(sweep) * cos(tilt)).normalized()
				# the card turns about its own length to face the camera (an axis billboard), so it never goes edge-on
				var to_cam := Vector3.UP
				if cam != null:
					to_cam = piv.global_transform.basis.inverse() * (cam.global_position - (c as Node3D).global_position).normalized()
				var x := d.cross(to_cam)
				if x.length() < 0.01:
					x = Vector3.RIGHT
				x = x.normalized()
				(c as Node3D).basis = Basis(x, d, x.cross(d))
	if p.has("trail"):
		_trail(a, n, p["trail"], game)
	var lt := n.get_node_or_null("Light") as OmniLight3D
	if lt != null:
		var l: Dictionary = p["light"]
		lt.light_energy = float(l["energy"]) * (0.86 + 0.1 * sin(t * 37.0) + 0.07 * sin(t * 23.0 + 1.3)) * smoothstep(0.0, 0.1, age)
	var sh := n.get_node_or_null("Shimmer") as MeshInstance3D
	if sh != null:
		var cam := n.get_viewport().get_camera_3d() if n.is_inside_tree() else null
		if cam != null:
			sh.look_at(cam.global_position, Vector3.UP)

## The ribbon: the head's last positions (a["pts"], newest first) joined into a camera-facing strip, flame-wide
## just behind the head and tapering to nothing TRAIL len back, the tail lifted a little (hot gas rises).
static func _trail(a: Dictionary, n: Node3D, tr: Dictionary, game) -> void:
	var L: float = float(tr["len"])
	var pts: Array = a.get("pts", [])
	var head: Vector3 = n.global_position
	if pts.is_empty() or (pts[0] as Vector3).distance_to(head) > 0.02:
		pts.push_front(head)
	a["pts"] = pts
	# drop what lies further back than the ribbon reaches
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += (pts[i] as Vector3).distance_to(pts[i - 1])
		if acc > L + 1.0:
			pts.resize(i + 1)
			break
	var mi := a.get("trail") as MeshInstance3D
	if mi == null or not is_instance_valid(mi):
		mi = MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		var m := ShaderMaterial.new()
		m.shader = shader("trail")
		m.set_shader_parameter("energy", float(tr["energy"]))
		for k in ["head", "mid", "tail", "smoke"]:
			m.set_shader_parameter("c_" + k, tr[k])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16384.0
		game.world.fx_root.add_child(mi)
		a["trail"] = mi
	var cam := n.get_viewport().get_camera_3d() if n.is_inside_tree() else null
	var cpos: Vector3 = cam.global_position if cam != null else head + Vector3(0, 10, 10)
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	if pts.size() < 2:
		return
	var W: float = float(tr["width"])
	var age: float = float(n.get_meta("age", 0.0))
	var reach: float = minf(L, age * 20.0 + 0.4)      # it grows out behind the arrow as it leaves the bow
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var s := 0.0
	var tt: float = Time.get_ticks_msec() / 1000.0
	var done := false
	for i in range(pts.size() - 1):
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var seg := p0.distance_to(p1)
		if seg < 0.001:
			continue
		var dir := (p1 - p0) / seg
		var steps := maxi(1, int(ceil(seg / TRAIL_STEP)))
		for k in (steps + 1 if i == pts.size() - 2 else steps):
			var f := float(k) / steps
			var sk := s + seg * f
			var u := clampf(sk / reach, 0.0, 1.0)
			var pos := p0.lerp(p1, f)
			# the tail drifts up and flutters
			pos.y += 0.22 * u * u + sin(tt * 9.0 + sk * 2.3) * 0.03 * u
			var side := dir.cross((cpos - pos).normalized()).normalized()
			var w := W * (0.35 + 0.65 * smoothstep(0.0, 0.25, u)) * (1.0 - u * u) * 0.5
			im.surface_set_uv(Vector2(u, 0.0))
			im.surface_add_vertex(pos - side * w)
			im.surface_set_uv(Vector2(u, 1.0))
			im.surface_add_vertex(pos + side * w)
			if sk >= reach:
				done = true
				break
		if done:
			break
		s += seg
	im.surface_end()

## The flight is over: the trail is left to fade where it lies, the arrow's light and particles die with it.
static func end_flight(a: Dictionary) -> void:
	var mi := a.get("trail") as MeshInstance3D
	if mi != null and is_instance_valid(mi):
		var m := mi.material_override as ShaderMaterial
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.4)
		tw.tween_callback(mi.queue_free)
	a.erase("trail")

# ---------------------------------------------------------------- the release
## The bow flaring as the arrow leaves it: a ring of embers round the bow hand, a brief heat ring, a flash.
static func release(h: Hero, kind: String, from: Vector3, dir: Vector3) -> void:
	var p := preset(kind)
	if not p.has("release"):
		return
	var r: Dictionary = p["release"]
	var root: Node3D = h.game.world.fx_root
	var col: Color = r["col"]
	var lite := cheap(h.game)
	Fx.flash(root, from, col, float(r["light"]), 0.22, 5.0)
	# embers out of the ring round the bow hand, swept back along the shot
	var pe := _textured_particles("feathers", int(r["embers"]) / (2 if lite else 1), 0.6, Vector2(0.035, 0.13), true)
	pe.one_shot = true
	pe.explosiveness = 0.9
	var pm := pe.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = dir
	pm.emission_ring_radius = 0.22
	pm.emission_ring_inner_radius = 0.12
	pm.emission_ring_height = 0.05
	pm.direction = -dir
	pm.spread = 60.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.6
	pm.radial_velocity_min = 1.5
	pm.radial_velocity_max = 3.0
	pm.gravity = Vector3(0, -2.0, 0)
	pm.angular_velocity_min = -240.0
	pm.angular_velocity_max = 240.0
	pm.color_ramp = _ramp([GOLD, ORANGE, CRIMSON, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.0)], true)
	pm.scale_curve = _curve_tex([[0.0, 1.0], [1.0, 0.3]])
	root.add_child(pe)
	pe.global_position = from
	pe.emitting = true
	Fx._free_later(pe, 1.3)
	# the heat ring: a torus of flame standing on the shot's line, growing and gone in a blink
	var ring := MeshInstance3D.new()
	ring.mesh = Geo.torus(0.8, 1.0, 32, 6)
	var m := ShaderMaterial.new()
	m.shader = shader("flame")
	m.set_shader_parameter("energy", 3.0)
	m.set_shader_parameter("speed", 9.0)
	m.set_shader_parameter("scale", 2.0)
	m.set_shader_parameter("c_core", Color(1, 0.95, 0.8))
	m.set_shader_parameter("c_mid", ORANGE)
	m.set_shader_parameter("c_edge", CRIMSON)
	m.set_shader_parameter("c_tip", VIOLET)
	m.set_shader_parameter("solid", 1.0)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	ring.global_position = from
	ring.look_at(from + dir, Vector3.UP)
	ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	ring.scale = Vector3.ONE * 0.1
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(0.55, 0.35, 0.55), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.2).set_ease(Tween.EASE_IN)
	Fx._free_later(ring, 0.24)
	Fx.burst(root, from, Color(1.0, 0.85, 0.5), 10 if lite else 18, 5.0, 0.05, 0.35, true, -6.0, 40.0, -dir)
	_sounds(h, p, "release")
	SkillFx.shake(h, 0.12)

# ---------------------------------------------------------------- the draw
## The fire gathering on the nocked arrow while he draws (ArcherFx.update, every frame of the shot, on the
## puppet too): embers spiralling into the head, a glow growing along the shaft, the light in his hand rising.
## `k` is 0..1 along the draw; the nodes live on the bow's nocked arrow and are cleared at the release.
static func draw_charge(h: Hero, kind: String, k: float) -> void:
	var w: Node3D = h.weapon_node
	if w == null or not is_instance_valid(w) or not w.has_meta("nocked"):
		return
	var arrow: Node3D = w.get_meta("nocked")
	var ch := arrow.get_node_or_null("Charge") as Node3D
	var p := preset(kind)
	if not p.has("draw"):
		return
	var d: Dictionary = p["draw"]
	if ch == null:
		ch = Node3D.new()
		ch.name = "Charge"
		arrow.add_child(ch)
		var fl := MeshInstance3D.new()
		fl.mesh = _tube(0.75, 0.05)
		var m := ShaderMaterial.new()
		m.shader = shader("flame")
		m.set_shader_parameter("energy", float(d["energy"]))
		m.set_shader_parameter("speed", 5.0)
		m.set_shader_parameter("scale", 3.0)
		m.set_shader_parameter("c_core", Color(1, 0.95, 0.8))
		m.set_shader_parameter("c_mid", d["col"])
		m.set_shader_parameter("c_edge", CRIMSON)
		m.set_shader_parameter("c_tip", VIOLET)
		fl.material_override = m
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fl.name = "Sheath"
		ch.add_child(fl)
		# embers drawn into the arrowhead
		var pe := Fx.aura(ch, d["col"], 24 if not cheap(h.game) else 10, 0.0, 0.05, 0.5, 0.0, 0.45, 180.0, Vector3(0, 0, -0.38))
		pe.local_coords = true
		var pm := pe.process_material as ParticleProcessMaterial
		pm.radial_velocity_min = -2.4
		pm.radial_velocity_max = -1.2
		pm.angular_velocity_min = 200.0
		pm.angular_velocity_max = 400.0
		var lt := OmniLight3D.new()
		lt.light_color = d["col"]
		lt.omni_range = 3.0
		lt.shadow_enabled = false
		lt.position = Vector3(0, 0, -0.3)
		lt.name = "Light"
		ch.add_child(lt)
		var tip := _glow_quad(Color(1.0, 0.9, 0.7), 0.16, 3.0)
		tip.position = Vector3(0, 0, -0.4)
		tip.name = "Tip"
		ch.add_child(tip)
	var kk := clampf(k, 0.0, 1.0)
	var sheath := ch.get_node("Sheath") as MeshInstance3D
	(sheath.material_override as ShaderMaterial).set_shader_parameter("alpha_mul", kk)
	sheath.scale = Vector3(0.3 + 0.9 * kk, 0.3 + 0.9 * kk, 1.0)
	(ch.get_node("Light") as OmniLight3D).light_energy = 1.6 * kk * (0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.03))
	(ch.get_node("Tip") as MeshInstance3D).scale = Vector3.ONE * (0.3 + kk)
	ch.visible = arrow.visible

static func end_draw(h: Hero) -> void:
	var w: Node3D = h.weapon_node
	if w == null or not is_instance_valid(w) or not w.has_meta("nocked"):
		return
	var ch := (w.get_meta("nocked") as Node3D).get_node_or_null("Charge")
	if ch != null:
		ch.queue_free()

# ---------------------------------------------------------------- a foe pierced
## The arrow goes through: a bright flash where it enters, a cone of fire and feather embers bursting out of
## the foe's far side along the arrow's line, sparks, a pop of light, a scorch on the ground under him.
static func pierce(h: Hero, kind: String, e: Node3D, dir: Vector3) -> void:
	var p := preset(kind)
	var root: Node3D = h.game.world.fx_root
	var at: Vector3 = e.global_position + Vector3(0, 0.95 * float(e.get("height")), 0)
	if not p.has("pierce"):
		Fx.sparks(root, at, Color(0.9, 0.85, 0.7))
		_sounds(h, p, "pierce", at)
		return
	var pc: Dictionary = p["pierce"]
	var col: Color = pc["col"]
	var lite := cheap(h.game)
	var r: float = float(e.get("radius"))
	var entry := at - dir * (r + 0.1)
	var exit := at + dir * (r + 0.15)
	Fx.flash(root, at, col, float(pc["light"]), 0.3, 6.0)
	# the entry flash: a star of light that is gone in a few frames
	_flash_sprite(root, entry, col, 1.1, 0.16)
	# the cone out of his back: a flame cone blown open, feather embers and sparks thrown along the line
	var cone := MeshInstance3D.new()
	cone.mesh = _tube(1.4, 0.4, true)
	var m := ShaderMaterial.new()
	m.shader = shader("flame")
	m.set_shader_parameter("energy", 3.5)
	m.set_shader_parameter("speed", 10.0)
	m.set_shader_parameter("scale", 2.5)
	m.set_shader_parameter("c_core", Color(1, 0.95, 0.8))
	m.set_shader_parameter("c_mid", ORANGE)
	m.set_shader_parameter("c_edge", CRIMSON)
	m.set_shader_parameter("c_tip", VIOLET)
	cone.material_override = m
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cone)
	cone.global_position = exit
	cone.look_at(exit - dir, Vector3.UP)      # the tube runs toward +z: its mouth away from the foe
	cone.scale = Vector3(0.2, 0.2, 0.3)
	var tw := cone.create_tween().set_parallel(true)
	tw.tween_property(cone, "scale", Vector3(1.0, 1.0, 1.0), 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.3).set_ease(Tween.EASE_IN)
	Fx._free_later(cone, 0.35)
	var pe := _textured_particles("feathers", int(pc["embers"]) / (2 if lite else 1), 0.8, Vector2(0.05, 0.19), true)
	pe.one_shot = true
	pe.explosiveness = 0.95
	var pm := pe.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = dir
	pm.spread = 22.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.damping_min = 3.0
	pm.damping_max = 6.0
	pm.angular_velocity_min = -300.0
	pm.angular_velocity_max = 300.0
	pm.color_ramp = _ramp([Color(1, 0.95, 0.8), ORANGE, CRIMSON, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.0)], true)
	pm.scale_curve = _curve_tex([[0.0, 0.6], [0.2, 1.0], [1.0, 0.3]])
	root.add_child(pe)
	pe.global_position = exit
	pe.emitting = true
	Fx._free_later(pe, 1.4)
	Fx.burst(root, exit, Color(1.0, 0.8, 0.45), int(pc["sparks"]) / (2 if lite else 1), 9.0, 0.05, 0.5, true, -9.0, 25.0, dir)
	# a little blood-dark smoke behind the burst
	if not lite:
		var sm := _textured_particles("smoke", 5, 1.1, Vector2(0.5, 0.5), false)
		sm.one_shot = true
		sm.explosiveness = 0.9
		var spm := sm.process_material as ParticleProcessMaterial
		spm.direction = dir + Vector3(0, 0.5, 0)
		spm.spread = 30.0
		spm.initial_velocity_min = 1.0
		spm.initial_velocity_max = 2.5
		spm.gravity = Vector3(0, 0.6, 0)
		spm.damping_min = 2.0
		spm.damping_max = 3.0
		spm.color_ramp = _ramp([Color(0.2, 0.12, 0.2, 0.0), Color(0.15, 0.09, 0.16, 0.55), Color(0.12, 0.08, 0.14, 0.0)], false)
		spm.scale_curve = _curve_tex([[0.0, 0.4], [1.0, 1.4]])
		root.add_child(sm)
		sm.global_position = exit
		sm.emitting = true
		Fx._free_later(sm, 1.5)
	if pc.get("scorch", false):
		scorch(h.game, e.global_position, dir, 1.6, 0.5)
	_sounds(h, p, "pierce", at)
	SkillFx.hitstop(h, 0.03)

## The body flames on a foe set alight by this kind of arrow (one system per foe, gone when the burn ends).
static func burn(game, e: Node3D, kind: String, dur: float) -> void:
	var p := preset(kind)
	if not p.has("burn") or not is_instance_valid(e):
		return
	var b: Dictionary = p["burn"]
	var old := e.get_node_or_null("phoenix_burn") as Node3D
	if old != null:
		old.set_meta("until", maxf(float(old.get_meta("until", 0.0)), Time.get_ticks_msec() / 1000.0 + dur))
		return
	var hgt: float = float(e.get("height"))
	var rad: float = float(e.get("radius"))
	var root := Node3D.new()
	root.name = "phoenix_burn"
	root.position = Vector3(0, hgt * 0.5, 0)
	e.add_child(root)
	var lite := cheap(game)
	var fl := _textured_particles(str(b["tex"]), int(b["amount"]) / (2 if lite else 1), 0.6, Vector2(0.2, 0.55), true)
	fl.local_coords = false
	var pm := fl.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(rad * 0.7, hgt * 0.45, rad * 0.7)
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 1.8, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	var bc: Color = b["col"]
	pm.color_ramp = _ramp([Color(bc.r, bc.g, bc.b, 0.0), Color(1.0, 0.85, 0.55), bc, Color(CRIMSON.r, CRIMSON.g, CRIMSON.b, 0.0)], true)
	pm.scale_curve = _curve_tex([[0.0, 0.5], [0.3, 1.0], [1.0, 0.2]])
	root.add_child(fl)
	var em := Fx.aura(root, Color(1.0, 0.7, 0.3), 6 if lite else 12, 1.2, 0.05, 1.4, 0.8, rad * 0.6, 30.0)
	em.local_coords = false
	var lt := OmniLight3D.new()
	lt.light_color = bc
	lt.light_energy = 0.9
	lt.omni_range = 3.5
	lt.shadow_enabled = false
	root.add_child(lt)
	root.set_meta("until", Time.get_ticks_msec() / 1000.0 + dur)
	root.set_meta("light", lt)
	root.set_process(false)
	# counts itself down (the enemy's burn_t is gameplay; this only has to end near the same time)
	var tm := Timer.new()
	tm.wait_time = 0.25
	tm.autostart = true
	root.add_child(tm)
	tm.timeout.connect(func():
		if not is_instance_valid(root):
			return
		var left: float = float(root.get_meta("until")) - Time.get_ticks_msec() / 1000.0
		if left <= 0.0:
			fl.emitting = false
			em.emitting = false
			lt.light_energy = 0.0
			tm.stop()
			Fx._free_later(root, 1.5)
		else:
			fl.amount_ratio = clampf(left / 0.8, 0.25, 1.0))

# ---------------------------------------------------------------- the end of the flight
## Where the flight ends (its range run out, or a wall): the phoenix burst: a flash and a star of light, the fire
## swelling open with feather embers thrown out of it, a shock ring over the ground, stone chunks and bouncing
## sparks, brief flames on the ground, a puff of smoke rising, a scorch, the light dying away.
static func finish(h: Hero, kind: String, pos: Vector3, dir: Vector3, wall: bool) -> void:
	var p := preset(kind)
	if not p.has("end"):
		return
	var en: Dictionary = p["end"]
	var root: Node3D = h.game.world.fx_root
	var g: Vector3 = Vector3(pos.x, h.game.world.height_at(pos.x, pos.z), pos.z)
	var col: Color = en["col"]
	var lite := cheap(h.game)
	var at := pos - dir * 0.3
	Fx.flash(root, at, col, float(en["light"]), 0.55, 9.0)
	_flash_sprite(root, at, Color(1, 0.9, 0.7), 2.4, 0.3)
	# the fire swelling open: a sphere of flame growing and thinning
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 24
	sm.rings = 12
	ball.mesh = sm
	var m := ShaderMaterial.new()
	m.shader = shader("flame")
	m.set_shader_parameter("energy", 3.0)
	m.set_shader_parameter("speed", 6.0)
	m.set_shader_parameter("scale", 2.0)
	m.set_shader_parameter("c_core", Color(1, 0.95, 0.8))
	m.set_shader_parameter("c_mid", ORANGE)
	m.set_shader_parameter("c_edge", CRIMSON)
	m.set_shader_parameter("c_tip", VIOLET)
	m.set_shader_parameter("solid", 1.0)
	ball.material_override = m
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	ball.global_position = at
	ball.scale = Vector3.ONE * 0.3
	var tw := ball.create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3(2.6, 3.0, 2.6), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ball, "global_position", at + Vector3(0, 0.9, 0), 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.5).set_ease(Tween.EASE_IN)
	Fx._free_later(ball, 0.55)
	# feather embers flung out of the burst in every direction, fluttering down
	var pe := _textured_particles("feathers", int(en["embers"]) / (2 if lite else 1), 1.3, Vector2(0.07, 0.26), true)
	pe.one_shot = true
	pe.explosiveness = 0.95
	var pm := pe.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -2.5, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.angular_velocity_min = -300.0
	pm.angular_velocity_max = 300.0
	pm.color_ramp = _ramp([Color(1, 0.95, 0.8), ORANGE, CRIMSON, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.0)], true)
	pm.scale_curve = _curve_tex([[0.0, 0.7], [0.15, 1.0], [1.0, 0.3]])
	root.add_child(pe)
	pe.global_position = at
	pe.emitting = true
	Fx._free_later(pe, 1.9)
	# sparks that fall and bounce on the ground
	var sp := Fx.burst(root, at, Color(1.0, 0.82, 0.45), int(en["sparks"]) / (2 if lite else 1), 9.0, 0.06, 0.9, true, -12.0, 100.0, Vector3.UP)
	var spm := sp.process_material as ParticleProcessMaterial
	spm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	spm.damping_min = 1.0
	spm.damping_max = 3.0
	if float(en.get("ring", 0.0)) > 0.0:
		Fx.ring(root, g, float(en["ring"]), Color(1.0, 0.55, 0.2), 0.45, 0.15)
	if en.get("chunks", false) and not lite:
		Fx._slam_chunks(root, g)
	if en.get("flames", false):
		var f := Props.fire(root, g + Vector3(0, 0.05, 0), 1.3, ORANGE, false, false, not lite)
		var ft := f.create_tween()
		ft.tween_interval(0.9)
		ft.tween_callback(func():
			for c in f.get_children():
				if c is GPUParticles3D:
					(c as GPUParticles3D).emitting = false)
		Fx._free_later(f, 3.5)
	if int(en.get("smoke", 0)) > 0 and not lite:
		var smk := _textured_particles("smoke", int(en["smoke"]), 2.2, Vector2(1.1, 1.1), false)
		smk.one_shot = true
		smk.explosiveness = 0.8
		var kpm := smk.process_material as ParticleProcessMaterial
		kpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		kpm.emission_sphere_radius = 0.4
		kpm.direction = Vector3.UP
		kpm.spread = 40.0
		kpm.initial_velocity_min = 0.8
		kpm.initial_velocity_max = 2.2
		kpm.gravity = Vector3(0, 0.7, 0)
		kpm.damping_min = 1.0
		kpm.damping_max = 2.0
		kpm.angular_velocity_min = -30.0
		kpm.angular_velocity_max = 30.0
		kpm.color_ramp = _ramp([Color(0.3, 0.18, 0.2, 0.0), Color(0.16, 0.1, 0.17, 0.6), Color(0.12, 0.09, 0.14, 0.35), Color(0.1, 0.08, 0.12, 0.0)], false)
		kpm.scale_curve = _curve_tex([[0.0, 0.3], [0.5, 1.0], [1.0, 1.6]])
		root.add_child(smk)
		smk.global_position = at
		smk.emitting = true
		Fx._free_later(smk, 2.8)
	if en.get("scorch", false):
		scorch(h.game, g, dir, 3.2, 1.2)
	GrassField.impulse(g, 2.5, 0.7, 0.4)
	_sounds(h, p, "end", at)
	if wall:
		SkillFx.shake(h, 0.1)

## A burn streak on the ground along dir (the painted scorch, phoenix_scorch.png): its embers glow and go out,
## the soot fades over a few seconds.
static func scorch(game, g: Vector3, dir: Vector3, length: float, width: float) -> void:
	var t := tex("scorch")
	if t == null:
		return
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(length, width)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = shader("scorch")
	m.set_shader_parameter("tex", t)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.world.fx_root.add_child(mi)
	mi.global_position = Vector3(g.x, game.world.height_at(g.x, g.z) + 0.05, g.z)
	mi.rotation.y = atan2(-dir.z, dir.x)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_method(func(v: float): m.set_shader_parameter("glow", v), 1.6, 0.0, 2.2).set_ease(Tween.EASE_IN)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 6.0).set_delay(1.5)
	Fx._free_later(mi, 7.6)

# ---------------------------------------------------------------- sounds
## The preset's layers for a moment: flat on the caster, positional from the puppet or from a place.
static func _sounds(h: Hero, p: Dictionary, when: String, at := Vector3.INF) -> void:
	var snd: Dictionary = p.get("sounds", {})
	for s in snd.get(when, []):
		if at != Vector3.INF:
			Sfx.play_at(str(s[0]), at, float(s[1]), float(s[2]))
		else:
			SkillFx.snd(h, str(s[0]), float(s[1]), float(s[2]))

static func sounds(h: Hero, kind: String, when: String) -> void:
	_sounds(h, preset(kind), when)

# ---------------------------------------------------------------- pieces
## A tapered tube along +z (the arrow's tail side), UV.y 0 at its narrow head, 1 at its open end; `cone` opens
## wide at the far end instead of tapering back in.
static func _tube(length: float, r: float, cone := false) -> Mesh:
	var key := "%.2f|%.2f|%d" % [length, r, int(cone)]
	if _tube_cache.has(key):
		return _tube_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 10
	var segs := 12
	var prof := []
	for i in rings + 1:
		var t := float(i) / rings
		var rr: float
		if cone:
			rr = r * (0.12 + 0.88 * pow(t, 0.8))
		else:
			rr = r * (0.15 + 0.85 * sin(clampf(t * 1.25, 0.0, 1.0) * PI) * (1.0 - 0.3 * t) + 0.1 * (1.0 - t))
			if t > 0.8:
				rr *= (1.0 - t) / 0.2 * 0.9 + 0.1
		prof.append([Vector3(0, 0, -0.1 + length * t), rr, t])
	for i in rings:
		for j in segs:
			var a0 := TAU * j / segs
			var a1 := TAU * (j + 1) / segs
			var v := []
			for q in [[i, a0], [i + 1, a0], [i + 1, a1], [i, a1]]:
				var pr: Array = prof[q[0]]
				var ang: float = q[1]
				var n := Vector3(cos(ang), sin(ang), 0)
				v.append([(pr[0] as Vector3) + n * float(pr[1]), n, Vector2(float(j) / segs if q[1] == a0 else float(j + 1) / segs, float(pr[2]))])
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(v[idx][1])
				st.set_uv(v[idx][2])
				st.add_vertex(v[idx][0])
	var mesh := st.commit()
	_tube_cache[key] = mesh
	return mesh

static func _glow_quad(col: Color, size: float, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = Mats.soft_dot()
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy, 1.0)
	m.disable_receive_shadows = true
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## A starburst sprite (the Holy Slam burst, tinted) standing up to the camera, flaring and gone.
static func _flash_sprite(root: Node3D, pos: Vector3, col: Color, size: float, dur: float) -> void:
	var t := tex("burst")
	if t == null:
		return
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = shader("sprite")
	m.set_shader_parameter("tex", t)
	m.set_shader_parameter("tint", Color(col.r, col.g, col.b, 1.0))
	m.set_shader_parameter("energy", 1.8)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.3
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, dur * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, dur).set_ease(Tween.EASE_IN)
	Fx._free_later(mi, dur + 0.05)

## Particles drawn with one of the painted strips (a random frame each), additive or alpha-blended.
static func _textured_particles(key: String, amount: int, life: float, size: Vector2, additive: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	var frames: int = FRAMES.get(key, 1)
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.anim_speed_min = 0.0
	pm.anim_speed_max = 0.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = frames
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(2.2, 2.2, 2.2) if additive else Color.WHITE
	var t := tex(key)
	if t != null:
		m.albedo_texture = t
	else:
		m.albedo_texture = Mats.soft_dot()
	m.disable_receive_shadows = true
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

static func _ramp(cols: Array, fade_out: bool) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(float(i) / (cols.size() - 1), cols[i])
	if fade_out:
		var last: Color = cols[cols.size() - 1]
		g.set_color(g.get_point_count() - 1, Color(last.r, last.g, last.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

static func _curve_tex(pts: Array) -> CurveTexture:
	var c := Curve.new()
	for p in pts:
		c.add_point(Vector2(float(p[0]), float(p[1])))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

# ---------------------------------------------------------------- shaders
## A sheath of fire round a shaft (a tube, UV.y from the head to the tail): two octaves of noise scrolling
## toward the tail, a heat value from them shaded core -> mid -> edge -> tip (violet), soft at the sides.
const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
%s
uniform float energy = 3.0;
uniform float speed = 6.0;
uniform float scale = 3.0;
uniform float seed = 0.0;
uniform float alpha_mul = 1.0;
uniform float solid = 0.0;
uniform vec4 c_core : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 c_mid : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 c_edge : source_color = vec4(0.85, 0.12, 0.04, 1.0);
uniform vec4 c_tip : source_color = vec4(0.55, 0.2, 0.9, 1.0);
void vertex(){
	float w = sin(UV.y * 11.0 - TIME * speed * 1.6 + seed + UV.x * 6.283) * 0.08 * UV.y;
	VERTEX += NORMAL * w * length(VERTEX.xy);
}
void fragment(){
	vec2 p = vec2(UV.x * 3.0 + seed, UV.y * scale - TIME * speed * 0.35 + seed);
	float n = fbm3(p);
	float n2 = fbm3(p * 2.3 + vec2(3.1, -TIME * speed * 0.25));
	float along = UV.y;
	float body = 1.0 - smoothstep(0.55, 1.0, along);
	float heat = clamp((n * 0.75 + n2 * 0.45) * 1.5 - 0.25 - along * 0.55, 0.0, 1.0) * body;
	float rim = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	heat *= mix(0.35 + 0.65 * pow(rim, 0.7), 1.0, solid);
	vec3 col = mix(c_tip.rgb, c_edge.rgb, smoothstep(0.0, 0.28, heat));
	col = mix(col, c_mid.rgb, smoothstep(0.25, 0.62, heat));
	col = mix(col, c_core.rgb, smoothstep(0.62, 0.95, heat));
	float a = clamp(heat * 1.4, 0.0, 1.0) * alpha_mul;
	ALBEDO = col * energy * a;
	ALPHA = a;
}
"""

## A painted feather / flame card from a strip of frames, lit HDR with a flicker, its root faded.
const CARD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float frames = 8.0;
uniform float frame = 0.0;
uniform float energy = 2.0;
uniform float seed = 0.0;
uniform float alpha_mul = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
void vertex(){
	// the barbs ripple along the feather
	VERTEX.x += sin(TIME * 11.0 + seed + UV.y * 7.0) * 0.025 * (1.0 - UV.y);
}
void fragment(){
	vec2 uv = vec2((UV.x + frame) / frames, UV.y);
	vec4 t = texture(tex, uv);
	float flick = 0.82 + 0.18 * sin(TIME * 21.0 + seed + UV.y * 5.0) * sin(TIME * 13.0 + seed * 1.7);
	float a = t.a * alpha_mul * smoothstep(1.0, 0.8, UV.y);
	ALBEDO = t.rgb * tint.rgb * energy * flick * a;
	ALPHA = a;
}
"""

## The ribbon behind the arrow (UV.x 0 at the head, 1 at the tail; UV.y across): fire at the head thinning into
## smoke at the tail, its edges eaten by noise so it never reads as a flat band.
const TRAIL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
%s
uniform float energy = 2.5;
uniform float alpha_mul = 1.0;
uniform vec4 c_head : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform vec4 c_mid : source_color = vec4(1.0, 0.42, 0.06, 1.0);
uniform vec4 c_tail : source_color = vec4(0.5, 0.12, 0.6, 1.0);
uniform vec4 c_smoke : source_color = vec4(0.1, 0.06, 0.12, 1.0);
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	float along = UV.x;
	float across = abs(UV.y - 0.5) * 2.0;
	// tongues of flame licking back along the ribbon, breaking its edges up
	vec2 np = vec2(along * 6.0 + wpos.x * 0.7 + wpos.z * 0.7, UV.y * 2.5 + wpos.y);
	float n = fbm3(np + vec2(-TIME * 2.5, TIME * 0.7));
	float n2 = vnoise(np * 3.0 + vec2(-TIME * 5.0, 0.0));
	float edge = 1.0 - smoothstep(0.15, 0.85, across + (n - 0.45) * 1.1 + along * 0.35);
	float fire = pow(1.0 - along, 1.4) * (0.4 + 0.8 * n2) * edge;
	float heat = clamp(fire * 1.5, 0.0, 1.0);
	vec3 fl = mix(c_tail.rgb, c_mid.rgb, smoothstep(0.08, 0.4, heat));
	fl = mix(fl, c_head.rgb, smoothstep(0.45, 0.95, heat));
	float smoke = edge * (1.0 - pow(1.0 - along, 2.5)) * (0.25 + 0.45 * n) * (1.0 - along * along);
	float a = clamp(heat * 0.85 + smoke * 0.5, 0.0, 1.0) * alpha_mul;
	float k = clamp(heat / max(heat + smoke * 0.5, 0.001), 0.0, 1.0);
	vec3 col = mix(c_smoke.rgb, fl * energy * (0.6 + 0.4 * heat), k);
	ALBEDO = col;
	ALPHA = a;
}
"""

## The heat haze: the scene behind the card bent by drifting noise, strongest at the centre (Forward+ only).
const SHIMMER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
%s
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.014;
uniform float alpha_mul = 1.0;
void fragment(){
	float d = 1.0 - smoothstep(0.1, 0.5, distance(UV, vec2(0.5)));
	vec2 off = vec2(fbm3(UV * 5.0 + vec2(0.0, TIME * 3.5)) - 0.5, fbm3(UV * 5.0 + vec2(7.0, TIME * 2.9)) - 0.5) * strength * d;
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
	ALPHA = d * alpha_mul * 0.9;
}
"""

## A camera-facing additive sprite whose brightness is its alpha (painted on black), never showing its square.
const SPRITE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 1.5;
uniform float alpha_mul = 1.0;
void vertex(){
	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	vec3 right = vec3(INV_VIEW_MATRIX[0].xyz) * length(MODEL_MATRIX[0].xyz);
	vec3 up = vec3(INV_VIEW_MATRIX[1].xyz) * length(MODEL_MATRIX[1].xyz);
	vec3 wp = MODEL_MATRIX[3].xyz + right * VERTEX.x + up * VERTEX.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}
void fragment(){
	vec4 t = texture(tex, UV);
	float a = max(t.r, max(t.g, t.b)) * alpha_mul;
	ALBEDO = t.rgb * tint.rgb * energy * a;
	ALPHA = a;
}
"""

## The burn streak laid on the ground: soot alpha-blended, its embers emissive while `glow` lasts.
const SCORCH_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float glow = 1.5;
uniform float alpha_mul = 1.0;
void fragment(){
	vec4 t = texture(tex, UV);
	float ember = clamp((t.r - 0.35) * 2.0, 0.0, 1.0) * glow;
	float pulse = 0.85 + 0.15 * sin(TIME * 6.0 + UV.x * 20.0);
	ALBEDO = t.rgb * 0.5 + t.rgb * ember * 2.5 * pulse;
	ALPHA = t.a * alpha_mul;
}
"""
