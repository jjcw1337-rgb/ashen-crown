class_name Demon
extends RefCounted
## The Demon class: a horned, winged fiend in obsidian plate. Like the Wraith it reuses the
## knight's skeleton and joints (so Anim.pose, weapon grips, co-op puppets all work) and adds
## its own pieces. Everything sharp (horns, spikes, claws, blades, wing bones, the tail spade)
## is dark obsidian with a crisp, solid ember edge.

const EMBER := Color(1.0, 0.42, 0.06)
const CRIMSON := Color(0.95, 0.08, 0.12)

static var _edge_shader: Shader

static func default_gear() -> Dictionary:
	return {"edge": EMBER, "skin": Color(0.42, 0.06, 0.04), "steel": Color(0.07, 0.055, 0.06), "cloth": Color(0.3, 0.02, 0.03)}

## The knight body dressed as a fiend: obsidian plate, crimson cloth, red skin, ember trim.
static func body_gear(g: Dictionary) -> Dictionary:
	var k := Knight.default_gear()
	k["armor"] = "plate"
	k["steel"] = g["steel"]
	k["trim"] = g["edge"]
	k["glow"] = g["edge"]
	k["cloth"] = g["cloth"]
	k["cape"] = null
	k["emblem"] = g["cloth"]   # no holy cross on a fiend: the emblem blends into the cloth
	k["leather"] = Color(0.1, 0.04, 0.03)
	k["skin"] = g["skin"]
	k["hair"] = Color(0.02, 0.015, 0.015)
	k["quilt"] = g["cloth"].darkened(0.4)
	k["gloves"] = "gauntlets"
	k["boots"] = "greaves"
	k["coif"] = false
	return k

## His real body: the Meshy "Magma Brute" on the shared mocap system (tools/blender/demon/prep_demon_mocap.py:
## Meshy library clips, root motion taken out, the wings, tail and loincloth on their own bones that
## scripts/demon_mocap_rig.gd animates). Without the glb the knight body in obsidian plate below stands in.
const MOCAP_GLB := "res://assets/models/demon_mocap.glb"
## A brute: the model is 2.2 m tall as Meshy made it, and he stands this much bigger again (the knight is 1.8 m).
const SCALE := 1.08
## The clips' natural ground speeds (m/s; prep_demon_mocap.py prints them): the slow walk, the run, the head-down charge.
const WALK_SPEED := 1.3
const RUN_SPEED := 6.2
const CHARGE_SPEED := 7.6
const WALK_BLEND := 2.6        # above this ground speed the walk is gone from the blend
## His moves' clips per attack style (KnightMocapRig "shots": [[attack progress, clip second], ...], the blow on
## Anim.impact_at's frame): the weapon swings the punch, the axe chop and the ground slam (the finisher), Space's
## swings the chop, the punch and the hurl; his skills' styles below (DemonSkills.STYLE).
const SHOTS := {
	"side": {"style": "side", "clip": "claw", "keys": [[0.0, 0.45], [0.3, 1.0], [0.48, 1.33], [0.7, 1.7], [1.0, 2.4]]},
	"cast": {"style": "cast", "clip": "cast", "keys": [[0.0, 0.5], [0.3, 1.4], [0.55, 2.08], [1.0, 2.66]]},
	"swipe1": {"style": "swipe1", "clip": "claw", "keys": [[0.0, 0.6], [0.4, 1.33], [0.7, 1.7], [1.0, 2.3]]},
	"swipe2": {"style": "swipe2", "clip": "smash", "keys": [[0.0, 0.6], [0.42, 1.58], [0.7, 2.0], [1.0, 2.7]]},
	"swipe3": {"style": "swipe3", "clip": "slam", "keys": [[0.0, 0.6], [0.47, 2.75], [1.0, 3.0]]},
	"over": {"style": "over", "clip": "smash", "keys": [[0.0, 0.7], [0.5, 1.58], [0.75, 2.0], [1.0, 2.7]]},
	"back": {"style": "back", "clip": "claw", "keys": [[0.0, 0.7], [0.48, 1.33], [0.75, 1.7], [1.0, 2.3]]},
	"thrust": {"style": "thrust", "clip": "hurl", "keys": [[0.0, 0.5], [0.52, 1.75], [0.8, 2.3], [1.0, 3.3]]},
	# his skills (DemonSkills): the punch, the charge (the clip loops through the run), the slam, the throw (the
	# boulder leaves at the release), the grab (seized at 0.25, held up, smashed at 0.5), the roar and the stomp
	"fists": {"style": "fists", "clip": "claw", "keys": [[0.0, 0.45], [0.3, 1.0], [0.48, 1.33], [0.7, 1.7], [1.0, 2.4]]},
	"icharge": {"style": "icharge", "clip": "charge", "keys": [[0.0, 0.0], [1.0, 1.5]]},
	"cslam": {"style": "cslam", "clip": "slam", "keys": [[0.0, 0.3], [0.3, 1.3], [0.58, 2.75], [1.0, 3.0]]},
	"hurl": {"style": "hurl", "clip": "hurl", "keys": [[0.0, 0.3], [0.52, 1.75], [0.8, 2.4], [1.0, 3.3]]},
	"grip": {"style": "grip", "clip": "grab_throw", "keys": [[0.0, 0.2], [0.25, 1.2], [0.5, 3.08], [0.7, 3.4], [1.0, 4.0]]},
	"wrath_roar": {"style": "wrath_roar", "clip": "roar", "keys": [[0.0, 0.0], [0.5, 1.25], [1.0, 2.75]]},
	"wrath_stomp": {"style": "wrath_stomp", "clip": "stomp", "keys": [[0.0, 0.0], [0.5, 0.62], [1.0, 1.3]]},
	# the preview tool's names for the roar, the stomp and the grab
	"roar": {"style": "roar", "clip": "roar", "keys": [[0.0, 0.0], [0.5, 1.25], [1.0, 2.75]]},
	"stomp": {"style": "stomp", "clip": "stomp", "keys": [[0.0, 0.0], [0.5, 0.62], [1.0, 1.3]]},
	"grab": {"style": "grab", "clip": "grab_throw", "keys": [[0.0, 0.0], [0.3, 1.5], [0.5, 3.08], [1.0, 4.0]]},
}

static func mocap_ok() -> bool:
	return ResourceLoader.exists(MOCAP_GLB)

static func build(g: Dictionary) -> Node3D:
	if mocap_ok():
		return build_mocap(g)
	var root := Knight.build(body_gear(g))
	root.set_meta("demon", true)
	_extras(root, g)
	return root

static func build_mocap(g: Dictionary) -> Node3D:
	# the orc walk only at a crawl: from WALK_BLEND up the run alone carries him, slowed to his ground speed by
	# DemonMocapRig._rate (the run's planted foot moves at RUN_SPEED; at his 4.8 m/s it plays at 0.77x, heavy)
	var r := Knight.build_mocap(MOCAP_GLB, {
		"relaxed": ["idle", 0.0, "walk", WALK_SPEED, "run", WALK_BLEND, "run", RUN_SPEED, "charge", CHARGE_SPEED],
		"combat": ["combat_idle", 0.0, "walk", WALK_SPEED, "run", WALK_BLEND, "run", RUN_SPEED, "charge", CHARGE_SPEED],
		"meta": "demon", "scale": SCALE, "script": "res://scripts/demon_mocap_rig.gd",
		"shots": SHOTS})
	r.remove_meta("knight")
	r.set_meta("demon", true)
	r.set_meta("own_death", true)      # the death clip lays him down: no tilt from the hero
	var J: Dictionary = r.get_meta("j")
	# his hands are huge: the grips sit lower in the fist and the weapons scale up with him
	for gname in ["grip_r", "grip_l"]:
		var gr: Node3D = J[gname]
		gr.position.y = -0.13
		gr.scale = Vector3.ONE * 1.35
	(J["mount_l"] as Node3D).scale = Vector3.ONE * 1.3
	(J["mount_l"] as Node3D).position = Vector3(-0.09, -0.2, 0.0)
	_magma(r, g)
	_mocap_extras(r, g)
	return r

## The Meshy textures under the magma shader (scripts/demon_mocap.gdshader): matte skin, the lava in the cracks
## breathing, flaring, cooling in death, the Underworld's shadow.
static func _magma(r: Node3D, g: Dictionary) -> void:
	var sh: Shader = load("res://scripts/demon_mocap.gdshader")
	var mats := []
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.get_parent() is BoneAttachment3D or m.has_meta("fx"):
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si) as StandardMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = sh
			mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			if src.normal_texture != null:
				mat.set_shader_parameter("normal_tex", src.normal_texture)
				mat.set_shader_parameter("use_normal", true)
			mat.set_shader_parameter("ember", g["edge"])
			m.set_surface_override_material(si, mat)
			mats.append(mat)
	r.set_meta("demon_mats", mats)

## The lava's own light between his horns and chest, and the embers that rise off him when he dies.
static func _mocap_extras(r: Node3D, g: Dictionary) -> void:
	var J: Dictionary = r.get_meta("j")
	var tor: Node3D = J.get("at_torso", J["torso"])
	var l := OmniLight3D.new()
	l.name = "EmberGlow"
	l.light_color = g["edge"]
	l.light_energy = 0.5
	l.omni_range = 1.1
	l.omni_attenuation = 1.8
	l.shadow_enabled = false
	l.position = Vector3(0, 0.15, -0.3)
	tor.add_child(l)
	r.set_meta("eye_light", l)
	var e := DemonFx.ember_aura()
	e.name = "DeathEmbers"
	e.amount = 40
	e.lifetime = 1.6
	(e.process_material as ParticleProcessMaterial).emission_ring_radius = 0.9
	(e.process_material as ParticleProcessMaterial).emission_ring_inner_radius = 0.1
	(e.process_material as ParticleProcessMaterial).initial_velocity_min = 0.4
	(e.process_material as ParticleProcessMaterial).initial_velocity_max = 1.1
	e.position = Vector3(0, 0.15, -0.5)      # he falls forward: the embers rise off where he lies
	r.add_child(e)
	r.set_meta("death_embers", e)

static func rebuild_body(root: Node3D, g: Dictionary) -> void:
	if str(root.get_meta("meshy", "")) == "demon":
		for m in root.get_meta("demon_mats", []):
			(m as ShaderMaterial).set_shader_parameter("ember", g["edge"])
		var gl := root.find_child("EmberGlow", true, false) as OmniLight3D
		if gl != null:
			gl.light_color = g["edge"]
		return
	Knight.rebuild_body(root, body_gear(g))
	for m in root.get_meta("edge_mats", []):
		(m as ShaderMaterial).set_shader_parameter("edge", g["edge"])

## Obsidian with a solid bright edge: a hard rim band plus a glowing tip along local +Y.
static func edge_mat(col: Color, tip_lo: float = 1e6, tip_hi: float = 1e6 + 1.0, energy: float = 3.2) -> ShaderMaterial:
	if _edge_shader == null:
		_edge_shader = Shader.new()
		_edge_shader.code = EDGE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _edge_shader
	m.set_shader_parameter("edge", col)
	m.set_shader_parameter("tip_lo", tip_lo)
	m.set_shader_parameter("tip_hi", tip_hi)
	m.set_shader_parameter("energy", energy)
	return m

static func _extras(root: Node3D, g: Dictionary) -> void:
	var J: Dictionary = root.get_meta("j")
	var col: Color = g["edge"]
	var mats := []
	var rim := edge_mat(col)
	mats.append(rim)
	var hot := Mats.glow(col, 2.6)
	var hd: Node3D = J["head"]
	# great ram horns: thick at the root, sweeping up, back and curling forward, ember-tipped
	for side in [1, -1]:
		var prev := Vector3(side * 0.075, 0.18, -0.01)
		var dir := Vector3(side * 0.75, 0.62, 0.15).normalized()
		var r := 0.05
		for i in 9:
			var nxt := prev + dir * 0.055
			var s := Models.seg(hd, prev, nxt, r, r * 0.86, rim, 10)
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# ridges ringing the horn
			if i % 2 == 0 and i < 7:
				var rg := Models.P(hd, Geo.torus(r * 0.82, r * 1.05, 12, 4), rim, (prev + nxt) * 0.5)
				Models.orient_y(rg, dir)
			prev = nxt
			r *= 0.86
			dir = (dir + Vector3(side * 0.05, -0.2, 0.22)).normalized()
		var tip := Models.seg(hd, prev, prev + dir * 0.07, r, 0.001, hot, 8)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# burning eyes and a brow ridge of small spikes
	for sx in [-1, 1]:
		Models.P(hd, Geo.sph(0.017, 8), Mats.glow(Color(1.0, 0.75, 0.2), 6.0), Vector3(0.04 * sx, 0.125, -0.112), Vector3.ZERO, Vector3(1.5, 0.6, 1.0))
	for i in 3:
		var sp := Models.P(hd, Geo.cone(0.012, 0.06, 6), edge_mat(col, 0.0, 0.03), Vector3((i - 1) * 0.035, 0.205, -0.07), Vector3(-35, 0, (i - 1) * -15))
		mats.append(sp.material_override)
	# shoulder spikes: three per pauldron, fanning out
	for side_name in ["sh_r", "sh_l"]:
		var sh: Node3D = J[side_name]
		var sx: float = 1.0 if side_name == "sh_r" else -1.0
		for i in 3:
			var h := 0.16 - i * 0.03
			var m := edge_mat(col, h * 0.1, h * 0.5)
			mats.append(m)
			var sp := Models.P(sh, Geo.cone(0.03, h, 8), m, Vector3(sx * (0.05 + i * 0.02), 0.06 + h * 0.4, (i - 1) * 0.06), Vector3((i - 1) * 25, 0, -sx * (25 + i * 18)))
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a ridge of spines down the back
	var tor: Node3D = J["torso"]
	for i in 4:
		var h := 0.13 - i * 0.02
		var m := edge_mat(col, h * 0.1, h * 0.5)
		mats.append(m)
		Models.P(tor, Geo.cone(0.025, h, 7), m, Vector3(0, 0.42 - i * 0.1, 0.15 + i * 0.005), Vector3(65, 0, 0))
	# forearm blades sweeping back past the elbow
	for el_name in ["el_r", "el_l"]:
		var el: Node3D = J[el_name]
		var sx: float = 1.0 if el_name == "el_r" else -1.0
		var blade := PackedVector2Array([Vector2(0, 0), Vector2(0.05, 0.02), Vector2(0.27, 0.11), Vector2(0.06, -0.035), Vector2(0, -0.03)])
		var bm := edge_mat(col, 0.02, 0.1, 3.6)
		mats.append(bm)
		var b := Models.P(el, Geo.extrude(blade, 0.012, "demon_blade"), bm, Vector3(sx * 0.055, -0.2, 0.02), Vector3(0, -sx * 90, 90 + 15))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# claws
	for hand in ["hand_r", "hand_l"]:
		var hn: Node3D = J[hand]
		for i in 4:
			var c := Models.P(hn, Geo.cone(0.009, 0.075, 6), edge_mat(col, -0.01, 0.035), Vector3((i - 1.5) * 0.016, -0.085, -0.03), Vector3(180 + 20, 0, (i - 1.5) * 8.0))
			mats.append(c.material_override)
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# bat wings: ember-edged bones with a dark, glowing-veined membrane
	var wings := []
	var memb := Mats.mat(Color(0.16, 0.02, 0.03), 0.85, 0.0, Color(0.5, 0.05, 0.02), 0.25, 0.4)
	memb = memb.duplicate()
	(memb as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [1, -1]:
		var wroot := Models.N(tor, "wing_" + ("r" if side == 1 else "l"), Vector3(side * 0.09, 0.42, 0.14))
		wings.append(wroot)
		var tips := [Vector3(side * 0.95, 0.42, 0.35), Vector3(side * 0.85, 0.05, 0.4), Vector3(side * 0.6, -0.25, 0.32)]
		var elbow := Vector3(side * 0.42, 0.32, 0.25)
		var bs := Models.seg(wroot, Vector3.ZERO, elbow, 0.022, 0.016, rim, 6)
		bs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pts := PackedVector3Array([Vector3.ZERO, elbow])
		for t in tips:
			var fb := Models.seg(wroot, elbow, t, 0.012, 0.004, rim, 5)
			fb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var tc := Models.P(wroot, Geo.cone(0.012, 0.07, 5), hot, t)
			Models.orient_y(tc, (t - elbow).normalized())
			pts.append(t)
		# membrane: a fan of triangles between the finger bones, sagging between them
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var fan := [Vector3.ZERO, tips[0], tips[1], tips[2], Vector3(side * 0.18, -0.2, 0.1)]
		for k in fan.size() - 1:
			var a: Vector3 = fan[k]
			var b2: Vector3 = fan[k + 1]
			var mid := (a + b2) * 0.5 * 0.86 + elbow * 0.14
			for tri in [[elbow, a, mid], [elbow, mid, b2]]:
				for v in tri:
					st.set_normal(Vector3(0, 0, 1))
					st.add_vertex(v)
		var mm := MeshInstance3D.new()
		mm.mesh = st.commit()
		mm.material_override = memb
		wroot.add_child(mm)
	# a whip of a tail ending in a burning spade
	var hips: Node3D = J["hips"]
	var tail_root := Models.N(hips, "tail", Vector3(0, -0.05, 0.13))
	var segs := []
	var parent: Node3D = tail_root
	var r := 0.045
	for i in 8:
		var sgn := Models.N(parent, "t%d" % i, Vector3(0, -0.02, 0.09) if i > 0 else Vector3.ZERO)
		var s := Models.seg(sgn, Vector3.ZERO, Vector3(0, -0.02, 0.09), r, r * 0.85, rim, 7)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		segs.append(sgn)
		parent = sgn
		r *= 0.86
	var spade := PackedVector2Array([Vector2(0, 0), Vector2(0.06, 0.05), Vector2(0.0, 0.16), Vector2(-0.06, 0.05)])
	var sm := Models.P(parent, Geo.extrude(spade, 0.01, "demon_spade"), hot, Vector3(0, -0.02, 0.09), Vector3(90, 0, 0))
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("edge_mats", mats)
	root.set_meta("demon_anim", {"wings": wings, "tail": segs})

## Wings beat slowly (faster when moving), the tail sways like a cat's (the procedural fallback body). The mocap
## body's wings and tail are the rig's own (DemonMocapRig); here only its lava is driven: it flares through an
## attack or a cast, pulses when he is hurt, and goes to the Underworld's shadow while he is phased (hero.phased).
static func animate(root: Node3D, t: float, move: float, h: Node = null) -> void:
	if root.has_meta("demon_mats"):
		if h == null:
			return
		var a: float = float(h.get("atk_t")) / maxf(float(h.get("atk_dur")), 0.01) if float(h.get("atk_t")) >= 0.0 else -1.0
		var flare := 0.0
		if a >= 0.0:
			flare = 0.9 * sin(clampf(a / 0.75, 0.0, 1.0) * PI)
		var hit_t: float = float(h.get("hit_t"))
		var pulse := 0.8 * clampf(hit_t, 0.0, 1.0) * (0.5 + 0.5 * sin(t * 18.0))
		var buff := 0.3 if float(h.get("buff_t")) > 0.0 else 0.0
		# Wrath of the Pit: the white heat (DemonFx keeps the shader's "wrath"); the glow rides a little higher with it
		if (h.get("fxs") as Dictionary).has("wrath"):
			buff += 0.6 * float((h.get("fxs") as Dictionary)["wrath"].get("k", 0.0))
		var want_phase := 1.0 if bool(h.get("phased")) else 0.0
		var ph: float = float(root.get_meta("phase_now", 0.0))
		var dt := clampf(t - float(root.get_meta("phase_t", t)), 0.0, 0.1)
		root.set_meta("phase_t", t)
		ph = move_toward(ph, want_phase, dt * 2.4)
		root.set_meta("phase_now", ph)
		for m in root.get_meta("demon_mats"):
			(m as ShaderMaterial).set_shader_parameter("glow", flare + pulse + buff)
			(m as ShaderMaterial).set_shader_parameter("phase_amt", ph)
		var gl := root.get_meta("eye_light") as OmniLight3D if root.has_meta("eye_light") else null
		if gl != null and not bool(h.get("dead")):
			gl.light_energy = (0.5 + 0.6 * (flare + pulse)) * (1.0 - 0.8 * ph)
		# a heavy footfall shakes the camera a touch (local only)
		var thump: float = float(root.get("thump")) if root.get("thump") != null else 0.0
		var gm = h.get("game")
		if thump > 0.0 and not bool(h.get("puppet")) and gm != null and gm.has_method("add_shake"):
			gm.add_shake(0.035 * thump * (1.0 + 0.5 * move))
		return
	if not root.has_meta("demon_anim"):
		return
	var a: Dictionary = root.get_meta("demon_anim")
	var beat := sin(t * (2.2 + move * 2.5)) * (0.18 + move * 0.25)
	var wl: Array = a["wings"]
	for i in wl.size():
		var w: Node3D = wl[i]
		var side := 1.0 if i == 0 else -1.0
		w.rotation = Vector3(0.15 + beat * 0.3, side * (0.35 + beat), side * beat * 0.4)
	var tl: Array = a["tail"]
	for i in tl.size():
		var s: Node3D = tl[i]
		s.rotation = Vector3(-0.12 + sin(t * 1.4 + i * 0.5) * 0.06, sin(t * 1.9 - i * 0.55) * 0.22, 0.0)

const EDGE_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 edge : source_color = vec3(1.0, 0.42, 0.06);
uniform float tip_lo = 1000000.0;
uniform float tip_hi = 1000001.0;
uniform float energy = 3.2;
varying float ly;
void vertex(){ ly = VERTEX.y; }
void fragment(){
	float rim = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	// a crisp, solid band on the silhouette edge rather than a soft glow
	float band = smoothstep(0.62, 0.7, rim);
	float tip = smoothstep(tip_lo, tip_hi, ly);
	float e = max(band, tip);
	ALBEDO = mix(vec3(0.035, 0.025, 0.03), edge * 0.6, e);
	METALLIC = 0.55;
	ROUGHNESS = 0.3;
	EMISSION = edge * energy * e;
}
"""
