class_name PlagueExperimentFx
extends RefCounted
## The Last Experiment's look (the Plague Doctor's V, his ultimate; gameplay in plague.gd).
##
## Stage 1, the vat: the Meshy vat (assets/models/plague/vat.glb: a brass-bound glass cylinder on clawed iron feet with
## a crank and gauges, a pickled thing curled in green fluid) drops from his hands and slams into the ground (dust
## rolling out, the fog simulation), and the quarantine's boundary is drawn at once at its full size (`ZONE_SHADER`:
## the Meshy ring of fungal growth, so everyone sees where to leave). While he cranks (`charge`), the vat shudders
## harder and harder, its fluid boils (bubbles, a sick light flickering faster), steam (the Mantaflow vapour) spurts
## from the valves.
## Stage 2, the burst (`burst`): the vat's own glass flies apart (vat_shards.glb: its cylinder fractured into curved
## panes in Blender, tools/blender/plague/vat_glass.py), its fluid bursts out in a wave (vat_wave.png: a Blender FLIP
## simulation of the vat's contents thrown out and slumping into a flood, splash_flipbook.py KIND=wave), the
## contamination floods the zone (`ZONE_SHADER` "flood": the Meshy mould painting with its baked normals spreading
## out to the ring), a haze of the spore simulation hangs in it with spores raining, the light turns green, and the
## homunculus (the Meshy creature, rigged and animated by Meshy: assets/models/plague/homunculus.glb) screams and
## crawls out of the wreck. It lumbers after the nearest foe inside the zone (`creature_step`); each spew is first a
## ghost of the Meshy bile-spray painting on the ground, filling from its mouth over SPEW_WARN with a bright front
## (`spew`, `FAN_SHADER`), then a gout of bile along it that leaves the painting there wet and drying.
## The end (`collapse`): it falls dead, the spores rise and drain back into its body, the stain dries and fades.
## None of it is an area blow (Fx.ring): it never scatters his own swarm.

const VAT_GLB := "res://assets/models/plague/vat.glb"
const SHARDS_GLB := "res://assets/models/plague/vat_shards.glb"
const CREATURE_GLB := "res://assets/models/plague/homunculus.glb"
const WAVE_BOOK := "res://assets/textures/fx/vat_wave.png"     # 6 x 4, the frame 4.5 m across (4.8 m ortho x 0.938 crop)
const FAN_TEX := "res://assets/textures/plague/bile_fan_albedo.png"
const FAN_NRM := "res://assets/textures/plague/bile_fan_normal.png"
## the vat's glass: where its cylinder sits on the model (the panes are cut from a cylinder 0.12..0.92 m up)
const GLASS_LIFT := 0.23
const BILE := Color(0.55, 0.85, 0.2)
const HAZARD := Color(0.75, 1.0, 0.3)
const CREATURE_SPEED := 2.5
const CREATURE_SCALE := 0.9

class Vat extends Node3D:
	var w: World
	var vat: Node3D
	var zone: MeshInstance3D
	var zmat: ShaderMaterial
	var lamp: OmniLight3D
	var boil: GPUParticles3D
	var rain: GPUParticles3D
	var haze: GPUParticles3D
	var creature: Node3D
	var anim: AnimationPlayer
	var c_pos := Vector3.ZERO
	var c_yaw := 0.0
	var r := 8.0
	var age := 0.0
	var shake := 0.0
	var burst_t := -1.0
	var dying := -1.0
	func setup(world: World, g: Vector3, radius: float) -> void:
		w = world
		r = radius
		zone = PlagueVialFx._ground_disc(w, g, radius * 1.04, 16, 72, 0.05)
		zmat = ShaderMaterial.new()
		zmat.shader = PlagueExperimentFx._zone_shader()
		zmat.set_shader_parameter("flood", 0.0)
		zmat.set_shader_parameter("rad", 1.0)
		zmat.set_shader_parameter("fade", 1.0)
		zmat.set_shader_parameter("seed", randf() * 40.0)
		zmat.set_shader_parameter("rot", randf() * TAU)
		zmat.set_shader_parameter("blight", PlagueVialFx._tex("res://assets/textures/plague/blight_albedo.png"))
		zmat.set_shader_parameter("blight_n", PlagueVialFx._tex("res://assets/textures/plague/blight_normal.png"))
		zmat.set_shader_parameter("ringtex", PlagueVialFx._tex("res://assets/textures/plague/ring_albedo.png"))
		zone.material_override = zmat
		add_child(zone)
		zone.position = Vector3(0, -g.y, 0)
		vat = Node3D.new()
		add_child(vat)
		if ResourceLoader.exists(PlagueExperimentFx.VAT_GLB):
			vat.add_child((load(PlagueExperimentFx.VAT_GLB) as PackedScene).instantiate())
		vat.rotation.y = randf() * TAU
		vat.position = Vector3(0, 1.6, 0)
		var tw := vat.create_tween()
		tw.tween_property(vat, "position", Vector3.ZERO, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(_landed)
		lamp = OmniLight3D.new()
		lamp.light_color = PlagueExperimentFx.BILE
		lamp.light_energy = 0.5
		lamp.omni_range = 3.0
		lamp.position = Vector3(0, 0.9, 0)
		add_child(lamp)
		boil = Fx.aura(self, Color(0.7, 1.0, 0.6, 0.8), 20, 0.4, 0.02, 0.6, 1.2, 0.3, 20.0, Vector3(0, 0.5, 0))
		boil.name = "boil"
	func _landed() -> void:
		var g := global_position
		Fx.burst(self, g + Vector3(0, 0.2, 0), Color(0.25, 0.2, 0.16, 0.8), 22, 3.5, 0.1, 0.7, false, -9.0, 75.0)
		# dust thrown out level all round as it slams down
		PlagueSmoke.puffs(self, g + Vector3(0, 0.25, 0), PlagueSmoke.FOG, Color(0.42, 0.36, 0.3, 0.6), 10, 1.2, 1.2, 4.0, 0.4, 0.0, 0.0, Vector3.UP, true)
	## Stage 1's crank (0..1): it shudders harder, boils, the light flickers faster, steam spurts.
	func charge(f: float) -> void:
		shake = f
		if boil != null:
			boil.amount_ratio = 0.3 + 0.7 * f
		if randf() < f * 0.06:
			var at := global_position + Vector3(randf_range(-0.35, 0.35), 1.45, randf_range(-0.35, 0.35))
			PlagueSmoke.puffs(self, at, PlagueSmoke.VAPOUR, Color(0.92, 0.92, 0.95, 0.55), 3, 0.5, 0.8, 1.4, 0.05, 1.2, 25.0)
	func burst(radius: float) -> void:
		r = radius
		burst_t = 0.0
		shake = 0.0
		zmat.set_shader_parameter("rad", radius / maxf(zone_r(), 0.01))
		var g := global_position
		# the vat's own glass flies apart: its cylinder's curved panes, flung out from where each sat
		if ResourceLoader.exists(PlagueExperimentFx.SHARDS_GLB):
			var src: Node3D = (load(PlagueExperimentFx.SHARDS_GLB) as PackedScene).instantiate()
			var gm := PlagueVialFx.glass_mat_2side(Color(0.7, 0.95, 0.75))
			var turn := vat.rotation.y if vat != null else 0.0
			for mi in src.find_children("*", "MeshInstance3D", true, false):
				var d := PlagueVialFx.Debris.new()
				var m := MeshInstance3D.new()
				m.mesh = (mi as MeshInstance3D).mesh
				m.material_override = gm
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				d.add_child(m)
				add_child(d)
				var loc: Vector3 = (mi as Node3D).position.rotated(Vector3.UP, turn)
				d.global_position = g + Vector3(loc.x, loc.y + PlagueExperimentFx.GLASS_LIFT, loc.z)
				d.rotation.y = turn
				var out := Vector3(loc.x, 0, loc.z).normalized() if Vector2(loc.x, loc.z).length() > 0.001 else Vector3.RIGHT
				d.vel = out.rotated(Vector3.UP, randf_range(-0.35, 0.35)) * randf_range(4.0, 9.0) + Vector3(0, randf_range(2.0, 5.5), 0)
				d.spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(5.0, 14.0)
				d.floor_y = g.y + 0.04
				d.life = randf_range(1.8, 2.8)
			src.free()
		# the fluid bursts out: the simulated wave, droplets, a breath of its vapour, a flash
		_wave(g)
		Fx.burst(self, g + Vector3(0, 0.8, 0), PlagueExperimentFx.BILE, 60, 7.0, 0.08, 0.9, true, -9.0, 80.0)
		PlagueSmoke.puffs(self, g + Vector3(0, 0.6, 0), PlagueSmoke.VAPOUR, Color(0.55, 0.72, 0.35, 0.5), 14, 1.6, 1.6, r * 0.9, 0.5, 0.6, 0.0, Vector3.UP, true)
		Fx.flash(self, g + Vector3(0, 1.0, 0), PlagueExperimentFx.BILE, 3.5, 0.5, r * 1.4)
		if vat != null:
			var tw := vat.create_tween()
			tw.tween_property(vat, "scale", Vector3(1.15, 0.35, 1.15), 0.12)
			tw.tween_property(vat, "scale", Vector3(1.0, 0.25, 1.0), 0.3)
		if boil != null:
			boil.emitting = false
		lamp.omni_range = r * 1.3
		lamp.light_energy = 1.0
		# the spore rain over the whole zone
		rain = GPUParticles3D.new()
		rain.amount = int(clampf(r * r * 3.0, 60.0, 260.0))
		rain.lifetime = 2.6
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = r * 0.95
		pm.emission_ring_inner_radius = 0.0
		pm.emission_ring_height = 0.5
		pm.direction = Vector3.DOWN
		pm.spread = 20.0
		pm.initial_velocity_min = 0.3
		pm.initial_velocity_max = 0.9
		pm.gravity = Vector3(0.1, -0.6, 0.05)
		pm.scale_min = 0.5
		pm.scale_max = 1.2
		var gr := Gradient.new()
		gr.set_color(0, Color(0.85, 1.0, 0.5, 0.0))
		gr.add_point(0.2, Color(0.85, 1.0, 0.5, 0.9))
		gr.set_color(gr.get_point_count() - 1, Color(0.6, 0.8, 0.3, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = gr
		pm.color_ramp = gt
		rain.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.06, 0.06)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.vertex_color_use_as_albedo = true
		qm.albedo_texture = PlagueVialFx.wisp_tex()
		q.material = qm
		rain.draw_pass_1 = q
		rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rain.position = Vector3(0, 3.6, 0)
		add_child(rain)
		# a haze of the spore simulation hanging low over the whole zone
		haze = PlagueSmoke.vapour(self, Color(0.68, 0.8, 0.42, 0.28), int(clampf(r * 2.2, 8.0, 20.0)), 2.2, 3.2, 0.12, r * 0.85, Vector3(0, 0.6, 0), Color(0, 0, 0), PlagueSmoke.SPORE, true)
		_spawn_creature()
	## The vat's fluid bursting out (vat_wave.png) on a card standing at the vat, facing the camera about the
	## vertical; it draws over what stands round it (the burst is in front of and around everything near).
	func _wave(g: Vector3) -> void:
		var book := PlagueVialFx._tex(PlagueExperimentFx.WAVE_BOOK)
		if book == null:
			return
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		var size := clampf(r * 0.95, 4.5, 8.0)
		q.size = Vector2(size, size)
		# the simulation's floor centre sits 3.4% of the frame below its middle
		q.center_offset = Vector3(0, size * 0.034, 0)
		m.mesh = q
		var sh := ShaderMaterial.new()
		sh.shader = PlagueExperimentFx._wave_shader()
		sh.set_shader_parameter("book", book)
		sh.set_shader_parameter("t", 0.0)
		sh.set_shader_parameter("tint", PlagueExperimentFx.BILE)
		sh.set_shader_parameter("flip", 1.0 if randf() < 0.5 else -1.0)
		m.material_override = sh
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		m.global_position = g
		var tw := m.create_tween()
		tw.tween_method(func(v: float) -> void: sh.set_shader_parameter("t", v), 0.0, 1.0, 0.95)
		tw.tween_callback(m.queue_free)
	func zone_r() -> float:
		return r if burst_t < 0.0 else r
	func _spawn_creature() -> void:
		if not ResourceLoader.exists(PlagueExperimentFx.CREATURE_GLB):
			return
		creature = (load(PlagueExperimentFx.CREATURE_GLB) as PackedScene).instantiate()
		add_child(creature)
		creature.scale = Vector3.ONE * PlagueExperimentFx.CREATURE_SCALE
		c_pos = global_position
		creature.global_position = c_pos
		c_yaw = vat.rotation.y if vat != null else 0.0
		for mi in creature.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var aps := creature.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			anim = aps[0]
			for lib in anim.get_animation_library_list():
				for nm in anim.get_animation_library(lib).get_animation_list():
					var a: Animation = anim.get_animation_library(lib).get_animation(nm)
					ForestCamp._pin_root(a)
					if "Walk" in nm or "Idle" in nm:
						a.loop_mode = Animation.LOOP_LINEAR
			_play("Zombie_Scream")
		var drip := Fx.aura(creature, Color(PlagueExperimentFx.BILE.r, PlagueExperimentFx.BILE.g, PlagueExperimentFx.BILE.b, 0.9), 10, 0.2, 0.03, 0.9, -5.0, 0.3, 30.0, Vector3(0, 1.2, 0))
		drip.name = "drip"
		creature.scale = Vector3(0.6, 0.2, 0.6) * PlagueExperimentFx.CREATURE_SCALE
		var tw := creature.create_tween()
		tw.tween_property(creature, "scale", Vector3.ONE * PlagueExperimentFx.CREATURE_SCALE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	func _play(nm: String) -> void:
		if anim == null:
			return
		for full in anim.get_animation_list():
			if str(full).ends_with(nm):
				if anim.current_animation != full:
					anim.play(full, 0.25)
				return
	func creature_pos() -> Vector3:
		return c_pos + Vector3(0, 1.1, 0)
	## The creature lumbers after the nearest foe inside the zone (it never leaves it), screaming first.
	func creature_step(delta: float, foes: Array, center: Vector3, radius: float) -> void:
		if creature == null or dying >= 0.0 or burst_t < 0.9:
			return
		var best: Node3D = null
		var bd := 1e9
		for e in foes:
			var d := (e as Node3D).global_position.distance_to(c_pos)
			if d < bd:
				bd = d
				best = e
		if best != null and bd > 1.6:
			var dir := (best.global_position - c_pos) * Vector3(1, 0, 1)
			var step := dir.normalized() * PlagueExperimentFx.CREATURE_SPEED * delta
			var np := c_pos + step
			var off := (np - center) * Vector3(1, 0, 1)
			if off.length() > radius * 0.9:
				np = center + off.normalized() * radius * 0.9
			c_pos = Vector3(np.x, w.height_at(np.x, np.z), np.z)
			c_yaw = lerp_angle(c_yaw, atan2(-dir.x, -dir.z), clampf(delta * 5.0, 0.0, 1.0))
			_play("Slow_Orc_Walk")
		else:
			if best != null:
				var dir2 := (best.global_position - c_pos) * Vector3(1, 0, 1)
				c_yaw = lerp_angle(c_yaw, atan2(-dir2.x, -dir2.z), clampf(delta * 5.0, 0.0, 1.0))
			_play("Idle")
		creature.global_position = c_pos
		creature.rotation.y = c_yaw + PI
	func collapse() -> void:
		if dying >= 0.0:
			return
		dying = 0.0
		if rain != null:
			rain.emitting = false
		if haze != null:
			haze.emitting = false
		if creature != null:
			_play("Fall_Dead_from_Abdominal_Injury")
			if anim != null:
				anim.speed_scale = 1.2
			# the spores rise off the zone and drain into its body
			Fx.burst(self, c_pos + Vector3(0, 0.3, 0), Color(0.8, 1.0, 0.5, 0.8), 50, 2.0, 0.04, 1.2, true, 2.5, 80.0)
		Sfx.play_at("shade_implode", global_position, -4.0, 0.7)
	func _process(delta: float) -> void:
		age += delta
		if vat != null and shake > 0.0:
			vat.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.03 * shake * shake
			vat.rotation.z = sin(age * 40.0) * 0.03 * shake
			lamp.light_energy = 0.5 + shake * (0.6 + 0.6 * sin(age * (10.0 + 30.0 * shake)))
		if burst_t >= 0.0:
			burst_t += delta
			zmat.set_shader_parameter("flood", 1.0 - pow(1.0 - clampf(burst_t / 0.7, 0.0, 1.0), 2.0))
			lamp.light_energy = lerpf(lamp.light_energy, 0.9 + 0.2 * sin(age * 3.0), clampf(delta * 2.0, 0.0, 1.0))
		if dying >= 0.0:
			dying += delta
			var f := clampf(1.0 - dying / 2.2, 0.0, 1.0)
			zmat.set_shader_parameter("fade", f)
			lamp.light_energy *= 0.97
			if creature != null and dying > 1.6:
				creature.scale = creature.scale.lerp(Vector3.ZERO, clampf(delta * 2.0, 0.0, 1.0))
			if vat != null and dying > 1.0:
				vat.scale = vat.scale.lerp(Vector3.ZERO, clampf(delta * 2.0, 0.0, 1.0))
			if dying > 3.2:
				queue_free()

## A spew: a ghost of the bile-spray painting on the ground, the cone it covers, filling from the creature's mouth
## over `warn` with a bright front (everyone sees where the bile will go and when), then a gout along it that leaves
## the painting there, wet, drying and fading.
static func spew(lab: Dictionary, from: Vector3, toward: Vector3, warn: float, length: float, half: float) -> void:
	if lab.is_empty() or not is_instance_valid(lab.get("node")):
		return
	var v: Vat = lab["node"]
	var dir := (toward - from) * Vector3(1, 0, 1)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var fan := _ground_fan(v.w, from, dir, length, 2.0 * length * tan(half), 10, 12, 0.07)
	var sh := ShaderMaterial.new()
	sh.shader = _fan_shader()
	sh.set_shader_parameter("fan", PlagueVialFx._tex(FAN_TEX))
	sh.set_shader_parameter("fan_n", PlagueVialFx._tex(FAN_NRM))
	sh.set_shader_parameter("col", PlagueExperimentFx.BILE)
	sh.set_shader_parameter("fill", 0.0)
	sh.set_shader_parameter("wet", 0.0)
	sh.set_shader_parameter("fade", 1.0)
	fan.material_override = sh
	v.add_child(fan)
	fan.global_position = Vector3(from.x, 0.0, from.z)
	var ft := fan.create_tween()
	ft.tween_method(func(x: float) -> void: sh.set_shader_parameter("fill", x), 0.0, 1.0, warn)
	ft.tween_callback(func() -> void: sh.set_shader_parameter("wet", 1.0))
	ft.tween_interval(1.4)
	ft.tween_method(func(x: float) -> void: sh.set_shader_parameter("fade", x), 1.0, 0.0, 1.2)
	ft.tween_callback(fan.queue_free)
	var tw := v.create_tween()
	tw.tween_interval(warn)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(v):
			return
		v._play("Zombie_Scream")
		Fx.burst(v, from + dir * 0.3, PlagueExperimentFx.BILE, 70, length * 2.2, 0.08, 0.7, true, -6.0, rad_to_deg(half) * 0.8, dir + Vector3(0, 0.15, 0))
		PlagueSmoke.puffs(v, from + dir * 0.8, PlagueSmoke.VAPOUR, Color(0.5, 0.68, 0.28, 0.5), 8, 1.1, 1.0, length * 1.6, 0.2, 0.3, rad_to_deg(half), dir)
		Sfx.play_at("blight_burst", from, -3.0, 0.6))

## A grid laid over the ground from `from` along `dir` (`length` long, `width` wide at its far end), each vertex at
## the terrain's height plus `lift`; x/z relative to `from` (place it at from.x, 0, from.z). UV x across (0..1), y
## from the far end (0) to the mouth (1).
static func _ground_fan(w: World, from: Vector3, dir: Vector3, length: float, width: float, nx: int, nz: int, lift: float) -> MeshInstance3D:
	var right := dir.cross(Vector3.UP).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for j in nz + 1:
		var along := float(j) / nz
		for i in nx + 1:
			var across := float(i) / nx
			var p := from + dir * along * length + right * (across - 0.5) * width
			var y := (w.height_at(p.x, p.z) if w != null else from.y) + lift
			pts.append(Vector3(p.x - from.x, y, p.z - from.z))
			uvs.append(Vector2(across, 1.0 - along))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var quad := [a, a + nx + 1, a + nx + 2, a, a + nx + 2, a + 1]
			for k in quad:
				st.set_normal(Vector3.UP)
				st.set_uv(uvs[k])
				st.add_vertex(pts[k])
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

static var _fsh: Shader
## The spew on the ground: the Meshy bile-spray painting (keyed by colour off its grey floor, normals baked from its
## relief) mapped so its spray fans out from the mouth along the cone; the cone itself and a ghost of the painting
## filling out from the mouth as `fill` goes 0..1 with a bright front, then (`wet`) the painting itself, glossy, and
## `fade` drying it away.
static func _fan_shader() -> Shader:
	if _fsh != null:
		return _fsh
	_fsh = Shader.new()
	_fsh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
uniform sampler2D fan : source_color, filter_linear_mipmap;
uniform sampler2D fan_n : hint_normal, filter_linear_mipmap;
uniform vec4 col : source_color;
uniform float fill = 0.0;
uniform float wet = 0.0;
uniform float fade = 1.0;
void fragment() {
	// the painting's spray rises from (0.5, 0.88) of its image to its top edge (0.1)
	vec2 pv = vec2(0.12 + UV.x * 0.76, 0.1 + UV.y * 0.78);
	vec4 a = texture(fan, pv);
	float along = 1.0 - UV.y;
	float across = abs(UV.x - 0.5) * 2.0;
	float cone = smoothstep(1.02, 0.92, across / max(along, 0.001)) * smoothstep(0.0, 0.03, along);
	float filled = smoothstep(fill + 0.03, fill - 0.03, along);
	float front = smoothstep(0.07, 0.0, abs(along - fill)) * step(0.001, fill) * (1.0 - wet) * cone;
	float ghost = (cone * 0.22 + a.a * 0.38) * filled * (1.0 - wet);
	float splat = a.a * wet;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(fan_n, pv).rgb, splat);
	NORMAL_MAP_DEPTH = 1.4;
	ALBEDO = mix(col.rgb * 0.55, a.rgb * 0.9, wet);
	ROUGHNESS = mix(0.6, 0.06, wet);
	SPECULAR = 0.85;
	EMISSION = col.rgb * (front * 1.4 + ghost * 0.45) + a.rgb * splat * 0.12;
	ALPHA = clamp(ghost + front * 0.9 + splat, 0.0, 1.0) * fade;
}
"""
	return _fsh

static var _wsh: Shader
## The vat's wave: the FLIP simulation's flipbook (6 x 4, frames blended), its own light and colour kept, on a card
## facing the camera about the vertical, drawn over what is near (the liquid bursts out in front of and around it).
static func _wave_shader() -> Shader:
	if _wsh != null:
		return _wsh
	_wsh = Shader.new()
	_wsh.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, specular_schlick_ggx;
uniform sampler2D book : source_color, filter_linear_mipmap;
uniform float t = 0.0;
uniform vec4 tint : source_color;
uniform float flip = 1.0;
void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz - NODE_POSITION_WORLD;
	cam.y = 0.0;
	vec3 z = normalize(cam + vec3(0.0001));
	vec3 x = normalize(cross(vec3(0.0, 1.0, 0.0), z));
	vec3 wp = NODE_POSITION_WORLD + x * VERTEX.x * flip + vec3(0.0, 1.0, 0.0) * VERTEX.y;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(z, 0.0)).xyz;
}
vec4 cell(float f, vec2 uv) {
	vec2 c = vec2(mod(f, 6.0), floor(f / 6.0));
	return texture(book, (c + uv) / vec2(6.0, 4.0));
}
void fragment() {
	float ft = clamp(t, 0.0, 0.999) * 23.0;
	float f0 = floor(ft);
	vec4 c = mix(cell(f0, UV), cell(min(f0 + 1.0, 23.0), UV), fract(ft));
	float lum = dot(c.rgb, vec3(0.3, 0.55, 0.15));
	ALBEDO = mix(c.rgb, tint.rgb * lum * 1.2, 0.35);
	EMISSION = tint.rgb * lum * 0.3;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	ALPHA = c.a * (1.0 - smoothstep(0.7, 1.0, t));
}
"""
	return _wsh

static var _zsh: Shader
## The quarantine on the ground: its boundary is the Meshy ring of fungal growth (ring_albedo, remapped so its band
## lies thin along the zone's edge, its spore caps pulsing), there from the moment the vat lands; after the burst
## the Meshy mould patch (blight_albedo + its Blender-baked normals) floods out from the middle to the ring.
static func _zone_shader() -> Shader:
	if _zsh != null:
		return _zsh
	_zsh = Shader.new()
	_zsh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
uniform float flood = 0.0;
uniform float rad = 1.0;
uniform float fade = 1.0;
uniform float seed = 0.0;
uniform float rot = 0.0;
uniform sampler2D blight : source_color, filter_linear_mipmap;
uniform sampler2D blight_n : hint_normal, filter_linear_mipmap;
uniform sampler2D ringtex : source_color, filter_linear_mipmap;
varying vec2 lp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { lp = UV * 2.0 - 1.0; }
void fragment() {
	float c = cos(rot); float s = sin(rot);
	vec2 q = vec2(c * lp.x - s * lp.y, s * lp.x + c * lp.y) * 1.04 / max(rad, 0.01);
	float d = length(q);
	// the ring: radii 0.9..1.0 of the zone read from the painting's band (radii 0.6..0.97 of its image)
	vec2 dir = q / max(d, 0.0001);
	float band = clamp((d - 0.9) / 0.1, 0.0, 1.0);
	vec4 rg = texture(ringtex, 0.5 + dir * mix(0.6, 0.97, band) * 0.5);
	float in_band = step(0.9, d) * step(d, 1.0);
	float ra = rg.a * in_band;
	float caps = smoothstep(0.55, 0.85, rg.g - rg.r) * ra;
	// the flood: the mould patch spreading out to the ring after the burst
	vec2 uv = q * 0.5 / 0.92 + 0.5;
	vec4 bl = texture(blight, uv);
	float reach = flood * 0.95 + (noise(q * 5.0 + seed) - 0.5) * 0.08;
	float wet = bl.a * smoothstep(reach, reach - 0.06, d) * step(d, 0.94);
	vec3 n = texture(blight_n, uv).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), n, wet);
	NORMAL_MAP_DEPTH = 1.4;
	float lum = dot(bl.rgb, vec3(0.3, 0.55, 0.15));
	float pust = smoothstep(0.35, 0.65, lum) * wet;
	vec3 col = mix(rg.rgb * 0.85, bl.rgb * 0.9, wet / max(wet + ra, 0.001));
	ALBEDO = col;
	ROUGHNESS = mix(0.7, 0.12, wet);
	SPECULAR = 0.7;
	EMISSION = vec3(0.55, 0.95, 0.3) * (caps * (0.7 + 0.5 * sin(TIME * 3.0 + q.x * 9.0)) + pust * 0.3);
	ALPHA = clamp(max(ra * 0.95, wet), 0.0, 1.0) * fade;
}
"""
	return _zsh
