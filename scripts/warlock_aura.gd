class_name WarlockAura
extends RefCounted
## The jungle void spirit's presence (Blaine, 2026-11-06: "she feels lame... she looks so static when she's just
## chilling"): what is always round her, idle or gliding, on the class picker and the title as in the game.
##  - three void wisps (WarlockHarrowFx.wisp_node) wheel round her on their own tilted orbits; they follow her on a
##    spring, so gliding they stream behind her, and while she casts they whirl in tight and fast
##  - void fire in her hands: fel green in the left, violet in the right (Corruption and Fear), a soft light in the left
##  - petals, violet and fel green, drift off her crown and shoulders and tumble down (shed in the world: they trail)
##  - void motes rising off her fraying hem (with the hem's mist, retinted from a dark stain to a soft violet glow)
## Also the shared pieces of her skills' look: the petal material (a drawn petal, not a square) and the curse sigil
## (a ring of turning runes drawn by a shader on the ground, in the curse's colour).
## Warlock._build_spirit calls build; Warlock.animate calls update every frame (the local hero and every puppet).

const FEL := Warlock.FEL
const VIOLET := Color(0.72, 0.45, 1.0)
const WISPS := 3
## per wisp: [orbit radius, height, speed (rad/s, sign = direction), tilt]
const ORBITS := [[0.62, 1.05, 0.95, 0.22], [0.78, 0.7, -0.7, -0.16], [0.55, 1.5, 1.25, 0.3]]
const FOLLOW := 5.5          # how tightly the wisps follow their orbit (higher = less trailing)

static var _petal_tex: ImageTexture
static var _petal_mats := {}
static var _sigil_shader: Shader

## The ambient pieces on the spirit's rig (meta "aura").
static func build(r: Node3D) -> void:
	var J: Dictionary = r.get_meta("j")
	var a := {"wisps": [], "t": -1.0}
	for i in WISPS:
		var w := wisp(FEL if i == 1 else VIOLET)
		w.top_level = true
		r.add_child(w)
		(a["wisps"] as Array).append(w)
	# void fire cupped in each hand
	var hands := []
	for side in ["l", "r"]:
		var at: Node3D = J.get("at_hand_" + side)
		if at == null:
			continue
		var col: Color = FEL if side == "l" else VIOLET
		var hold := Node3D.new()
		hold.name = "HandFire_" + side
		hold.position = Vector3(0, -0.06, -0.02)
		at.add_child(hold)
		var core := MeshInstance3D.new()
		core.mesh = InfernalFx.quad()
		core.scale = Vector3.ONE * 0.22
		core.material_override = InfernalFx.glow_mat(col, 1.3, 2.6, 0.0)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.extra_cull_margin = 1.0
		hold.add_child(core)
		var fl := Warlock.fel_flame(0.55, col)
		hold.add_child(fl)
		hands.append(core)
		if side == "l":
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 0.55
			l.omni_range = 1.3
			l.shadow_enabled = false
			hold.add_child(l)
			a["light"] = l
	a["hands"] = hands
	# petals off her crown and shoulders
	var head: Node3D = J.get("at_head", J.get("head"))
	if head != null:
		var pet := InfernalFx.particles(head, Vector3.ZERO, {"amount": 9, "life": 3.2, "one_shot": false,
			"explosive": 0.0, "randomness": 0.6, "shape": "box", "box": Vector3(0.32, 0.12, 0.22), "dir": Vector3(0, 0.3, 0),
			"spread": 180.0, "vel": [0.05, 0.25], "gravity": -0.32, "damping": [0.2, 0.5], "angle": true, "spin": 160.0,
			"turb": 0.7, "scale": [0.7, 1.3], "mat": petal_mat(), "size": 0.075,
			"colors": [[0.0, Color(0.55, 0.3, 0.9, 0.0)], [0.12, Color(0.55, 0.3, 0.9)], [0.5, Color(0.3, 0.8, 0.3, 0.95)], [1.0, Color(0.08, 0.35, 0.1, 0.0)]]})
		pet.name = "Petals"
		pet.position = Vector3(0, 0.05, 0)
	# void motes rising off the hem
	var motes := InfernalFx.particles(r, Vector3.ZERO, {"amount": 14, "life": 1.6, "one_shot": false, "explosive": 0.0,
		"shape": "ring", "r": 0.36, "r_in": 0.15, "dir": Vector3.UP, "spread": 25.0, "vel": [0.25, 0.7], "gravity": 0.1,
		"damping": [0.3, 0.6], "turb": 0.5, "scale": [0.5, 1.1], "size": 0.035, "mat": Mats.particle_mat(true, Color(1.1, 1.1, 1.1)),
		"colors": [[0.0, Color(VIOLET, 0.0)], [0.15, Color(0.62, 0.38, 0.95)], [0.6, Color(0.35, 0.85, 0.35, 0.8)], [1.0, Color(0.15, 0.5, 0.15, 0.0)]]})
	motes.name = "HemMotes"
	motes.position = Vector3(0, 0.22, 0.04)
	# the hem's mist: a soft violet glow instead of a dark stain on the ground behind her
	var mist := r.get_meta("hem_mist", null) as GPUParticles3D
	if mist != null and mist.draw_pass_1 is QuadMesh:
		(mist.draw_pass_1 as QuadMesh).material = Mats.particle_mat(true, Color(0.42, 0.24, 0.75))
		(mist.draw_pass_1 as QuadMesh).size = Vector2(0.2, 0.2)
		mist.amount_ratio = 0.35
	r.set_meta("aura", a)

## Every frame: the wisps' orbits, the hands' fire breathing. `free`: not casting or channelling.
static func update(r: Node3D, t: float, move: float, free: bool) -> void:
	if not r.has_meta("aura"):
		return
	var a: Dictionary = r.get_meta("aura")
	var dt := clampf(t - float(a["t"]), 0.0, 0.1) if float(a["t"]) >= 0.0 else 0.0
	var first := float(a["t"]) < 0.0
	a["t"] = t
	var dead := float(r.get("death_t")) >= 0.0 if r.get("death_t") != null else false
	var shown := r.is_visible_in_tree() and not dead
	var k := r.global_transform.basis.get_scale().x
	var c := r.global_position
	# casting, they draw in and whirl; the whirl eases in and out
	var cast_w: float = move_toward(float(a.get("cast", 0.0)), 0.0 if free else 1.0, dt * 4.0)
	a["cast"] = cast_w
	var spin := 1.0 + 1.6 * cast_w
	a["ph"] = float(a.get("ph", 0.0)) + dt * spin
	var ph: float = a["ph"]
	var wisps: Array = a["wisps"]
	for i in wisps.size():
		var w = wisps[i]
		if not is_instance_valid(w):
			continue
		(w as Node3D).visible = shown
		if not shown:
			continue
		var o: Array = ORBITS[i]
		var ang: float = ph * float(o[2]) + TAU * i / WISPS
		var rad: float = (float(o[0]) * (1.0 - 0.35 * cast_w) + 0.06 * sin(t * 1.3 + i * 2.0)) * k
		var hgt: float = (lerpf(float(o[1]), 1.15, cast_w * 0.6) + 0.12 * sin(t * 0.8 + i * 2.1) + sin(ang) * float(o[3])) * k
		var want := c + Vector3(cos(ang) * rad, hgt, sin(ang) * rad)
		var wn := w as Node3D
		if first or wn.global_position.distance_to(want) > 6.0 * k:
			wn.global_position = want
		else:
			wn.global_position = wn.global_position.lerp(want, 1.0 - exp(-dt * FOLLOW * (1.0 + cast_w)))
		WarlockHarrowFx.pulse(wn, t, 0.15 + 0.6 * cast_w)
	# the hands' fire breathes, and flares while she casts
	for h in a["hands"]:
		if is_instance_valid(h):
			(h as Node3D).scale = Vector3.ONE * (0.26 + 0.04 * sin(t * 3.1 + float(h.get_instance_id() % 7)) + 0.16 * cast_w)
	if a.has("light") and is_instance_valid(a["light"]):
		(a["light"] as OmniLight3D).light_energy = 0.5 + 0.08 * sin(t * 5.3) + 0.7 * cast_w

## One of her wisps: a small bright core in a soft glow, trailing a few motes of its colour (lighter than the
## skills' wisps, WarlockHarrowFx.wisp_node: these are always there, so they mustn't flare white).
static func wisp(col: Color) -> Node3D:
	var n := Node3D.new()
	n.name = "AuraWisp"
	n.set_meta("flap", randf() * TAU)
	var core := MeshInstance3D.new()
	core.name = "core"
	core.mesh = Geo.sph(0.028, 8)
	core.material_override = Mats.glow(col.lightened(0.35), 2.6)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	var halo := MeshInstance3D.new()
	halo.mesh = InfernalFx.quad()
	halo.scale = Vector3.ONE * 0.3
	halo.extra_cull_margin = 1.0
	halo.material_override = InfernalFx.glow_mat(col, 1.25, 2.8, 0.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(halo)
	var tr := InfernalFx.particles(n, Vector3.ZERO, {"amount": 10, "life": 0.4, "one_shot": false, "explosive": 0.0,
		"shape": "sphere", "r": 0.02, "dir": Vector3.UP, "spread": 180.0, "vel": [0.0, 0.05], "scale": [0.6, 1.0],
		"grow": [1.0, 0.2], "size": 0.035, "mat": Mats.particle_mat(true, Color(0.8, 0.8, 0.8)),
		"colors": [[0.0, Color(col, 0.8)], [1.0, Color(col, 0.0)]]})
	tr.name = "trail"
	return n

# ---------------------------------------------------------------- shared looks
## A petal (drawn once into a small texture: a pointed oval with a paler midrib), for billboard particles; the
## particles' colour ramp tints it.
static func petal_mat(additive := false) -> StandardMaterial3D:
	var key := "a" if additive else "m"
	if _petal_mats.has(key):
		return _petal_mats[key]
	if _petal_tex == null:
		var n := 48
		var im := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0    # across
				var v := (y + 0.5) / n * 2.0 - 1.0    # along, tip at -1
				# a petal: wide near its base, pointed at its tip, a little curved
				var cx := u - 0.12 * (1.0 - v * v)
				var half := 0.62 * pow(clampf((1.0 - v) * 0.5, 0.0, 1.0), 0.55) * sqrt(clampf(1.0 - v * v, 0.0, 1.0))
				var d := absf(cx) / maxf(half, 0.001)
				var al := clampf((1.0 - d) * 6.0, 0.0, 1.0) * clampf((1.0 - absf(v)) * 8.0, 0.0, 1.0)
				var rib := 1.0 - clampf(absf(cx) * 14.0, 0.0, 1.0)
				var shade := 0.72 + 0.28 * (1.0 - d) + 0.25 * rib
				im.set_pixel(x, y, Color(shade, shade, shade, al))
		im.generate_mipmaps()
		_petal_tex = ImageTexture.create_from_image(im)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.95, 0.95, 0.95) if not additive else Color(1.6, 1.6, 1.6)
	m.albedo_texture = _petal_tex
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_petal_mats[key] = m
	return m

## The curse sigil: a ring of runes turning on the ground, drawn by a shader on a flat quad (radius in metres). Its
## material's "alpha" fades it, "pulse" flares it (a curse's burst).
static func sigil(col: Color, radius: float, seed := 0.0, spin := 0.6) -> MeshInstance3D:
	if _sigil_shader == null:
		_sigil_shader = Shader.new()
		_sigil_shader.code = SIGIL_SHADER
	var m := ShaderMaterial.new()
	m.shader = _sigil_shader
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("spin", spin)
	var q := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * radius * 2.0
	q.mesh = pm
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q

const SIGIL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform vec3 color : source_color = vec3(0.35, 1.0, 0.3);
uniform float alpha = 1.0;
uniform float pulse = 0.0;
uniform float seed = 0.0;
uniform float spin = 0.6;
float h1(float n) { return fract(sin(n * 91.345 + seed * 17.13) * 43758.5453); }
float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a, ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(w * 0.5, w, length(pa - ba * t));
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float ang = atan(p.y, p.x) + TIME * spin;
	// two rings
	float ring = smoothstep(0.035, 0.0, abs(r - 0.93)) + 0.8 * smoothstep(0.025, 0.0, abs(r - 0.66));
	// runes between them: a stave and branches per cell, picked by a hash
	float N = 14.0;
	float cell = floor(ang / 6.2831853 * N);
	float u = fract(ang / 6.2831853 * N);
	float v = (r - 0.69) / 0.21;
	float rune = 0.0;
	if (v > 0.0 && v < 1.0) {
		vec2 q = vec2((u - 0.5) * 1.6, v - 0.5);
		float hs = h1(cell);
		rune = seg(q, vec2(0.0, -0.36), vec2(0.0, 0.36), 0.12);
		if (hs > 0.25) rune = max(rune, seg(q, vec2(0.0, 0.2), vec2(0.28 * sign(hs - 0.6), 0.36), 0.1));
		if (fract(hs * 7.0) > 0.4) rune = max(rune, seg(q, vec2(0.0, -0.05), vec2(-0.26, 0.15), 0.1));
		if (fract(hs * 13.0) > 0.55) rune = max(rune, seg(q, vec2(0.0, -0.3), vec2(0.24, -0.1), 0.1));
	}
	// a thorned vine curling inside: three hooked arcs turning the other way
	float a2 = atan(p.y, p.x) - TIME * spin * 1.6;
	float vine = 0.0;
	for (int i = 0; i < 3; i++) {
		float aa = a2 + float(i) * 2.0943951;
		float rr = 0.18 + 0.4 * fract(aa / 6.2831853);
		vine = max(vine, smoothstep(0.03, 0.0, abs(r - rr)) * step(0.15, r) * step(r, 0.6));
	}
	float glow = (1.0 - smoothstep(0.0, 1.0, r)) * 0.18;
	float breathe = 0.8 + 0.2 * sin(TIME * 2.6 + seed * 3.0);
	float v_all = (ring + rune * 0.95 + vine * 0.55) * breathe + glow;
	ALBEDO = color * v_all * (1.4 + 2.0 * pulse);
	ALPHA = clamp(v_all, 0.0, 1.0) * alpha;
}
"""
