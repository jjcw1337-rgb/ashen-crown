class_name HolyFx
extends RefCounted
## The knight's visual language (visual overhaul, stage 2): radiant light rather than fire. Holy Nova, Battle Cry
## and Charge had been the generic Fx ring, burst and pillar recoloured gold, the same shapes every class used; now
## they share pieces of their own, built the way InfernalFx builds the Demon's (shaders compiled once, noise from
## InfernalFx.noise(), one-shot pieces under the zone's FX node that free themselves):
##   - the seal: a sacred circle that draws itself on the ground (rings, ticks, a sunburst, four crosses), flares
##     white at the blow and fades; the knight's mark under every holy skill
##   - the holy fire ring: a band of white-gold flame racing outward along the ground (Holy Nova)
##   - the light column: a shaft of light round the hero, streaked and rising (Battle Cry)
##   - the shockwave: a ripple bending the picture behind it (Forward+, High and Ultra)
##   - the glow sprites (InfernalFx.glow_mat with rays), golden motes and a short light flash
## Palette: RADIANT white-gold carries the light, GOLD the shapes, SUNFIRE only the warm edges, so it never reads as
## the Demon's red or the Fire Arrow's orange. Counts scale with InfernalFx.tier (Low and the browser: fewest).

const RADIANT := Color(1.0, 0.94, 0.76)
const GOLD := Color(1.0, 0.74, 0.3)
const SUNFIRE := Color(1.0, 0.5, 0.16)
const DUST := Color(0.72, 0.64, 0.5)

static var _shaders := {}
static var _band: ArrayMesh
static var _column: ArrayMesh
static var _flat: PlaneMesh
static var _warm_world := 0

static func shader(key: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = {"seal": SEAL_SHADER, "ring": RING_SHADER, "column": COLUMN_SHADER, "shock": SHOCK_SHADER}[key]
		_shaders[key] = s
	return _shaders[key]

static func _pal(m: ShaderMaterial) -> ShaderMaterial:
	m.set_shader_parameter("radiant", RADIANT)
	m.set_shader_parameter("gold", GOLD)
	m.set_shader_parameter("sunfire", SUNFIRE)
	return m

static func seal_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("seal")
	return _pal(m)

static func ring_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("ring")
	m.set_shader_parameter("noise_tex", InfernalFx.noise())
	m.set_shader_parameter("seed", randf() * 10.0)
	return _pal(m)

static func column_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("column")
	m.set_shader_parameter("noise_tex", InfernalFx.noise())
	return _pal(m)

static func shock_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("shock")
	return m

## Compiles the shaders once per zone by drawing a tiny copy of each (a first cast would hitch).
static func warm(h: Hero) -> void:
	if h == null or not h.is_inside_tree() or h.game == null or h.game.world == null:
		return
	if _warm_world == h.game.world.get_instance_id():
		return
	_warm_world = h.game.world.get_instance_id()
	var mats: Array = [seal_mat(), ring_mat(), column_mat()]
	if InfernalFx.haze_ok(h.game):
		mats.append(shock_mat())
	for m in mats:
		var mi := MeshInstance3D.new()
		mi.mesh = InfernalFx.quad()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * 0.001
		h.game.world.fx_root.add_child(mi)
		mi.global_position = h.global_position + Vector3(0, 0.05, 0)
		Fx._free_later(mi, 0.3)

# ---------------------------------------------------------------- meshes (made once)
## An open cylinder of radius 1 and height 1 standing on the origin: UV.x round it, UV.y up it.
static func band() -> ArrayMesh:
	if _band == null:
		_band = _cylinder(64, 0.0, 1.0)
	return _band

## The light column: a slimmer cylinder whose top flares out a little.
static func column() -> ArrayMesh:
	if _column == null:
		_column = _cylinder(32, 0.0, 1.0, 1.35)
	return _column

static func _cylinder(segs: int, y0: float, y1: float, top := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p := [Vector3(cos(a0), y0, sin(a0)), Vector3(cos(a1), y0, sin(a1)), Vector3(cos(a1) * top, y1, sin(a1) * top), Vector3(cos(a0) * top, y1, sin(a0) * top)]
		var uv := [Vector2(float(i) / segs, 0.0), Vector2(float(i + 1) / segs, 0.0), Vector2(float(i + 1) / segs, 1.0), Vector2(float(i) / segs, 1.0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3(p[k].x, 0.0, p[k].z).normalized())
			st.set_uv(uv[k])
			st.add_vertex(p[k])
	return st.commit()

## A flat quad lying on the ground (for the seal and the shockwave), 1 m square.
static func flat() -> PlaneMesh:
	if _flat == null:
		_flat = PlaneMesh.new()
		_flat.size = Vector2.ONE
	return _flat

# ---------------------------------------------------------------- pieces
static func _piece(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scale: Vector3, life: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	root.add_child(mi)
	mi.global_position = pos
	mi.scale = scale
	Fx._free_later(mi, life)
	return mi

## The knight's seal on the ground at pos, radius r: draws itself in `draw_t`, flares, then fades over `fade`.
static func seal(root: Node3D, pos: Vector3, r: float, draw_t := 0.16, fade := 1.0, flare := 1.0) -> MeshInstance3D:
	var m := seal_mat()
	var mi := _piece(root, flat(), m, pos + Vector3(0, 0.06, 0), Vector3(r * 2.0, 1.0, r * 2.0), draw_t + fade + 0.1)
	mi.rotation.y = randf() * TAU
	m.set_shader_parameter("flare", flare)
	InfernalFx.tween_param(mi, m, "draw", 0.0, 1.0, draw_t)
	InfernalFx.tween_param(mi, m, "flare", flare, 0.0, 0.35, draw_t * 0.5)
	InfernalFx.tween_param(mi, m, "life", 1.0, 0.0, fade, draw_t)
	var tw := mi.create_tween()
	tw.tween_property(mi, "rotation:y", mi.rotation.y + 0.5, draw_t + fade)
	return mi

## A standing band of holy fire round pos racing out from r0 to r1 in `dur`, h metres tall, fading as it goes.
static func fire_ring(root: Node3D, pos: Vector3, r0: float, r1: float, h: float, dur: float) -> MeshInstance3D:
	var m := ring_mat()
	var mi := _piece(root, band(), m, pos + Vector3(0, 0.02, 0), Vector3(r0, h, r0), dur + 0.15)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(r1, h * 0.45, r1), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	InfernalFx.tween_param(mi, m, "life", 1.0, 0.0, dur).set_ease(Tween.EASE_IN)
	return mi

## A ripple racing out over the ground from pos to radius r in `dur` (Forward+ on High and Ultra only).
static func shockwave(root: Node3D, game, pos: Vector3, r: float, dur: float, strength := 0.018) -> void:
	if not InfernalFx.haze_ok(game):
		return
	var m := shock_mat()
	m.set_shader_parameter("strength", strength)
	var mi := _piece(root, flat(), m, pos + Vector3(0, 0.12, 0), Vector3(r * 2.0, 1.0, r * 2.0), dur + 0.1)
	InfernalFx.tween_param(mi, m, "front", 0.05, 0.95, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	InfernalFx.tween_param(mi, m, "life", 1.0, 0.0, dur).set_ease(Tween.EASE_IN)

## A soft sunburst sprite facing the camera (InfernalFx's glow with rays), shrinking out over `dur`.
static func sunburst(root: Node3D, pos: Vector3, size: float, dur: float, energy := 2.6, rays := 1.2) -> void:
	var m := InfernalFx.glow_mat(RADIANT, energy, 2.4, rays)
	var mi := InfernalFx.glow(root, pos, size, m)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.35, dur).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(mi, m, "alpha", 1.0, 0.0, dur).set_ease(Tween.EASE_IN)
	Fx._free_later(mi, dur + 0.05)

## Golden motes drifting up from a ring of radius r round pos (or a disc when r_in is 0).
static func motes(root: Node3D, pos: Vector3, r: float, amount: int, life := 1.1, r_in := -1.0, rise := Vector2(0.6, 1.6)) -> void:
	InfernalFx.particles(root, pos + Vector3(0, 0.15, 0), {"amount": amount, "life": life, "explosive": 0.85,
		"shape": "ring", "r": r, "r_in": (r * 0.82) if r_in < 0.0 else r_in, "dir": Vector3.UP, "spread": 25.0,
		"vel": [rise.x, rise.y], "gravity": 0.4, "damping": [0.6, 1.2], "scale": [0.5, 1.2], "size": 0.07,
		"turb": 0.6, "grow": [1.0, 0.2],
		"colors": [[0.0, Color(RADIANT, 0.0)], [0.12, RADIANT], [0.55, GOLD], [1.0, Color(SUNFIRE, 0.0)]]})

# ---------------------------------------------------------------- the knight's skills
## Holy Nova (E): the seal flares under him, a sunburst at his chest, a ring of holy fire races out to the edge of
## the 7 m blast with a ripple ahead of it, motes rise where it passed, the grass is laid down outward.
static func nova(h: Hero, root: Node3D, pos: Vector3, radius := 7.0) -> void:
	warm(h)
	var tr := InfernalFx.tier(h.game)
	GrassField.impulse(pos, radius, 0.8, 0.45)
	seal(root, pos, 2.4, 0.12, 0.9, 0.7)
	sunburst(root, pos + Vector3(0, 1.2, 0), 2.6, 0.28, 2.0, 1.2)
	fire_ring(root, pos, 0.6, radius, 1.4, 0.42)
	shockwave(root, h.game, pos, radius + 1.0, 0.42)
	Fx.flash(root, pos + Vector3(0, 1.2, 0), GOLD, 4.0, 0.45, radius * 1.4)
	motes(root, pos, radius * 0.75, [12, 22, 34, 46][tr], 1.2, radius * 0.25)
	# white sparks thrown outward low over the ground
	InfernalFx.particles(root, pos + Vector3(0, 0.6, 0), {"amount": [10, 16, 24, 32][tr], "life": 0.45, "explosive": 1.0,
		"shape": "sphere", "r": 0.3, "dir": Vector3.UP, "spread": 88.0, "vel": [9.0, 14.0], "gravity": -6.0,
		"damping": [2.0, 4.0], "scale": [0.4, 0.9], "size": 0.06,
		"colors": [[0.0, RADIANT], [0.6, GOLD], [1.0, Color(SUNFIRE, 0.0)]]})

## Battle Cry (F): the seal under him, a shaft of light rising round him and fading, a ripple and a thin bright
## ring out to the 6 m stun, embers spiralling up his column, a flare at his chest.
static func battle_cry(h: Hero, root: Node3D, pos: Vector3, radius := 6.0) -> void:
	warm(h)
	var tr := InfernalFx.tier(h.game)
	GrassField.impulse(pos, radius, 0.6, 0.4)
	seal(root, pos, 1.9, 0.18, 1.4, 0.6)
	var m := column_mat()
	var col := _piece(root, column(), m, pos, Vector3(0.8, 0.1, 0.8), 1.2)
	var tw := col.create_tween()
	tw.tween_property(col, "scale", Vector3(0.8, 6.0, 0.8), 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	InfernalFx.tween_param(col, m, "life", 1.0, 0.0, 0.85, 0.12).set_ease(Tween.EASE_IN)
	sunburst(root, pos + Vector3(0, 1.5, 0), 2.2, 0.32, 1.8, 0.9)
	fire_ring(root, pos, 0.5, radius, 0.32, 0.36)
	shockwave(root, h.game, pos, radius + 0.5, 0.34, 0.024)
	Fx.flash(root, pos + Vector3(0, 2.0, 0), RADIANT, 4.5, 1.0, 9.0)
	# embers rising up the column, turning in the updraught
	InfernalFx.particles(root, pos + Vector3(0, 0.3, 0), {"amount": [14, 24, 36, 48][tr], "life": 1.3, "explosive": 0.6,
		"shape": "ring", "r": 1.0, "r_in": 0.5, "dir": Vector3.UP, "spread": 12.0, "vel": [2.5, 5.5], "gravity": 0.0,
		"damping": [0.4, 0.9], "scale": [0.4, 1.0], "size": 0.06, "turb": 1.4, "grow": [1.0, 0.25],
		"colors": [[0.0, Color(RADIANT, 0.0)], [0.1, RADIANT], [0.6, GOLD], [1.0, Color(SUNFIRE, 0.0)]]})

## Charge (R): a streak of light and dust follows him for the dash (one emitter that moves with him, instead of a
## new burst every frame), a radiant flash on whoever he slams into, a seal and dust ring where he stops.
static func charge_start(h: Hero, root: Node3D) -> void:
	warm(h)
	charge_clear(h)
	var tr := InfernalFx.tier(h.game)
	var trail := InfernalFx.particles(root, h.global_position + Vector3(0, 0.25, 0), {"amount": [12, 22, 30, 40][tr],
		"life": 0.6, "one_shot": false, "explosive": 0.0, "shape": "sphere", "r": 0.35, "dir": Vector3.UP,
		"spread": 60.0, "vel": [0.3, 1.0], "gravity": 0.4, "damping": [1.0, 2.0], "scale": [1.0, 2.0],
		"size": 0.26, "grow": [0.6, 1.8], "add": false,
		"colors": [[0.0, Color(DUST.lightened(0.2), 0.0)], [0.15, Color(DUST.lightened(0.2), 0.75)], [1.0, Color(DUST, 0.0)]]})
	var glint := InfernalFx.particles(root, h.global_position + Vector3(0, 1.0, 0), {"amount": [10, 16, 24, 32][tr],
		"life": 0.4, "one_shot": false, "explosive": 0.0, "shape": "sphere", "r": 0.5, "dir": Vector3.UP,
		"spread": 180.0, "vel": [0.1, 0.4], "gravity": 0.0, "scale": [0.6, 1.2], "size": 0.11,
		"colors": [[0.0, Color(RADIANT, 0.0)], [0.15, RADIANT], [1.0, Color(GOLD, 0.0)]]})
	h.fxs["charge_trail"] = [trail, glint]

## Every frame of the dash: the trail follows him.
static func charge_follow(h: Hero) -> void:
	var t: Array = h.fxs.get("charge_trail", [])
	for i in t.size():
		var p = t[i]
		if is_instance_valid(p):
			(p as Node3D).global_position = h.global_position + Vector3(0, 0.25 if i == 0 else 1.0, 0)

## The dash ended: the trail stops emitting and fades out with its particles.
static func charge_clear(h: Hero) -> void:
	var t: Array = h.fxs.get("charge_trail", [])
	for p in t:
		if is_instance_valid(p):
			(p as GPUParticles3D).emitting = false
			Fx._free_later(p, 0.7)
	h.fxs.erase("charge_trail")

static func charge_hit(h: Hero, root: Node3D, p: Vector3, first: bool) -> void:
	sunburst(root, p + Vector3(0, 1.0, 0), 1.8 if first else 1.1, 0.22, 2.8, 1.0)
	InfernalFx.particles(root, p + Vector3(0, 1.0, 0), {"amount": 14 if first else 8, "life": 0.35, "explosive": 1.0,
		"shape": "sphere", "r": 0.2, "dir": Vector3.UP, "spread": 120.0, "vel": [5.0, 9.0], "gravity": -9.0,
		"scale": [0.4, 0.8], "size": 0.06, "colors": [[0.0, RADIANT], [1.0, Color(GOLD, 0.0)]]})
	if first:
		Fx.flash(root, p + Vector3(0, 1.0, 0), RADIANT, 2.5, 0.2, 5.0)

static func charge_end(h: Hero, root: Node3D, pos: Vector3) -> void:
	charge_clear(h)
	seal(root, pos, 1.3, 0.1, 0.6, 0.4)
	GrassField.impulse(pos, 2.5, 0.55, 0.35)
	InfernalFx.particles(root, pos + Vector3(0, 0.15, 0), {"amount": 16, "life": 0.7, "explosive": 1.0, "shape": "ring",
		"r": 0.5, "r_in": 0.3, "dir": Vector3(0, 0.15, 0), "spread": 180.0, "vel": [2.0, 3.5], "gravity": 0.2,
		"damping": [2.5, 3.5], "scale": [1.0, 2.0], "size": 0.3, "grow": [0.6, 1.8], "add": false,
		"colors": [[0.0, Color(DUST, 0.0)], [0.12, Color(DUST, 0.6)], [1.0, Color(DUST, 0.0)]]})

# ---------------------------------------------------------------- shaders
## The seal: an outer double ring with 48 ticks between, an inner ring, a sixteen-rayed sunburst and four crosses
## on the inner ring. It draws itself round (draw 0..1), flares white (flare), fades (life 1..0). Lines are
## anti-aliased by their screen width, with a soft glow round each and a faint pool of light inside.
const SEAL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float draw = 0.0;
uniform float flare = 0.0;
uniform float life = 1.0;
uniform vec3 radiant : source_color = vec3(1.0, 0.94, 0.76);
uniform vec3 gold : source_color = vec3(1.0, 0.74, 0.3);
uniform vec3 sunfire : source_color = vec3(1.0, 0.5, 0.16);
float sd_cross(vec2 p, float s, float w) {
	p = abs(p);
	return min(max(p.x - w, p.y - s), max(p.y - w, p.x - s));
}
void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	if (r > 1.02) { discard; }
	float an = fract(atan(q.y, q.x) / 6.2831853 + 0.5);
	float ang = atan(q.y, q.x);
	float d = 9.0;
	float sweep = clamp(draw * 1.25, 0.0, 1.0);
	if (an < sweep) {
		d = min(d, abs(r - 0.955) - 0.014);
		d = min(d, abs(r - 0.885) - 0.006);
		float tk = abs(fract(an * 48.0) - 0.5) * (6.2831853 * 0.92 / 48.0);
		if (r > 0.895 && r < 0.945) { d = min(d, tk - 0.004); }
	}
	if (1.0 - an < clamp(draw * 1.5 - 0.2, 0.0, 1.0)) {
		d = min(d, abs(r - 0.6) - 0.009);
	}
	// sixteen rays from the middle, long and short by turns, growing out as it draws
	float k = clamp(draw * 1.6 - 0.3, 0.0, 1.0);
	float seg = 6.2831853 / 16.0;
	float ai = floor(ang / seg + 0.5);
	float a0 = ai * seg;
	float len = (mod(ai, 2.0) < 0.5 ? 0.5 : 0.34) * k;
	vec2 dir = vec2(cos(a0), sin(a0));
	float along = dot(q, dir);
	float across = abs(dot(q, vec2(-dir.y, dir.x)));
	float taper = 0.012 * (1.0 - clamp(along / max(len, 1e-3), 0.0, 1.0)) + 0.002;
	if (along > 0.07 && along < len) { d = min(d, across - taper); }
	d = min(d, abs(r - 0.07) - 0.01);
	// four crosses on the inner ring
	if (k > 0.0) {
		for (int i = 0; i < 4; i++) {
			float a = float(i) * 1.5707963 + 0.7853982;
			vec2 c = vec2(cos(a), sin(a)) * 0.6;
			d = min(d, sd_cross(q - c, 0.055 * k, 0.011));
		}
	}
	float aa = fwidth(r) * 1.25 + 1e-4;
	float line = 1.0 - smoothstep(0.0, aa, d);
	float halo = exp(-max(d, 0.0) * 46.0) * 0.6;
	float pool = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
	vec3 col = gold * (line * 1.9 + halo * 0.55) + sunfire * halo * 0.25 + radiant * flare * (line * 1.1 + halo * 0.5 + pool * 0.2);
	col += gold * pool * 0.08 * draw;
	float a = clamp(line * 0.8 + halo * 0.25 + pool * 0.05 * draw, 0.0, 1.0);
	ALBEDO = col * life;
	ALPHA = a * life;
}
"""

## Holy fire: a band of flame along the ring, licking up from a white-hot foot to gold and a warm fringe that
## breaks into tongues at the top. life 1..0 burns it down.
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float life = 1.0;
uniform float seed = 0.0;
uniform vec3 radiant : source_color = vec3(1.0, 0.94, 0.76);
uniform vec3 gold : source_color = vec3(1.0, 0.74, 0.3);
uniform vec3 sunfire : source_color = vec3(1.0, 0.5, 0.16);
void fragment() {
	vec2 uv = UV;
	float n = texture(noise_tex, vec2(uv.x * 9.0 + seed, uv.y * 0.8 - TIME * 2.6)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 23.0 - seed, uv.y * 1.7 - TIME * 3.9)).r;
	float f = (1.02 - uv.y * (1.2 - 0.35 * life)) + (n * 0.62 + n2 * 0.38 - 0.5) * 0.95;
	f *= 0.5 + 0.5 * life;
	float body = smoothstep(0.14, 0.42, f);
	float core = smoothstep(0.42, 0.8, f);
	float hot = smoothstep(0.78, 1.02, f);
	float fringe = clamp(body - core, 0.0, 1.0);
	vec3 col = mix(gold * 1.5, sunfire * 1.3, smoothstep(0.35, 0.9, uv.y)) * fringe + radiant * 2.1 * clamp(core - hot, 0.0, 1.0) + vec3(1.0, 0.98, 0.92) * 3.0 * hot;
	float foot = smoothstep(0.0, 0.06, uv.y);
	float a = clamp(body * 0.55 + core * 0.4, 0.0, 1.0) * foot;
	ALBEDO = col * life * foot;
	ALPHA = a * life;
}
"""

## The light column: brightest where it faces the camera (soft edges, so it reads as a volume), fading in at the
## foot and out towards the top, streaked by noise rising up it.
const COLUMN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float life = 1.0;
uniform vec3 radiant : source_color = vec3(1.0, 0.94, 0.76);
uniform vec3 gold : source_color = vec3(1.0, 0.74, 0.3);
uniform vec3 sunfire : source_color = vec3(1.0, 0.5, 0.16);
void fragment() {
	float facing = pow(abs(dot(NORMAL, VIEW)), 2.5);
	float v = UV.y;
	float vert = smoothstep(0.0, 0.06, v) * (1.0 - smoothstep(0.15, 0.95, v));
	float n = texture(noise_tex, vec2(UV.x * 7.0, v * 0.35 - TIME * 1.4)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 17.0 + 0.3, v * 0.8 - TIME * 2.5)).r;
	float streak = pow(clamp(n * n2 * 2.4, 0.0, 1.5), 2.2);
	vec3 col = mix(radiant, gold, smoothstep(0.0, 0.6, v)) * (0.15 + 1.4 * streak);
	ALBEDO = col * facing * vert * life * 0.55;
}
"""

## The shockwave: a ripple at `front` (0..1 of the disc's radius) bending what is behind it outward.
const SHOCK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float front = 0.1;
uniform float strength = 0.018;
uniform float life = 1.0;
void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	float w = exp(-pow((r - front) / 0.07, 2.0)) * life;
	vec2 dir = q / max(r, 1e-4);
	vec2 off = vec2(dir.x, -dir.y) * w * strength;
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
	ALPHA = smoothstep(0.02, 0.25, w);
}
"""
