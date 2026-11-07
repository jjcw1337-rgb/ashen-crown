class_name ArrowFx
extends RefCounted
## The Archer's arrow effects, data-driven per arrow kind (PRESETS), so every bow skill gets the same treatment
## with its own identity (docs/systems/effects.md, the quality bar): a new skill is mostly a new preset.
## Everything here only DRAWS: it is called from ArcherFx (the "loose" event, the draw charge) and from
## Archer.update (the flight, each foe pierced, the end of the flight) on the caster's game and on his
## puppet's alike, so partners see the same arrow from the one "loose" event. Nothing here touches gameplay.
##
## The fire is SIMULATED, not painted: Mantaflow fire and smoke (tools/blender/fx/fire_sims.py) rendered into
## flipbooks (tools/fx_flipbook.py, assets/textures/fx/real_*.png). The flame sheets carry the sim's flame (R) and
## flame x temperature (G); FIRE_SHADER turns them into light through a blackbody curve (Kelvin), so the colour is
## the sim's own temperature: white-yellow where it is thick and hot, orange, then deep red where it thins. The
## smoke sheets carry an RGB lightmap (lit from the right / above / the left in Blender) and SMOKE_SHADER relights
## them in light() with the game's real lights: the sun, the fire's own OmniLights, shadows. Embers and sparks are
## points of blackbody light cooling as they fly (STREAK_SHADER, stretched along their velocity); the heat haze
## bends what is behind (HAZE_SHADER, Forward+); the burn mark is a Decal (soot albedo, a blistered normal map, ember
## cracks that cool); the flight's light casts shadows.
##
## A kind's preset:
##   "model"    the Meshy arrow (game/heroes/archer/weapon/arrows/<model>.glb, ArrowModel.make)
##   "heat"     {head, char}: the arrowhead glowing with heat and the shaft charring behind it (HEAT_SHADER overlay)
##   "flame"    {amount, life, size, energy, t}: sim flames wrapped round the head and blown back along the shaft
##   "ribbon"   {len, width, energy, smoke_len, smoke_width, smoke_col}: the flame's tail, one continuous strip rebuilt
##              every frame from the head's path (RIBBON_FIRE_SHADER: two offset frames of the sim flame stretched
##              along it, eaten by noise toward the tail), and the smoke strip behind it rising and widening with
##              age (RIBBON_SMOKE_SHADER, lit, its edges broken by noise)
##   "wisps"    {amount, life, size}: scraps of flame torn off and left behind in the air (optional)
##   "smoke"    {amount, life, size, col, alpha}: the smoke trail, lit by the scene
##   "embers"   {amount, life, size, t}: glowing embers drifting off on the turbulence
##   "sparks"   {amount, life, size, speed, t}: hot sparks shed in flight
##   "light"    {t, energy, range, shadow}: the moving light (Kelvin; at most LIGHT_CAP arrows lit at once)
##   "haze"     {amount, size, strength}: heat distortion behind the head (Forward+ only, never on Low / web)
##   "release" / "draw" / "pierce" / "end" / "burn": the moments, below
##   "surfaces" {grass, stone, dirt, wood, dark}: how the end of the flight meets the ground (ArrowFx.surface)
##   "sounds"   {cast, release, pierce, end}: [name, dB, pitch] layers, through SkillFx.snd / Sfx.play_at
## The simulated flames, the shaders and a body set alight are FlameFx (game/systems/fx/fire/), shared with every
## burn in the game; the clock is GameClock.

const LIGHT_CAP := 3
const SUBSTEPS := 4
const BURST_START := 4.0

const PRESETS := {
	## Fire Arrow: a pitch-soaked arrow on fire. Real flames (the sim) wrapped round the head and blown back along
	## the shaft, the head glowing and the shaft charring, torn scraps of flame, a trail of lit smoke, embers on the
	## turbulence and sparks; its light moves over the ground and casts shadows. Through a foe: a gout of fire out of
	## his back and the burn on him; where the flight ends: a fireball, smoke rolling up, sparks bouncing, embers,
	## a scorch, and the ground answering (grass smoulders, stone throws sparks, dirt kicks up dust, wood catches).
	"fire": {
		"model": "fire",
		"heat": {"head": 1.0, "char": 1.0},
		"flame": {"amount": 12, "life": 0.4, "size": [0.4, 0.7], "energy": 4.0, "t": [1000.0, 2400.0]},
		"ribbon": {"len": 2.6, "width": 0.46, "energy": 3.2, "smoke_len": 7.5, "smoke_width": 0.75, "smoke_col": Color(0.3, 0.285, 0.27)},
		"smoke": {"amount": 60, "life": 1.7, "size": [0.35, 1.1], "col": Color(0.36, 0.34, 0.33), "alpha": 0.55},
		"embers": {"amount": 36, "life": [0.6, 1.6], "size": 0.018, "t": [1900.0, 850.0]},
		"sparks": {"amount": 18, "life": [0.15, 0.4], "size": 0.01, "speed": 3.0, "t": [2400.0, 1100.0]},
		"light": {"t": 2600.0, "energy": 3.0, "range": 7.5, "shadow": true},
		"haze": {"amount": 8, "size": 0.75, "strength": 0.022},
		"release": {"light": 1.2, "sparks": 12},
		"draw": {"amount": 8, "energy": 3.5},
		"pierce": {"light": 7.0, "sparks": 34, "embers": 26, "smoke": 6, "fireball": 2.4, "jet": 10},
		"end": {"light": 10.0, "t": 2700.0, "range": 15.0, "fireball": 3.4, "sparks": 40, "embers": 40, "smoke": 8, "scorch": 2.6},
		## how the end meets the ground: flames left burning (count, life), embers that settle, how sparks bounce,
		## dust, the smoke's colour, the scorch's size and how long its embers glow, a fire that keeps going
		"surfaces": {
			"grass": {"flames": 9, "flame_life": 2.6, "settle": true, "bounce": 0.15, "friction": 0.9, "smoke_col": Color(0.59, 0.57, 0.55), "smoke": 10, "scorch": 1.25, "glow": 4.0, "ring": true},
			"stone": {"flames": 0, "flame_life": 0.0, "settle": false, "bounce": 0.55, "friction": 0.15, "smoke_col": Color(0.24, 0.22, 0.22), "smoke": 6, "scorch": 0.85, "glow": 0.0, "spark_mul": 1.8, "chips": true},
			"dirt": {"flames": 3, "flame_life": 1.1, "settle": false, "bounce": 0.3, "friction": 0.6, "smoke_col": Color(0.34, 0.31, 0.28), "smoke": 7, "scorch": 1.0, "glow": 1.5, "dust": Color(0.36, 0.3, 0.23)},
			"wood": {"flames": 0, "flame_life": 7.0, "settle": true, "bounce": 0.25, "friction": 0.7, "smoke_col": Color(0.42, 0.39, 0.36), "smoke": 8, "scorch": 1.0, "glow": 8.0, "keep": 7.0},
			"dark": {"flames": 3, "flame_life": 1.2, "settle": false, "bounce": 0.3, "friction": 0.6, "smoke_col": Color(0.28, 0.27, 0.25), "smoke": 7, "scorch": 1.0, "glow": 2.0, "dust": Color(0.12, 0.11, 0.1)},
		},
		## (jj: no sizzle on the draw or the release, only the arrow being loosed: the fuse and the crackle are gone)
		"sounds": {"cast": [], "release": [["fireball", -6.0, 1.08]],
			"pierce": [["impact_flesh", -4.0, 1.0], ["fire_erupt", -9.0, 1.45]], "end": [["boom", -7.0, 1.15], ["fire_erupt", -4.0, 0.9]]},
	},
	## the plain war arrow: no fire; sparks on the hit
	"war": {"model": "war", "sounds": {"pierce": [["impact_flesh", -6.0, 1.0]]}},
	## a run's skills (Blaine's roguelike pass): Glacial Shard flies the Meshy glacier arrow, Storm Shot a war arrow
	## wreathed in lightning (ArcherFx adds their glow), Arrow Storm's rain are war arrows
	"frost": {"model": "frost", "sounds": {"pierce": [["ice_arrow_hit", -5.0, 1.0]]}},
	"storm": {"model": "war", "sounds": {"pierce": [["arc_hit", -6.0, 1.2]]}},
}
static var _lights := 0

static func preset(kind: String) -> Dictionary:
	return PRESETS.get(kind, PRESETS["war"])

## Which ground a point is: a zone may answer itself (meta "surface_fn", the proof range), else the paving and
## earth masks, the grass, indoors.
static func surface(game, p: Vector3) -> String:
	var w = game.world
	if w == null:
		return "dirt"
	if w.has_meta("surface_fn"):
		return str((w.get_meta("surface_fn") as Callable).call(p))
	if game.has_method("indoor") and game.indoor():
		return "stone"
	if w.cobble_at(p.x, p.z) > 0.45:
		return "stone"
	if w.dirt_at(p.x, p.z) > 0.45:
		return "dirt"
	if w.oak_forest and w.grass_ground(p.x, p.z) > 0.35:
		return "grass"
	return "dirt"

# ---------------------------------------------------------------- the projectile
## The burning arrow of this kind, ready to be placed and flown (`fly` every frame). Its state is in metas.
## The flames on the head ride the arrow (local); the trail (wisps, smoke, embers, sparks, haze) is emitted in the
## world from emitters that `fly` keeps on the head, so it stays behind in the air and dies off after the flight.
static func projectile(kind: String, game) -> Node3D:
	var p := preset(kind)
	var root: Node3D = ArrowModel.make(str(p.get("model", "war")), p.has("flame"))
	root.set_meta("kind", kind)
	root.set_meta("age", 0.0)
	if not p.has("flame"):
		return root
	var lite := FlameFx.cheap(game)
	var div := 2 if lite else 1
	if p.has("heat"):
		var hm := ShaderMaterial.new()
		hm.shader = FlameFx.shader("heat")
		hm.set_shader_parameter("heat", float(p["heat"]["head"]))
		hm.set_shader_parameter("char_amt", float(p["heat"]["char"]))
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = hm
	# the flames wrapped round the head, blown back along the shaft
	var f: Dictionary = p["flame"]
	var sz: Array = f["size"]
	var tt: Array = f["t"]
	var fl := FlameFx.flip_particles("flame", int(f["amount"]), float(f["life"]), Vector2(sz[0], sz[1]), 1, float(f["energy"]), Vector2(tt[0], tt[1]))
	fl.local_coords = true
	fl.name = "Flames"
	var fpm := fl.process_material as ParticleProcessMaterial
	fpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fpm.emission_box_extents = Vector3(0.02, 0.02, 0.07)
	fpm.anim_speed_min = 0.35
	fpm.anim_speed_max = 0.55
	fpm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	fpm.scale_curve = FlameFx.curve_tex([[0.0, 0.55], [0.3, 1.0], [1.0, 0.75]])
	fl.position = Vector3(0, 0, -0.5)
	root.add_child(fl)
	var trail: Array = []
	var fx_root: Node3D = game.world.fx_root
	# torn scraps of flame left in the air, rising as they burn out
	if p.has("wisps"):
		var wd: Dictionary = p["wisps"]
		var ws: Array = wd["size"]
		# the flame's tail: torn tongues lying along the flight (axis 2: their velocity), dragged back off the head,
		# overlapping into one tapering tail that burns out within a couple of metres
		var wi := FlameFx.flip_particles("flame", int(wd["amount"]) / div, float(wd["life"]), Vector2(ws[0], ws[1]), 2, float(f["energy"]) * 0.75, Vector2(tt[0], tt[1] * 0.9))
		var wpm := wi.process_material as ParticleProcessMaterial
		wpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		wpm.emission_sphere_radius = 0.03
		wpm.particle_flag_align_y = true
		wpm.direction = Vector3(0, 0, 1)      # set to the flight's back in `fly`
		wpm.spread = 6.0
		wpm.initial_velocity_min = 0.0
		wpm.initial_velocity_max = 9.0
		wpm.gravity = Vector3(0, 1.5, 0)
		wpm.damping_min = 10.0
		wpm.damping_max = 14.0
		wpm.anim_speed_min = 0.06
		wpm.anim_speed_max = 0.12
		wpm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		wpm.scale_curve = FlameFx.curve_tex([[0.0, 1.0], [0.5, 0.6], [1.0, 0.2]])
		wi.name = "Wisps"
		trail.append(wi)
	if p.has("smoke"):
		var sd: Dictionary = p["smoke"]
		var ss: Array = sd["size"]
		var sm := FlameFx.flip_particles("smoke", int(sd["amount"]) / div, float(sd["life"]), Vector2(ss[0], ss[1]))
		var spm := sm.process_material as ParticleProcessMaterial
		spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		spm.emission_sphere_radius = 0.08
		spm.direction = Vector3.UP
		spm.spread = 60.0
		spm.initial_velocity_min = 0.1
		spm.initial_velocity_max = 0.5
		spm.gravity = Vector3(0, 0.45, 0)
		spm.damping_min = 0.5
		spm.damping_max = 1.0
		spm.angle_min = -180.0
		spm.angle_max = 180.0
		spm.angular_velocity_min = -25.0
		spm.angular_velocity_max = 25.0
		spm.anim_offset_max = 0.15
		spm.lifetime_randomness = 0.35
		spm.turbulence_enabled = true
		spm.turbulence_noise_strength = 0.6
		spm.turbulence_noise_scale = 2.0
		spm.turbulence_influence_min = 0.05
		spm.turbulence_influence_max = 0.15
		var sc: Color = sd["col"]
		spm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, float(sd["alpha"])), Color(1, 1, 1, float(sd["alpha"]) * 0.6), Color(1, 1, 1, 0)])
		spm.scale_curve = FlameFx.curve_tex([[0.0, 0.35], [0.35, 0.8], [1.0, 1.25]])
		var smm := sm.material_override as ShaderMaterial
		smm.set_shader_parameter("tint", sc)
		smm.set_shader_parameter("glow", 0.5)
		sm.name = "Smoke"
		trail.append(sm)
	if p.has("embers"):
		var ed: Dictionary = p["embers"]
		var el: Array = ed["life"]
		var et: Array = ed["t"]
		var em := FlameFx.streaks(int(ed["amount"]) / div, Vector2(el[0], el[1]), float(ed["size"]), 1.6, Vector2(et[0], et[1]), 1.0)
		var epm := em.process_material as ParticleProcessMaterial
		epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		epm.emission_sphere_radius = 0.12
		epm.direction = Vector3.UP
		epm.spread = 180.0
		epm.initial_velocity_min = 0.3
		epm.initial_velocity_max = 1.4
		epm.gravity = Vector3(0, 0.35, 0)
		epm.damping_min = 0.6
		epm.damping_max = 1.6
		epm.turbulence_enabled = true
		epm.turbulence_noise_strength = 2.5
		epm.turbulence_noise_scale = 1.4
		epm.turbulence_noise_speed_random = 0.4
		epm.turbulence_influence_min = 0.2
		epm.turbulence_influence_max = 0.5
		em.name = "Embers"
		trail.append(em)
	if p.has("sparks"):
		var kd: Dictionary = p["sparks"]
		var kl: Array = kd["life"]
		var kt: Array = kd["t"]
		var sp := FlameFx.streaks(int(kd["amount"]) / div, Vector2(kl[0], kl[1]), float(kd["size"]), 7.0, Vector2(kt[0], kt[1]), 1.6)
		var kpm := sp.process_material as ParticleProcessMaterial
		kpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		kpm.emission_sphere_radius = 0.05
		kpm.direction = Vector3.UP
		kpm.spread = 180.0
		kpm.initial_velocity_min = float(kd["speed"]) * 0.4
		kpm.initial_velocity_max = float(kd["speed"])
		kpm.gravity = Vector3(0, -6.0, 0)
		kpm.damping_min = 1.0
		kpm.damping_max = 2.0
		sp.name = "Sparks"
		trail.append(sp)
	if p.has("haze") and FlameFx.shimmer_ok() and not lite:
		var hd: Dictionary = p["haze"]
		var hz := FlameFx.haze(int(hd["amount"]), 0.45, float(hd["size"]), float(hd["strength"]))
		hz.name = "Haze"
		trail.append(hz)
	# the arrow covers ~1 m a frame: what it sheds in the air (the torn flame and the smoke) is split over SUBSTEPS
	# emitters that `fly` spreads along the stretch it crossed, so the trail is continuous, not beads a metre apart
	var spread: Array = []
	for e in trail:
		var pe := e as GPUParticles3D
		if str(pe.name) == "Smoke" or str(pe.name) == "Wisps":
			pe.amount = maxi(1, pe.amount / SUBSTEPS)
			for k in SUBSTEPS - 1:
				var c := pe.duplicate() as GPUParticles3D
				c.set_meta("sub", float(k + 1) / SUBSTEPS)
				spread.append(c)
			pe.set_meta("sub", 1.0)
	trail.append_array(spread)
	for e in trail:
		(e as GPUParticles3D).emitting = false    # `fly` starts them once they are on the head
		fx_root.add_child(e)
	root.set_meta("trail", trail)
	if p.has("light") and _lights < LIGHT_CAP:
		var l: Dictionary = p["light"]
		var lt := FlameFx.fire_light(float(l["t"]), float(l["energy"]), float(l["range"]), bool(l["shadow"]) and not lite)
		lt.position = Vector3(0, 0.12, -0.2)
		lt.name = "Light"
		root.add_child(lt)
		_lights += 1
		lt.tree_exited.connect(func(): _lights = maxi(0, _lights - 1))
	return root

## Every frame of the flight (Archer.update, both games): the trail's emitters follow the head (they emit in the
## world, so what they shed stays in the air behind it), the head heats and the shaft chars, the light flickers.
static func fly(a: Dictionary, n: Node3D, delta: float, game) -> void:
	var age: float = float(n.get_meta("age", 0.0)) + delta
	n.set_meta("age", age)
	var pr := preset(str(n.get_meta("kind", "war")))
	if pr.has("ribbon") and game != null:
		_ribbon(a, n, pr["ribbon"], game)
	if not n.has_meta("trail"):
		return
	var head: Vector3 = n.global_transform * Vector3(0, 0, -0.42)
	var prev: Vector3 = n.get_meta("prev_head", head)
	if not n.has_meta("prev_head"):
		# the tongues torn off are thrown back along the flight
		for e in n.get_meta("trail"):
			var pw := e as GPUParticles3D
			if is_instance_valid(pw) and str(pw.name).begins_with("Wisps"):
				(pw.process_material as ParticleProcessMaterial).direction = n.global_transform.basis.z
	n.set_meta("prev_head", head)
	for e in n.get_meta("trail"):
		var pe := e as GPUParticles3D
		if not is_instance_valid(pe):
			continue
		pe.global_position = prev.lerp(head, float(pe.get_meta("sub", 1.0)))
		if not pe.emitting:
			pe.emitting = true
	var t: float = GameClock.now()
	var lt := n.get_node_or_null("Light") as OmniLight3D
	if lt != null:
		lt.light_energy = float(lt.get_meta("base")) * FlameFx.flicker(t, float(n.get_instance_id() % 97)) * smoothstep(0.0, 0.06, age)

## The flame's tail and the smoke behind it: the head's path (a["rpts"]: [position, time], newest first, a point
## every RIBBON_STEP so the ~1 m an arrow covers in a frame is filled in) joined into two camera-facing strips.
## The fire strip is widest a little behind the head and burns out toward the tail; the smoke strip starts behind
## the fire, rises and widens with its age and fades away.
const RIBBON_STEP := 0.1
static func _ribbon(a: Dictionary, n: Node3D, rb: Dictionary, game) -> void:
	var tnow: float = float(n.get_meta("age", 0.0))
	var head: Vector3 = n.global_transform * Vector3(0, 0, -0.3)
	var pts: Array = a.get("rpts", [])
	if pts.is_empty():
		pts.append([head, tnow])
		pts.append([head, tnow])
	else:
		var last: Vector3 = pts[1][0]
		var lt: float = float(pts[1][1])
		var d := last.distance_to(head)
		if d > RIBBON_STEP:
			var k := int(d / RIBBON_STEP)
			for i in range(1, k + 1):
				var f := float(i) / float(k + 1)
				pts.insert(1, [last.lerp(head, f), lerpf(lt, tnow, f)])
		pts[0] = [head, tnow]
	var sl: float = float(rb["smoke_len"])
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += (pts[i][0] as Vector3).distance_to(pts[i - 1][0])
		if acc > sl + 0.5:
			pts.resize(i + 1)
			break
	a["rpts"] = pts
	var fx_root: Node3D = game.world.fx_root
	if not a.has("rfire"):
		a["rfire"] = _ribbon_mesh(fx_root, "ribbon_fire")
		var fm := (a["rfire"] as MeshInstance3D).material_override as ShaderMaterial
		fm.set_shader_parameter("atlas", FlameFx.tex("flame"))
		fm.set_shader_parameter("energy", float(rb["energy"]))
		fm.set_shader_parameter("seed", randf() * 10.0)
		a["rsmoke"] = _ribbon_mesh(fx_root, "ribbon_smoke")
		((a["rsmoke"] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("tint", rb["smoke_col"])
		((a["rsmoke"] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("seed", randf() * 10.0)
	var cam := n.get_viewport().get_camera_3d() if n.is_inside_tree() else null
	var cpos: Vector3 = cam.global_position if cam != null else head + Vector3(0, 10, 10)
	var age: float = float(n.get_meta("age", 0.0))
	# the fire: from the head back `len` metres (it grows out as the arrow leaves the bow)
	var fl: float = minf(float(rb["len"]), 0.3 + age * 12.0)
	_strip(a["rfire"], pts, cpos, tnow, 0.0, fl, float(rb["width"]), false)
	_strip(a["rsmoke"], pts, cpos, tnow, 0.35, sl, float(rb["smoke_width"]), true)

static func _ribbon_mesh(root: Node3D, key: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var m := ShaderMaterial.new()
	m.shader = FlameFx.shader(key)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	root.add_child(mi)
	return mi

## One strip along pts from s0 to s1 metres behind the head: UV.x = 0..1 along (smoke: metres, for its noise),
## UV.y across; COLOR.r = how hot (near the fire), COLOR.a = the fade. Smoke rises and widens with its age.
static func _strip(mi: MeshInstance3D, pts: Array, cpos: Vector3, tnow: float, s0: float, s1: float, w0: float, smoke: bool) -> void:
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	if pts.size() < 3:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var s := 0.0
	var n := 0
	for i in pts.size():
		if i > 0:
			s += (pts[i][0] as Vector3).distance_to(pts[i - 1][0])
		if s < s0:
			continue
		if s > s1:
			break
		var p: Vector3 = pts[i][0]
		var age: float = tnow - float(pts[i][1])
		var nb: Vector3 = pts[mini(i + 1, pts.size() - 1)][0]
		var pa: Vector3 = pts[maxi(i - 1, 0)][0]
		var dir := (nb - pa)
		dir = dir.normalized() if dir.length() > 0.0001 else Vector3.RIGHT
		var u := clampf((s - s0) / maxf(s1 - s0, 0.01), 0.0, 1.0)
		var w: float
		var col: Color
		if smoke:
			# hot gas rises, the puff spreads and thins as it ages
			p += Vector3(0, age * 0.55 + sin(s * 1.7 + tnow * 0.8) * 0.05 * age, 0)
			w = w0 * (0.35 + age * 0.9) * (0.5 + 0.5 * smoothstep(0.0, 0.15, u))
			var fade := smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.7, 1.0, u)) * clampf(1.0 - age / 2.4, 0.0, 1.0)
			col = Color(clampf(1.0 - u * 4.0, 0.0, 1.0), 0, 0, fade)
		else:
			# the flame: lifted a touch as it streams back, a lick of sideways turbulence
			p += Vector3(sin(tnow * 17.0 + s * 3.1) * 0.03 * u, age * 0.9 * u, cos(tnow * 13.0 + s * 2.3) * 0.03 * u)
			w = w0 * (0.3 + 0.7 * smoothstep(0.0, 0.18, u)) * (1.0 - 0.75 * u)
			col = Color(1, 1, 1, 1.0 - smoothstep(0.75, 1.0, u))
		var side := dir.cross((cpos - p).normalized())
		side = side.normalized() if side.length() > 0.0001 else Vector3.UP
		im.surface_set_color(col)
		im.surface_set_uv(Vector2(s - s0 if smoke else u, 0.0))
		im.surface_add_vertex(p - side * w * 0.5)
		im.surface_set_color(col)
		im.surface_set_uv(Vector2(s - s0 if smoke else u, 1.0))
		im.surface_add_vertex(p + side * w * 0.5)
		n += 1
	if n < 2:
		# an empty strip: two degenerate triangles so the surface is valid
		for k in 4:
			im.surface_set_color(Color(0, 0, 0, 0))
			im.surface_set_uv(Vector2.ZERO)
			im.surface_add_vertex(cpos + Vector3(0, -1000, 0))
	im.surface_end()

## The flight is over: the trail stops shedding and is left to burn out and drift away where it lies.
static func end_flight(a: Dictionary) -> void:
	for k in ["rfire", "rsmoke"]:
		var mi := a.get(k) as MeshInstance3D
		if mi != null and is_instance_valid(mi):
			var m := mi.material_override as ShaderMaterial
			var t := 0.2 if k == "rfire" else 1.6
			var tw := mi.create_tween()
			tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, t)
			tw.tween_callback(mi.queue_free)
		a.erase(k)
	var n = a.get("node")
	if n == null or not is_instance_valid(n) or not (n as Node3D).has_meta("trail"):
		return
	for e in (n as Node3D).get_meta("trail"):
		var pe := e as GPUParticles3D
		if is_instance_valid(pe):
			pe.emitting = false
			Fx._free_later(pe, pe.lifetime + 0.3)
	(n as Node3D).remove_meta("trail")

# ---------------------------------------------------------------- the release
## The arrow leaving the bow: its flames whip round with the shot, a few sparks fly off the string, a breath of
## smoke, a pop of light on his hands.
static func release(h: Hero, kind: String, from: Vector3, dir: Vector3) -> void:
	var p := preset(kind)
	if not p.has("release"):
		return
	var r: Dictionary = p["release"]
	var root: Node3D = h.game.world.fx_root
	var lite := FlameFx.cheap(h.game)
	_pop_light(root, from, 2600.0, float(r["light"]), 0.25, 4.0, false)
	var sp := FlameFx.streaks(int(r["sparks"]) / (2 if lite else 1), Vector2(0.15, 0.4), 0.013, 6.0, Vector2(2300, 1100), 1.6)
	var pm := sp.process_material as ParticleProcessMaterial
	pm.direction = dir + Vector3(0, 0.3, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -7.0, 0)
	_one_shot(root, sp, from, 0.6)
	var sm := FlameFx.flip_particles("smoke", 2 if lite else 3, 1.2, Vector2(0.3, 0.55))
	var spm := sm.process_material as ParticleProcessMaterial
	spm.direction = -dir + Vector3(0, 0.6, 0)
	spm.spread = 30.0
	spm.initial_velocity_min = 0.3
	spm.initial_velocity_max = 0.8
	spm.gravity = Vector3(0, 0.4, 0)
	spm.angle_max = 360.0
	spm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	spm.scale_curve = FlameFx.curve_tex([[0.0, 0.5], [1.0, 1.3]])
	(sm.material_override as ShaderMaterial).set_shader_parameter("tint", Color(0.16, 0.15, 0.14))
	_one_shot(root, sm, from, 1.4)
	_sounds(h, p, "release")
	SkillFx.shake(h, 0.08)

# ---------------------------------------------------------------- the draw
## The nocked arrow burning in his hands while he draws (ArcherFx.update, every frame of the shot, on the puppet too):
## the pitch on the head catches and grows with the draw (`k` 0..1), the flames standing up from it, the light on
## his hands and face rising. Cleared at the release.
static func draw_charge(h: Hero, kind: String, k: float) -> void:
	var w: Node3D = h.weapon_node
	if w == null or not is_instance_valid(w) or not w.has_meta("nocked"):
		return
	var p := preset(kind)
	if not p.has("draw"):
		return
	var d: Dictionary = p["draw"]
	var arrow: Node3D = w.get_meta("nocked")
	var ch := arrow.get_node_or_null("Charge") as Node3D
	if ch == null:
		ch = Node3D.new()
		ch.name = "Charge"
		arrow.add_child(ch)
		# the nocked arrow's head (the bow's own arrow mesh: its head toward -z)
		ch.position = Vector3(0, 0, -0.36)
		var fl := FlameFx.flip_particles("flame", int(d["amount"]), 0.45, Vector2(0.16, 0.3), 0, float(d["energy"]), Vector2(1000, 2300))
		fl.local_coords = true      # it rides the arrow as he raises the bow (the cards still stand up the world)
		var pm := fl.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.03
		pm.anim_speed_min = 0.4
		pm.anim_speed_max = 0.6
		pm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		fl.name = "Flames"
		ch.add_child(fl)
		var em := FlameFx.streaks(6 if FlameFx.cheap(h.game) else 12, Vector2(0.5, 1.0), 0.02, 1.5, Vector2(1800, 900))
		var epm := em.process_material as ParticleProcessMaterial
		epm.direction = Vector3.UP
		epm.spread = 40.0
		epm.initial_velocity_min = 0.3
		epm.initial_velocity_max = 0.9
		epm.gravity = Vector3(0, 0.6, 0)
		epm.turbulence_enabled = true
		epm.turbulence_noise_strength = 2.0
		epm.turbulence_influence_min = 0.2
		epm.turbulence_influence_max = 0.4
		em.name = "Embers"
		ch.add_child(em)
		var lt := FlameFx.fire_light(2500.0, 0.7, 2.6, false)
		lt.position = Vector3(0, 0.15, -0.1)
		lt.name = "Light"
		ch.add_child(lt)
	var kk := clampf(k, 0.0, 1.0)
	var fl2 := ch.get_node("Flames") as GPUParticles3D
	fl2.amount_ratio = 0.35 + 0.65 * kk
	fl2.scale = Vector3.ONE    # (the particles scale themselves; the node stays unscaled)
	(fl2.material_override as ShaderMaterial).set_shader_parameter("alpha_mul", 0.4 + 0.6 * kk)
	(ch.get_node("Light") as OmniLight3D).light_energy = 0.7 * (0.35 + 0.65 * kk) * FlameFx.flicker(GameClock.now(), 3.0)
	ch.visible = arrow.visible

static func end_draw(h: Hero) -> void:
	var w: Node3D = h.weapon_node
	if w == null or not is_instance_valid(w) or not w.has_meta("nocked"):
		return
	var ch := (w.get_meta("nocked") as Node3D).get_node_or_null("Charge")
	if ch != null:
		ch.queue_free()

# ---------------------------------------------------------------- a foe pierced
## The arrow goes through: sparks and a splash of burning pitch where it enters, a gout of fire out of his back
## along the arrow's line rolling up into smoke, embers, a pop of light on him and round him.
static func pierce(h: Hero, kind: String, e: Node3D, dir: Vector3) -> void:
	var p := preset(kind)
	var root: Node3D = h.game.world.fx_root
	var at: Vector3 = e.global_position + Vector3(0, 0.9 * float(e.get("height")), 0)
	if not p.has("pierce"):
		Fx.sparks(root, at, Color(0.9, 0.85, 0.7))
		_sounds(h, p, "pierce", at)
		return
	var pc: Dictionary = p["pierce"]
	var lite := FlameFx.cheap(h.game)
	var div := 2 if lite else 1
	var r: float = float(e.get("radius"))
	var entry := at - dir * (r + 0.05)
	var exit := at + dir * (r + 0.1)
	_pop_light(root, at, 2700.0, float(pc["light"]), 0.4, 6.0, false)
	# the gout out of his back: the sim's fireball thrown along the line, and a jet of flame torn out of the wound
	# ahead of it (the flame sim's tongues flying along the arrow's line, stretched by their speed)
	_fireball(root, exit + dir * 0.45, float(pc["fireball"]), 1.05, dir * 3.0, not lite, not lite)
	var jt := FlameFx.flip_particles("flame", int(pc.get("jet", 0)) / div, 0.26, Vector2(0.7, 1.3), 2, 4.2, Vector2(1300, 2900))
	var jpm := jt.process_material as ParticleProcessMaterial
	jpm.particle_flag_align_y = true
	jpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	jpm.emission_sphere_radius = 0.12
	jpm.direction = dir + Vector3(0, 0.12, 0)
	jpm.spread = 16.0
	jpm.initial_velocity_min = 3.0
	jpm.initial_velocity_max = 6.0
	jpm.damping_min = 3.0
	jpm.damping_max = 5.0
	# one tearing tongue, not a spray of chunks: each card swells out of the wound and is gone before it flies clear
	jpm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	jpm.scale_curve = FlameFx.curve_tex([[0.0, 0.6], [0.3, 1.0], [1.0, 0.45]])
	jt.explosiveness = 0.9
	_one_shot(root, jt, exit, 0.6)
	# sparks out of the entry, back along the line, and out of the exit, forward
	var sp := FlameFx.streaks(int(pc["sparks"]) / div, Vector2(0.2, 0.55), 0.011, 7.0, Vector2(2400, 1100), 1.8)
	var pm := sp.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = dir + Vector3(0, 0.25, 0)
	pm.spread = 28.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	_one_shot(root, sp, exit, 0.8)
	var sp2 := FlameFx.streaks(int(pc["sparks"]) / (2 * div), Vector2(0.1, 0.3), 0.012, 5.0, Vector2(2200, 1100), 1.5)
	var pm2 := sp2.process_material as ParticleProcessMaterial
	pm2.direction = -dir + Vector3(0, 0.4, 0)
	pm2.spread = 50.0
	pm2.initial_velocity_min = 1.5
	pm2.initial_velocity_max = 4.0
	pm2.gravity = Vector3(0, -9.0, 0)
	_one_shot(root, sp2, entry, 0.5)
	var em := FlameFx.streaks(int(pc["embers"]) / div, Vector2(0.6, 1.4), 0.018, 1.6, Vector2(1900, 850))
	var epm := em.process_material as ParticleProcessMaterial
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	epm.emission_sphere_radius = 0.2
	epm.direction = dir + Vector3(0, 0.6, 0)
	epm.spread = 50.0
	epm.initial_velocity_min = 1.0
	epm.initial_velocity_max = 3.5
	epm.gravity = Vector3(0, 0.3, 0)
	epm.damping_min = 1.5
	epm.damping_max = 3.0
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 2.5
	epm.turbulence_influence_min = 0.2
	epm.turbulence_influence_max = 0.5
	_one_shot(root, em, exit, 1.6)
	_smoke_puffs(root, exit + Vector3(0, 0.2, 0), int(pc["smoke"]) / div, Color(0.3, 0.28, 0.27), 0.35, 2.0, Vector2(0.5, 1.0), dir * 0.6)
	_sounds(h, p, "pierce", at)
	SkillFx.hitstop(h, 0.03)

# ---------------------------------------------------------------- the end of the flight
## Where the flight ends (its range run out, or a wall): the pitch bursts into a fireball (the sim: fire swelling
## open and rolling up into smoke), its light flashing over the ground and the foes and dying down to the fire left
## burning; sparks and embers flung out and falling, smoke rising, and the ground answering in its own way.
static func finish(h: Hero, kind: String, pos: Vector3, dir: Vector3, wall: bool) -> void:
	var p := preset(kind)
	if not p.has("end"):
		return
	var en: Dictionary = p["end"]
	var root: Node3D = h.game.world.fx_root
	var gy: float = h.game.world.height_at(pos.x, pos.z)
	var g := Vector3(pos.x, gy, pos.z)
	var lite := FlameFx.cheap(h.game)
	var div := 2 if lite else 1
	var surf := surface(h.game, g)
	var sf: Dictionary = (p.get("surfaces", {}) as Dictionary).get(surf, {})
	# the arrow drives into the ground short of where it would have flown on: the fire bursts there, low
	var at := g + Vector3(0, 0.25, 0) - dir * 0.2
	# the light: a flash with shadows, dying down to the glow of what is left burning
	var keep: float = float(sf.get("flame_life", 1.0))
	var lt := FlameFx.fire_light(float(en["t"]), float(en["light"]), float(en.get("range", 11.0)), not lite)
	root.add_child(lt)
	lt.global_position = at + Vector3(0, 0.9, 0)
	var seed_v := randf() * 50.0
	var start := GameClock.now()
	var base: float = float(en["light"])
	var tl := lt.create_tween()
	tl.tween_method(func(v: float):
		var tnow := GameClock.now()
		var age := tnow - start
		var flash := exp(-age * 5.0)
		var glow := 0.3 * clampf(1.0 - (age - 0.3) / maxf(keep + 0.6, 0.3), 0.0, 1.0)
		lt.light_energy = base * (flash + glow) * FlameFx.flicker(tnow, seed_v)
		lt.light_color = FlameFx.blackbody(lerpf(float(en["t"]) + 300.0, float(en["t"]) - 350.0, clampf(age / 1.2, 0.0, 1.0))), 0.0, 1.0, keep + 1.2)
	tl.tween_callback(lt.queue_free)
	_fireball(root, at, float(en["fireball"]), 1.6, Vector3(0, 0.8, 0), not lite, true)
	# sparks: flung out and up, falling, bouncing or skittering on the ground by what it is
	var spark_n: int = int(float(en["sparks"]) * float(sf.get("spark_mul", 1.0))) / div
	var sp := FlameFx.streaks(spark_n, Vector2(0.4, 1.3), 0.011, 6.0, Vector2(2400, 1000), 1.8)
	var pm := sp.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3(dir.x * 0.5, 1.0, dir.z * 0.5)
	pm.spread = 75.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 8.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.2
	pm.damping_max = 1.0
	_collide(pm, float(sf.get("bounce", 0.3)), float(sf.get("friction", 0.5)), 0.01)
	var sp_node := _one_shot(root, sp, at, 1.6)
	_ground_collider(sp_node, g)
	# embers: drifting up on the heat and floating down; on grass and wood they settle and glow on the ground
	var em := FlameFx.streaks(int(en["embers"]) / div, Vector2(1.0, 2.6 if sf.get("settle", false) else 1.8), 0.018, 1.4, Vector2(1900, 800))
	var epm := em.process_material as ParticleProcessMaterial
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	epm.emission_sphere_radius = 0.4
	epm.direction = Vector3.UP
	epm.spread = 70.0
	epm.initial_velocity_min = 1.0
	epm.initial_velocity_max = 4.0
	epm.gravity = Vector3(0, -1.6 if sf.get("settle", false) else 0.2, 0)
	epm.damping_min = 1.0
	epm.damping_max = 2.5
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 2.5
	epm.turbulence_noise_scale = 1.6
	epm.turbulence_influence_min = 0.15
	epm.turbulence_influence_max = 0.45
	if sf.get("settle", false):
		_collide(epm, 0.0, 1.0, 0.012)
	var em_node := _one_shot(root, em, at, 3.0)
	if sf.get("settle", false):
		_ground_collider(em_node, g)
	# smoke rolling up and drifting off, its colour from what burns
	_smoke_puffs(root, at + Vector3(0, 0.4, 0), int(sf.get("smoke", en["smoke"])) / div, sf.get("smoke_col", Color(0.13, 0.12, 0.11)), 0.55, 3.6, Vector2(0.9, 2.0), Vector3(0, 0.5, 0))
	# dust thrown up from dry ground, low and spreading
	if sf.has("dust"):
		var dust := FlameFx.flip_particles("smoke", 6 / div, 1.6, Vector2(0.8, 1.6))
		var dpm := dust.process_material as ParticleProcessMaterial
		dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		dpm.emission_ring_axis = Vector3.UP
		dpm.emission_ring_radius = 0.6
		dpm.emission_ring_inner_radius = 0.2
		dpm.emission_ring_height = 0.1
		dpm.direction = Vector3(0, 0.25, 0)
		dpm.spread = 180.0
		dpm.flatness = 0.8
		dpm.radial_velocity_min = 1.5
		dpm.radial_velocity_max = 3.5
		dpm.gravity = Vector3(0, -0.3, 0)
		dpm.damping_min = 2.0
		dpm.damping_max = 3.0
		dpm.angle_max = 360.0
		dpm.anim_offset_max = 0.2
		dpm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		dpm.scale_curve = FlameFx.curve_tex([[0.0, 0.5], [1.0, 1.4]])
		(dust.material_override as ShaderMaterial).set_shader_parameter("tint", sf["dust"])
		_one_shot(root, dust, g + Vector3(0, 0.15, 0), 2.0)
	if sf.get("chips", false) and not lite:
		Fx._slam_chunks(root, g)
	# flames left on the ground (grass smoulders in a ring, wood catches, dirt burns out at once, stone not at all)
	var nfl: int = int(sf.get("flames", 0)) / div
	if nfl > 0:
		var gf := FlameFx.flip_particles("flame", nfl, float(sf.get("flame_life", 1.0)), Vector2(0.45, 1.0), 0, 3.5, Vector2(950, 2200))
		var gpm := gf.process_material as ParticleProcessMaterial
		gpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING if sf.get("ring", false) else ParticleProcessMaterial.EMISSION_SHAPE_BOX
		gpm.emission_ring_axis = Vector3.UP
		gpm.emission_ring_radius = 1.1
		gpm.emission_ring_inner_radius = 0.3
		gpm.emission_ring_height = 0.0
		gpm.emission_box_extents = Vector3(0.45, 0.0, 0.45)
		gpm.anim_speed_min = 0.25 * float(sf.get("flame_life", 1.0))
		gpm.anim_speed_max = 0.4 * float(sf.get("flame_life", 1.0))
		gpm.lifetime_randomness = 0.5
		gpm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		gpm.scale_curve = FlameFx.curve_tex([[0.0, 0.4], [0.2, 1.0], [1.0, 0.25]])
		gf.explosiveness = 0.85
		var gfn := _one_shot(root, gf, Vector3(g.x, g.y + 0.02, g.z), float(sf.get("flame_life", 1.0)) + 0.4)
		gfn.global_position = Vector3(g.x, g.y - 0.05, g.z)
	# wood catches: the planks burn on along their grain where the arrow struck, low flames and a glowing char
	if float(sf.get("keep", 0.0)) > 0.0:
		var grain: Vector3 = h.game.world.get_meta("wood_grain") if h.game.world.has_meta("wood_grain") else Vector3(-dir.z, 0, dir.x)
		_plank_burn(root, g + dir * 0.2, grain, float(sf["keep"]), lite)
	# the smoke column: what is left burning goes on smoking, a plume rising well above it
	_smoke_column(root, g + Vector3(0, 0.3, 0), sf.get("smoke_col", Color(0.3, 0.28, 0.27)), maxf(keep, 1.2) + (1.5 if float(sf.get("keep", 0.0)) > 0.0 else 0.5), lite)
	# the burn mark: soot, a blistered normal, ember cracks cooling
	_scorch(h.game, root, g, dir, float(en["scorch"]) * float(sf.get("scorch", 1.0)), float(sf.get("glow", 1.0)))
	# the heat bending the air over it
	if FlameFx.shimmer_ok() and not lite:
		var hz := FlameFx.haze(5, 1.1, 1.6, 0.024)
		var hpm := hz.process_material as ParticleProcessMaterial
		hpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		hpm.emission_sphere_radius = 0.5
		hpm.gravity = Vector3(0, 1.4, 0)
		hz.explosiveness = 0.6
		_one_shot(root, hz, at + Vector3(0, 0.5, 0), 1.4)
	GrassField.impulse(g, 2.8 if surf == "grass" else 2.2, 0.9 if surf == "grass" else 0.6, 0.5)
	_sounds(h, p, "end", at)
	SkillFx.shake(h, 0.14 if wall else 0.1)

## The sim's fireball: the fire layer (additive, its own temperature) over the smoke layer (lit by the scene),
## played once over `life` seconds, `size` metres across, drifting by `drift` m/s; with `second`, a smaller
## mirrored one a beat later so the shape is never the same twice.
static func _fireball(root: Node3D, at: Vector3, size: float, life: float, drift: Vector3, smoke: bool, second: bool) -> void:
	if FlameFx.tex("burst_fire") == null:
		return
	smoke = smoke and FlameFx.tex("burst_smoke") != null
	# several instances of the sim, each turned, mirrored, scaled and started a beat apart, so the burst has depth
	# and is never one card: the main body, a second lobe off to one side, a third rolling up behind
	var lobes: Array = [[1.0, Vector3.ZERO, 0.0, 0.0], [0.72, Vector3(0.35, 0.15, 0.2), 0.06, 0.5], [0.6, Vector3(-0.3, 0.35, -0.25), 0.11, -0.6]]
	for k in (lobes.size() if second else 1):
		var lb: Array = lobes[k]
		var sz: float = size * float(lb[0]) * randf_range(0.92, 1.08)
		var off: Vector3 = (lb[1] as Vector3) * size * 0.45
		var delay: float = float(lb[2])
		var spin: float = float(lb[3]) + randf_range(-0.25, 0.25)
		var flip := randf() < 0.5
		if smoke:
			# the smoke comes through the flame a beat later (the first instant of a fireball is all fire), fading in
			# rather than standing there as a lit cloud
			var sq := _flip_card("burst_smoke", sz * 1.1, flip)
			var sm := sq.material_override as ShaderMaterial
			sm.set_shader_parameter("tint", Color(0.3, 0.285, 0.27))
			sm.set_shader_parameter("density", 0.9)
			sm.set_shader_parameter("glow", 0.9)
			root.add_child(sq)
			sq.global_position = at + off
			_play_card(sq, life * 1.6, delay + 0.07, drift * 0.6)
			var sfade := sq.create_tween()
			sm.set_shader_parameter("density", 0.0)
			sfade.tween_method(func(v: float): sm.set_shader_parameter("density", v), 0.0, 0.9, 0.22).set_delay(delay + 0.07)
		var fq := _flip_card("burst_fire", sz, flip)
		var fm := fq.material_override as ShaderMaterial
		fm.set_shader_parameter("energy", 0.6 if k == 0 else 0.45)
		fm.set_shader_parameter("spin", spin)
		fm.set_shader_parameter("detail", 1.0)
		fm.render_priority = 1      # the fire over its own smoke
		fm.set_shader_parameter("t_lo", 950.0)
		fm.set_shader_parameter("t_hi", 2200.0)
		root.add_child(fq)
		fq.global_position = at + off
		# the fire is the sim's first ~20 frames (the fuel flashes and burns out); played slower than the smoke, so
		# the flash swells and tears open over half a second while its smoke goes on rolling up
		_play_card(fq, life * 0.45, delay, drift * 0.4, 22.0)
	# tongues of flame thrown out of the burst as it opens (the flame loop's licking fire, short-lived; the big
	# burst only: on a small one they read as separate candles)
	if second and size > 2.5:
		var tg := FlameFx.flip_particles("flame", 14, 0.55, Vector2(size * 0.3, size * 0.55), 0, 3.0, Vector2(1000, 2300))
		var tpm := tg.process_material as ParticleProcessMaterial
		tpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		tpm.emission_sphere_radius = size * 0.18
		tpm.direction = Vector3.UP
		tpm.spread = 80.0
		tpm.initial_velocity_min = 1.0
		tpm.initial_velocity_max = 3.0
		tpm.damping_min = 3.0
		tpm.damping_max = 5.0
		tpm.anim_speed_min = 0.5
		tpm.anim_speed_max = 0.8
		tpm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
		tpm.scale_curve = FlameFx.curve_tex([[0.0, 0.6], [0.3, 1.0], [1.0, 0.5]])
		tg.explosiveness = 0.85
		_one_shot(root, tg, at - Vector3(0, size * 0.1, 0), 0.8)
	# the white-hot core: the first instant of the burst, hotter than anything after, gone in a fifth of a second:
	# a small knot of the burst's fire carved fine, and the flame sim's tongues spat out of it in a star
	var cq := _flip_card("burst_fire", size * 0.34, randf() < 0.5)
	var cm := cq.material_override as ShaderMaterial
	cm.set_shader_parameter("energy", 1.0)
	cm.set_shader_parameter("t_lo", 1900.0)
	cm.set_shader_parameter("t_hi", 3900.0)
	cm.set_shader_parameter("detail", 1.0)
	cm.set_shader_parameter("erode_from", 1.0)
	cm.set_shader_parameter("erode_span", 9.0)
	cm.render_priority = 2
	root.add_child(cq)
	cq.global_position = at
	var ctw := cq.create_tween().set_parallel(true)
	ctw.tween_method(func(v: float): cm.set_shader_parameter("frame", v), 2.0, 10.0, 0.2)
	ctw.tween_method(func(v: float): cm.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.2).set_ease(Tween.EASE_IN)
	Fx._free_later(cq, 0.25)
	if FlameFx.tex("flame") != null:
		var nt := 7 if second else 5
		var a0 := randf() * TAU
		for i in nt:
			var tq := _flip_card("flame", size * randf_range(0.22, 0.34), randf() < 0.5)
			var tm := tq.material_override as ShaderMaterial
			tm.set_shader_parameter("loop_anim", 1.0)
			tm.set_shader_parameter("energy", 3.2)
			tm.set_shader_parameter("t_lo", 1500.0)
			tm.set_shader_parameter("t_hi", 3400.0)
			tm.set_shader_parameter("spin", a0 + TAU * (float(i) + randf_range(-0.3, 0.3)) / float(nt))
			tm.set_shader_parameter("frame", randf() * 64.0)
			tm.render_priority = 2
			root.add_child(tq)
			tq.global_position = at
			var f0: float = randf() * 64.0
			var ttw := tq.create_tween().set_parallel(true)
			ttw.tween_method(func(v: float): tm.set_shader_parameter("frame", v), f0, f0 + 6.0, 0.24)
			ttw.tween_property(tq, "scale", tq.scale * 1.7, 0.24).set_ease(Tween.EASE_OUT)
			ttw.tween_method(func(v: float): tm.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.24).set_ease(Tween.EASE_IN)
			Fx._free_later(tq, 0.3)

## One camera-facing card of a sim sequence (a MeshInstance3D, its frame set by `_play_card`).
static func _flip_card(key: String, size: float, flip: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	mi.scale = Vector3.ONE * size
	var fire := key == "flame" or key == "burst_fire"
	var m := ShaderMaterial.new()
	m.shader = FlameFx.shader("fire" if fire else "smoke")
	m.set_shader_parameter("atlas", FlameFx.tex(key))
	m.set_shader_parameter("pivot", float(FlameFx.PIVOT.get(key, 0.0)))
	m.set_shader_parameter("loop_anim", 0.0)
	m.set_shader_parameter("flip", 1.0 if flip else 0.0)
	m.set_shader_parameter("frame", 0.0)
	m.set_shader_parameter("particles", 0.0)
	if fire:
		m.set_shader_parameter("axis_mode", 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	return mi

static func _play_card(mi: MeshInstance3D, life: float, delay: float, drift: Vector3, last := 63.0) -> void:
	var m := mi.material_override as ShaderMaterial
	mi.visible = delay <= 0.0
	var tw := mi.create_tween().set_parallel(true)
	if delay > 0.0:
		tw.tween_callback(func(): mi.visible = true).set_delay(delay)
	# the sim's first frames are the gout still round as it leaves the emitter: start once it has burst open
	tw.tween_method(func(v: float): m.set_shader_parameter("frame", v), BURST_START, last, life).set_delay(delay)
	tw.tween_property(mi, "global_position", mi.global_position + drift * life, life).set_delay(delay).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, life * 0.25).set_delay(delay + life * 0.75)
	Fx._free_later(mi, delay + life + 0.05)

## A few puffs of smoke (the sim's), lit by the scene, rising and spreading.
static func _smoke_puffs(root: Node3D, at: Vector3, n: int, col: Color, alpha: float, life: float, size: Vector2, push: Vector3) -> void:
	if n <= 0:
		return
	var sm := FlameFx.flip_particles("smoke", n, life, size)
	var pm := sm.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = (Vector3.UP + push).normalized()
	pm.spread = 35.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.35, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.angle_max = 360.0
	pm.angular_velocity_min = -18.0
	pm.angular_velocity_max = 18.0
	pm.lifetime_randomness = 0.3
	pm.anim_offset_max = 0.1
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.1
	pm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, alpha), Color(1, 1, 1, alpha * 0.55), Color(1, 1, 1, 0)])
	pm.scale_curve = FlameFx.curve_tex([[0.0, 0.45], [0.4, 0.85], [1.0, 1.3]])
	sm.explosiveness = 0.75
	(sm.material_override as ShaderMaterial).set_shader_parameter("tint", col)
	(sm.material_override as ShaderMaterial).set_shader_parameter("glow", 0.7)
	_one_shot(root, sm, at, life + 0.3)

## A plume of smoke rising from what burns (finish): puffs leaving for `secs`, rising fast and spreading out above.
static func _smoke_column(root: Node3D, at: Vector3, col: Color, secs: float, lite: bool) -> void:
	var sm := FlameFx.flip_particles("smoke", 12 if lite else 24, 4.0, Vector2(1.1, 2.2))
	var pm := sm.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 1.7
	pm.gravity = Vector3(0.12, 0.25, 0.05)
	pm.damping_min = 0.15
	pm.damping_max = 0.35
	pm.angle_max = 360.0
	pm.angular_velocity_min = -15.0
	pm.angular_velocity_max = 15.0
	pm.anim_offset_max = 0.15
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.08
	pm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0)])
	pm.scale_curve = FlameFx.curve_tex([[0.0, 0.4], [0.5, 1.0], [1.0, 1.8]])
	var m := sm.material_override as ShaderMaterial
	m.set_shader_parameter("tint", Color(col.r * 1.25, col.g * 1.25, col.b * 1.25))
	m.set_shader_parameter("glow", 1.0)
	root.add_child(sm)
	sm.global_position = at
	sm.emitting = true
	var tw := sm.create_tween()
	tw.tween_interval(secs)
	tw.tween_callback(func(): sm.emitting = false)
	Fx._free_later(sm, secs + 4.0)

## Wood catching: low flames creeping along the planks' grain where the arrow struck (a line of fire along `grain`,
## not a campfire on top), the flames fewer and lower as it burns down over `secs`, embers, a breathing light.
static func _plank_burn(root: Node3D, at: Vector3, grain: Vector3, secs: float, lite: bool) -> void:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = at
	var gv := grain.normalized() if grain.length() > 0.001 else Vector3.FORWARD
	n.basis = Basis(gv.cross(Vector3.UP).normalized(), Vector3.UP, gv)
	var fl := FlameFx.flip_particles("flame", 8 if lite else 16, 0.8, Vector2(0.4, 0.75), 0, 3.6, Vector2(950, 2150))
	var pm := fl.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.1, 0.0, 0.8)     # along the plank (the node's z is the grain)
	pm.anim_speed_min = 0.3
	pm.anim_speed_max = 0.5
	pm.lifetime_randomness = 0.4
	pm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	pm.scale_curve = FlameFx.curve_tex([[0.0, 0.5], [0.25, 1.0], [1.0, 0.4]])
	(fl.material_override as ShaderMaterial).set_shader_parameter("soft", 0.05)
	n.add_child(fl)
	var em := FlameFx.streaks(6 if lite else 12, Vector2(0.8, 1.8), 0.016, 1.4, Vector2(1700, 800))
	var epm := em.process_material as ParticleProcessMaterial
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	epm.emission_box_extents = Vector3(0.1, 0.0, 0.8)
	epm.direction = Vector3.UP
	epm.spread = 25.0
	epm.initial_velocity_min = 0.4
	epm.initial_velocity_max = 1.2
	epm.gravity = Vector3(0, 0.4, 0)
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 2.0
	epm.turbulence_influence_min = 0.15
	epm.turbulence_influence_max = 0.35
	n.add_child(em)
	var lt := FlameFx.fire_light(2400.0, 1.6, 5.0, false)
	lt.position = Vector3(0, 0.35, 0)
	n.add_child(lt)
	var start := GameClock.now()
	var tw := n.create_tween()
	tw.tween_method(func(_v: float):
		var tnow := GameClock.now()
		var k := clampf((secs - (tnow - start)) / (secs * 0.6), 0.0, 1.0)
		lt.light_energy = 1.6 * FlameFx.flicker(tnow, 5.0) * k
		fl.amount_ratio = maxf(0.15, k)
		pm.emission_box_extents = Vector3(0.1, 0.0, 0.35 + 0.45 * k), 0.0, 1.0, secs)
	tw.tween_callback(func():
		fl.emitting = false
		em.emitting = false)
	Fx._free_later(n, secs + 2.5)

## Wood catches: a little fire burning on where it struck for `secs`, its light breathing, smoke going up.
static func _keep_burning(_game, root: Node3D, at: Vector3, secs: float, lite: bool) -> void:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = at
	var fl := FlameFx.flip_particles("flame", 4 if lite else 7, 0.9, Vector2(0.5, 0.95), 0, 3.5, Vector2(950, 2200))
	var pm := fl.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.18, 0.02, 0.12)
	pm.anim_speed_min = 0.3
	pm.anim_speed_max = 0.45
	pm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	pm.scale_curve = FlameFx.curve_tex([[0.0, 0.5], [0.25, 1.0], [1.0, 0.6]])
	n.add_child(fl)
	var sm := FlameFx.flip_particles("smoke", 3 if lite else 6, 2.4, Vector2(0.45, 1.0))
	var spm := sm.process_material as ParticleProcessMaterial
	spm.direction = Vector3.UP
	spm.spread = 12.0
	spm.initial_velocity_min = 0.5
	spm.initial_velocity_max = 0.9
	spm.gravity = Vector3(0.15, 0.25, 0)
	spm.angle_max = 360.0
	spm.color_ramp = FlameFx.ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0)])
	spm.scale_curve = FlameFx.curve_tex([[0.0, 0.4], [1.0, 1.5]])
	(sm.material_override as ShaderMaterial).set_shader_parameter("tint", Color(0.17, 0.16, 0.15))
	sm.position = Vector3(0, 0.45, 0)
	n.add_child(sm)
	var em := FlameFx.streaks(6 if lite else 10, Vector2(0.8, 1.8), 0.022, 1.4, Vector2(1800, 850))
	var epm := em.process_material as ParticleProcessMaterial
	epm.direction = Vector3.UP
	epm.spread = 25.0
	epm.initial_velocity_min = 0.6
	epm.initial_velocity_max = 1.6
	epm.gravity = Vector3(0, 0.5, 0)
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 2.0
	epm.turbulence_influence_min = 0.15
	epm.turbulence_influence_max = 0.35
	em.position = Vector3(0, 0.2, 0)
	n.add_child(em)
	var lt := FlameFx.fire_light(2500.0, 1.4, 4.5, false)
	lt.position = Vector3(0, 0.45, 0)
	n.add_child(lt)
	var start := GameClock.now()
	var tw := n.create_tween()
	tw.tween_method(func(v: float):
		var tnow := GameClock.now()
		var left := secs - (tnow - start)
		var k := clampf(left / 1.5, 0.0, 1.0)
		lt.light_energy = 1.1 * FlameFx.flicker(tnow, 7.0) * k
		fl.amount_ratio = maxf(0.2, k), 0.0, 1.0, secs)
	tw.tween_callback(func():
		fl.emitting = false
		em.emitting = false
		sm.emitting = false)
	Fx._free_later(n, secs + 2.8)

## The burn mark: a Decal (Forward+ / Mobile) projected on whatever is there (ground, grass, planks): soot, a
## blistered char normal, and ember cracks (`glow` seconds to cool from orange to dark). Compatibility: a lit quad.
static func _scorch(_game, root: Node3D, g: Vector3, dir: Vector3, size: float, glow: float) -> void:
	var alb := FlameFx.tex("scorch")
	if alb == null:
		return
	var yaw := atan2(-dir.z, dir.x) + randf_range(-0.4, 0.4)
	if FlameFx.rd_ok():
		var d := Decal.new()
		d.size = Vector3(size * 1.25, 0.6, size)
		d.texture_albedo = alb
		d.texture_normal = FlameFx.tex("scorch_n")
		d.texture_emission = FlameFx.tex("scorch_e") if glow > 0.0 else null
		d.emission_energy = 0.0
		d.albedo_mix = 1.0
		d.normal_fade = 0.3
		d.upper_fade = 0.4
		d.lower_fade = 0.4
		d.cull_mask = 1
		root.add_child(d)
		d.global_position = g + Vector3(0, 0.1, 0)
		d.rotation.y = yaw
		var tw := d.create_tween().set_parallel(true)
		if glow > 0.0:
			# the cracks cool: bright at once, fading over `glow` seconds
			tw.tween_method(func(v: float): d.emission_energy = 5.0 * v * v, 1.0, 0.0, glow).set_ease(Tween.EASE_OUT)
		tw.tween_property(d, "albedo_mix", 0.0, 4.0).set_delay(maxf(glow, 1.5) + 4.0)
		Fx._free_later(d, maxf(glow, 1.5) + 8.2)
		return
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size * 1.25, size)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = FlameFx.shader("scorch")
	m.set_shader_parameter("tex", alb)
	m.set_shader_parameter("ntex", FlameFx.tex("scorch_n"))
	m.set_shader_parameter("etex", FlameFx.tex("scorch_e"))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = Vector3(g.x, g.y + 0.04, g.z)
	mi.rotation.y = yaw
	var tw2 := mi.create_tween().set_parallel(true)
	tw2.tween_method(func(v: float): m.set_shader_parameter("glow", v), 1.0 if glow > 0.0 else 0.0, 0.0, maxf(glow, 0.1))
	tw2.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 4.0).set_delay(maxf(glow, 1.5) + 4.0)
	Fx._free_later(mi, maxf(glow, 1.5) + 8.2)

## kept for callers of the old API: a burn mark along dir
static func scorch(game, g: Vector3, dir: Vector3, length: float, _width: float) -> void:
	_scorch(game, game.world.fx_root, g, dir, length, 1.5)

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
## A one-shot burst of these particles at pos, freed after `secs`.
static func _one_shot(root: Node3D, p: GPUParticles3D, pos: Vector3, secs: float) -> GPUParticles3D:
	p.one_shot = true
	if p.explosiveness <= 0.0:
		p.explosiveness = 0.92
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	Fx._free_later(p, secs + p.lifetime)
	return p

static func _pop_light(root: Node3D, pos: Vector3, t: float, energy: float, dur: float, rng: float, shadow: bool) -> void:
	var lt := FlameFx.fire_light(t, energy, rng, shadow)
	root.add_child(lt)
	lt.global_position = pos + Vector3(0, 0.3, 0)
	var tw := lt.create_tween()
	tw.tween_property(lt, "light_energy", 0.0, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(lt.queue_free)

## Particles that land: bounce and friction, a collision box under the ground (`_ground_collider`).
static func _collide(pm: ParticleProcessMaterial, bounce: float, friction: float, _radius: float) -> void:
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = bounce
	pm.collision_friction = friction
	pm.collision_use_scale = false
	pm.particle_flag_damping_as_friction = false

## The ground under a burst as a particle collider (its top at the ground's height), freed with the particles.
static func _ground_collider(p: GPUParticles3D, g: Vector3) -> void:
	p.collision_base_size = 0.01
	var c := GPUParticlesCollisionBox3D.new()
	c.size = Vector3(14, 2, 14)
	p.add_child(c)
	c.global_position = Vector3(g.x, g.y - 1.0 + 0.02, g.z)
