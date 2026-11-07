class_name PlagueBloomFx
extends RefCounted
## Corpse Bloom's look (the Plague Doctor's R; gameplay in plague.gd): a corpse flower erupting from the ground.
##
## The organism is the Meshy model game/heroes/plague/skills/corpse_bloom/bloom.glb (concept, image-to-3D, tools/blender/prep_prop.py:
## swollen spore sacs in diseased petals over black roots). It grows out of the soil (squash and stretch, the petals
## unfolding as it rises), breathes, and on each pulse swells and bursts. Under it a mat of roots creeps out across
## the ground to the edge of its reach: the Meshy painting bloom_roots (game/heroes/plague/build/ground_decal.py: keyed off
## black, normals baked from its relief in Blender), its spore pustules glowing brighter as a pulse nears. The edge
## of the reach is the Meshy ring of twisted roots (bloom_ring), always there once grown, and on the bloom's own
## clock (the same as the gameplay's) that ring draws in from the edge before each pulse, glowing, so everyone sees
## exactly when to move (`ROOT_SHADER`). The pulse is the Mantaflow spore burst (PlagueSmoke: the whole simulation
## thrown up off the sacs on a card, and its puffs rolling out over the reach); it is not an area blow, so it never
## scatters his own swarm. A snared foe is caught by the Meshy roots (game/heroes/plague/skills/corpse_bloom/roots.glb: black thorned
## roots with spore buds) bursting up round its feet (`lash`). At the end it withers, blackens and collapses into
## dust (`wither`). He plants it with the Meshy seed-syringe (syringe.glb).

const BLOOM_GLB := "res://game/heroes/plague/skills/corpse_bloom/bloom.glb"
const ROOTS_GLB := "res://game/heroes/plague/skills/corpse_bloom/roots.glb"
const SYRINGE_GLB := "res://game/heroes/plague/skills/corpse_bloom/syringe.glb"
const ROOTS_TEX := "res://game/heroes/plague/skills/corpse_bloom/bloom_roots_albedo.png"
const ROOTS_NRM := "res://game/heroes/plague/skills/corpse_bloom/bloom_roots_normal.png"
const RING_TEX := "res://game/heroes/plague/skills/corpse_bloom/bloom_ring_albedo.png"
const RING_NRM := "res://game/heroes/plague/skills/corpse_bloom/bloom_ring_normal.png"
const FLESH := Color(0.62, 0.25, 0.32)
const SPORE := Color(0.82, 0.95, 0.42)

static var _roots_scene: PackedScene

## The seed-syringe in his hand as he kneels: the Meshy brass syringe with its swollen bulb, needle down.
static func seed_syringe() -> Node3D:
	var root := Node3D.new()
	if ResourceLoader.exists(SYRINGE_GLB):
		var m: Node3D = ResCache.inst(SYRINGE_GLB)
		root.add_child(m)
		# the model lies along x, needle toward -x, bulb up: turned so the needle points out of his fist
		m.rotation = Vector3(0.0, -PI * 0.5, 0.0)
		m.position = Vector3(0.0, -0.035, 0.0)
		var l := OmniLight3D.new()
		l.light_color = SPORE
		l.light_energy = 0.35
		l.omni_range = 0.45
		l.position = Vector3(0.0, 0.06, 0.0)
		root.add_child(l)
		return root
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.52, 0.24)
	brass.metallic = 1.0
	brass.roughness = 0.35
	var tube := MeshInstance3D.new()
	tube.mesh = Geo.cyl(0.012, 0.012, 0.14, 10)
	tube.material_override = brass
	tube.rotation = Vector3(PI * 0.5, 0, 0)
	root.add_child(tube)
	var needle := MeshInstance3D.new()
	needle.mesh = Geo.cyl(0.002, 0.002, 0.08, 6)
	needle.material_override = Mats.mat(Color(0.8, 0.82, 0.85), 0.2, 1.0)
	needle.rotation = Vector3(PI * 0.5, 0, 0)
	needle.position = Vector3(0, 0, -0.11)
	root.add_child(needle)
	return root

class Bloom extends Node3D:
	var w: World
	var body: Node3D
	var roots: MeshInstance3D
	var rmat: ShaderMaterial
	var lamp: OmniLight3D
	var spores: GPUParticles3D
	var r := 3.5
	var age := 0.0
	var grow := 1.0
	var life := 7.0
	var every := 2.0
	var warn := 0.6
	var last_pulse := -1
	var pulse_t := 0.0
	var dying := -1.0
	var size := 1.0
	var hit_t := 9.0     # since a player last struck it (PvP, `hurt`): it recoils and wobbles back
	func setup(world: World, g: Vector3, radius: float, grow_t: float, active_t: float, every_t: float, warn_t: float) -> void:
		w = world
		r = radius
		grow = grow_t
		life = grow_t + active_t
		every = every_t
		warn = warn_t
		roots = PlagueVialFx._ground_disc(w, g, radius * 1.05, 14, 56, 0.04)
		rmat = ShaderMaterial.new()
		rmat.shader = PlagueBloomFx._root_shader()
		rmat.set_shader_parameter("spread", 0.0)
		rmat.set_shader_parameter("warn", 0.0)
		rmat.set_shader_parameter("pulse", 0.0)
		rmat.set_shader_parameter("seed", randf() * 50.0)
		rmat.set_shader_parameter("rot", randf() * TAU)
		rmat.set_shader_parameter("fade", 1.0)
		rmat.set_shader_parameter("roots", PlagueVialFx._tex(PlagueBloomFx.ROOTS_TEX))
		rmat.set_shader_parameter("roots_n", PlagueVialFx._tex(PlagueBloomFx.ROOTS_NRM))
		rmat.set_shader_parameter("ring", PlagueVialFx._tex(PlagueBloomFx.RING_TEX))
		rmat.set_shader_parameter("ring_n", PlagueVialFx._tex(PlagueBloomFx.RING_NRM))
		roots.material_override = rmat
		add_child(roots)
		roots.position = Vector3(0, -g.y, 0)
		body = Node3D.new()
		add_child(body)
		if ResourceLoader.exists(PlagueBloomFx.BLOOM_GLB):
			var m: Node3D = ResCache.inst(PlagueBloomFx.BLOOM_GLB)
			body.add_child(m)
			for mi in m.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		body.scale = Vector3(0.05, 0.05, 0.05)
		body.rotation.y = randf() * TAU
		size = 1.7    # larger than the 1.1 m model, so it reads from the game camera
		body.position = Vector3(0, -0.3, 0)
		lamp = OmniLight3D.new()
		lamp.light_color = PlagueBloomFx.SPORE
		lamp.light_energy = 0.0
		lamp.omni_range = radius * 0.9
		lamp.position = Vector3(0, 0.8, 0)
		add_child(lamp)
		# spores drifting up off the sacs the whole time: glinting motes and a thin haze of the spore simulation
		spores = Fx.aura(self, Color(PlagueBloomFx.SPORE.r, PlagueBloomFx.SPORE.g, PlagueBloomFx.SPORE.b, 0.8), 24, 0.35, 0.025, 2.2, 0.25, 0.45, 35.0, Vector3(0, 0.8, 0))
		var haze := PlagueSmoke.vapour(self, Color(0.72, 0.82, 0.45, 0.22), 6, 0.9, 2.4, 0.35, 0.35, Vector3(0, 1.3, 0))
		haze.name = "haze"
		# the ground breaking where it comes up: clods, and a roll of dust
		Fx.burst(self, g + Vector3(0, 0.15, 0), Color(0.18, 0.13, 0.1), 26, 2.6, 0.07, 0.7, false, -9.0, 60.0)
		PlagueSmoke.puffs(self, g + Vector3(0, 0.2, 0), PlagueSmoke.FOG, Color(0.36, 0.3, 0.24, 0.55), 7, 1.0, 1.0, 2.6, 0.3, 0.0, 0.0, Vector3.UP, true)
	func _process(delta: float) -> void:
		age += delta
		pulse_t = maxf(pulse_t - delta / 0.5, 0.0)
		var spread := clampf(age / (grow + 0.5), 0.0, 1.0)
		if dying >= 0.0:
			dying += delta
			var k := clampf(dying / 0.9, 0.0, 1.0)
			body.scale = body.scale.lerp(Vector3(0.6, 0.02, 0.6), clampf(delta * 3.5, 0.0, 1.0))
			body.position.y = lerpf(body.position.y, -0.35, clampf(delta * 2.0, 0.0, 1.0))
			rmat.set_shader_parameter("fade", 1.0 - k)
			rmat.set_shader_parameter("warn", 0.0)
			lamp.light_energy *= 0.9
			if dying > 1.8:
				queue_free()
			return
		rmat.set_shader_parameter("spread", 1.0 - pow(1.0 - spread, 2.0))
		rmat.set_shader_parameter("pulse", pulse_t * pulse_t)
		# the growth: squash and stretch out of the soil, overshooting
		var gk := clampf(age / grow, 0.0, 1.0)
		var s := 1.0
		if gk < 1.0:
			var e := 1.0 - pow(1.0 - gk, 3.0)
			s = e * (1.0 + 0.18 * sin(gk * PI))
			body.scale = Vector3(s * (1.0 + 0.15 * (1.0 - gk)), s * (0.6 + 0.4 * gk) * 1.1, s * (1.0 + 0.15 * (1.0 - gk))) * size * _recoil(delta)
			body.position.y = lerpf(-0.3, 0.0, e)
			lamp.light_energy = gk * 0.7
			return
		# alive: the sacs breathe; the warning ring draws in before each pulse; the pulse swells it
		var since := age - grow
		var cyc := fmod(since, every)
		var wk := 0.0
		if cyc >= every - warn:
			wk = (cyc - (every - warn)) / warn
		rmat.set_shader_parameter("warn", wk)
		var breathe := 1.0 + 0.04 * sin(age * 2.6)
		var swell := 1.0 + 0.12 * wk * wk
		body.scale = Vector3(breathe * swell, (2.0 - breathe) * swell * 1.0, breathe * swell) * size * _recoil(delta)
		lamp.light_energy = 0.35 + 0.5 * wk * wk + 1.2 * pulse_t
		var n := int(floor(since / every))
		if n > last_pulse and since >= every * float(n) and n >= 1:
			last_pulse = n
			_pulse()
	## The squash of a blow, ringing out (1 when it hasn't been struck).
	func _recoil(delta: float) -> Vector3:
		hit_t += delta
		var f := exp(-hit_t * 5.5) * cos(hit_t * 21.0)
		return Vector3(1.0 + 0.16 * f, 1.0 - 0.24 * f, 1.0 + 0.16 * f)
	## Struck by a player (PvP, PvpObjects): it recoils, bleeds dark sap and spores, its pustules flare.
	func hurt() -> void:
		if dying >= 0.0:
			return
		hit_t = 0.0
		pulse_t = maxf(pulse_t, 0.5)
		var p := global_position + Vector3(0, 0.9 * size * 0.6, 0)
		Fx.burst(self, p, Color(0.2, 0.26, 0.07, 0.95), 22, 3.0, 0.06, 0.7, false, -9.0, 65.0)
		Fx.burst(self, p + Vector3(0, 0.3, 0), Color(PlagueBloomFx.SPORE.r, PlagueBloomFx.SPORE.g, PlagueBloomFx.SPORE.b, 0.8), 14, 2.0, 0.04, 0.8, true, -1.0, 80.0)
		PlagueSmoke.puffs(self, p, PlagueSmoke.SPORE, Color(0.6, 0.72, 0.38, 0.45), 4, 0.9, 0.8, 0.8, 0.2, 0.4, 0.0)
		Sfx.play_at("impact_flesh", p, -5.0, randf_range(0.7, 0.85))
	## Killed by players (PvP): its sacs tear open in a last, harmless gasp of spores and it collapses fast.
	func kill() -> void:
		if dying >= 0.0:
			return
		hit_t = 0.0
		var p := global_position
		PlagueSmoke.spore_card(self, p + Vector3(0, 1.2, 0), Color(0.62, 0.7, 0.42, 1.0), 2.0, 0.85, 0.25)
		Fx.burst(self, p + Vector3(0, 1.0, 0), Color(0.2, 0.26, 0.07, 0.95), 40, 4.0, 0.07, 0.9, false, -9.0, 70.0)
		Fx.flash(self, p + Vector3(0, 1.0, 0), PlagueBloomFx.SPORE, 0.6, 0.2, r * 0.8)
		Sfx.play_at("blight_burst", p, -6.0, 0.6)
		wither()
		dying = 0.5     # faster than its own end
	## The sacs burst: the spore simulation thrown up off them, its puffs rolling out over the whole reach, glinting
	## motes, the pustules in the root mat flashing.
	func _pulse() -> void:
		body.scale *= 0.88
		pulse_t = 1.0
		var p := global_position
		PlagueSmoke.spore_card(self, p + Vector3(0, 1.45, 0), Color(0.82, 0.95, 0.5, 1.0), 2.4, 1.0, 0.55)
		PlagueSmoke.puffs(self, p + Vector3(0, 0.45, 0), PlagueSmoke.SPORE, Color(0.75, 0.9, 0.45, 0.6), 14, 1.7, 1.2, r * 2.0, 0.35, 0.25, 0.0, Vector3.UP, true, Color(0.2, 0.3, 0.08), 0.35)
		Fx.burst(self, p + Vector3(0, 1.2, 0), PlagueBloomFx.SPORE * Color(0.8, 0.8, 0.8), 44, 3.2, 0.05, 1.2, true, -1.5, 55.0)
		Fx.flash(self, p + Vector3(0, 1.0, 0), PlagueBloomFx.SPORE, 0.9, 0.25, r * 1.2)
	func wither() -> void:
		if dying < 0.0:
			dying = 0.0
			if spores != null:
				spores.emitting = false
			var haze := get_node_or_null("haze") as GPUParticles3D
			if haze != null:
				haze.emitting = false
			PlagueSmoke.puffs(self, global_position + Vector3(0, 0.5, 0), PlagueSmoke.FOG, Color(0.22, 0.18, 0.14, 0.7), 9, 1.1, 1.6, 1.4, 0.4, 0.3)

## A snared foe: the Meshy roots burst up round its feet and hold it, then sink back into the soil.
static func lash(bloom: Node, e: Node3D) -> void:
	if not is_instance_valid(bloom) or not (bloom is Bloom) or not is_instance_valid(e):
		return
	var b := bloom as Bloom
	var at := e.global_position
	var gy := b.w.height_at(at.x, at.z) if b.w != null else at.y
	var rad: float = float(e.get("radius")) if e.get("radius") != null else 0.5
	var root := Node3D.new()
	b.add_child(root)
	root.global_position = Vector3(at.x, gy, at.z)
	root.rotation.y = randf() * TAU
	if _roots_scene == null and ResourceLoader.exists(ROOTS_GLB):
		_roots_scene = load(ROOTS_GLB)
	if _roots_scene != null:
		var m: Node3D = _roots_scene.instantiate()
		root.add_child(m)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# wide enough that the foe stands inside the arches
		var k := clampf((rad * 2.0 + 0.7) / 1.05, 0.9, 2.4)
		m.position = Vector3(0, -0.06, 0)
		m.scale = Vector3(k * 0.7, 0.02, k * 0.7)
		var tw := m.create_tween()
		tw.tween_property(m, "scale", Vector3(k, k * 0.9, k), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.42)
		tw.tween_property(m, "scale", Vector3(k * 1.08, 0.02, k * 1.08), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.08, 0.06, 0.06)
		mat.roughness = 0.4
		for i in 5:
			var c := MeshInstance3D.new()
			c.mesh = Geo.cyl(0.015, 0.05, 0.9, 6)
			c.material_override = mat
			var a := TAU * float(i) / 5.0
			c.position = Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32)
			c.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
			root.add_child(c)
	Fx.burst(b, root.global_position + Vector3(0, 0.2, 0), Color(0.18, 0.13, 0.1), 16, 2.2, 0.05, 0.5, false, -9.0, 70.0)
	PlagueSmoke.puffs(b, root.global_position + Vector3(0, 0.15, 0), PlagueSmoke.FOG, Color(0.3, 0.25, 0.2, 0.5), 4, 0.7, 0.8, 1.6, 0.25, 0.0, 0.0, Vector3.UP, true)
	Fx._free_later(root, 1.2)

static var _rsh: Shader
## The bloom's ground: the painted mat of roots (revealed from the middle out to `spread`, its normals from Blender)
## inside the painted ring of roots at the reach's edge (the band of the ring painting, radii 0.675..0.9 of its image,
## laid along the last 14% of the reach); the same band drawing in from the edge as `warn` goes 0..1, glowing; the
## mat's spore pustules breathing and flashing on a pulse.
static func _root_shader() -> Shader:
	if _rsh != null:
		return _rsh
	_rsh = Shader.new()
	_rsh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
uniform float spread = 1.0;
uniform float warn = 0.0;
uniform float pulse = 0.0;
uniform float seed = 0.0;
uniform float rot = 0.0;
uniform float fade = 1.0;
uniform sampler2D roots : source_color, filter_linear_mipmap;
uniform sampler2D roots_n : hint_normal, filter_linear_mipmap;
uniform sampler2D ring : source_color, filter_linear_mipmap;
uniform sampler2D ring_n : hint_normal, filter_linear_mipmap;
varying vec2 lp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { lp = UV * 2.0 - 1.0; }
void fragment() {
	float c = cos(rot); float s = sin(rot);
	vec2 q = vec2(c * lp.x - s * lp.y, s * lp.x + c * lp.y) * 1.05;     // 1.0 = the edge of the reach
	float d = length(q);
	vec2 dir = q / max(d, 0.0001);
	// the mat of roots, crept out from the middle as far as `spread`
	vec2 uv = q * 0.45 + 0.5;
	vec4 rt = texture(roots, uv);
	float reach = spread * 1.06 + (noise(q * 7.0 + seed) - 0.5) * 0.1;
	float mat_a = rt.a * smoothstep(reach, reach - 0.1, d);
	// the ring of roots at the edge, there once it has grown
	float b0 = (d - 0.86) / 0.14;
	vec2 ruv = 0.5 + dir * mix(0.675, 0.9, clamp(b0, 0.0, 1.0)) * 0.5;
	vec4 rim = texture(ring, ruv);
	float rim_a = smoothstep(0.04, 0.2, rim.a) * step(0.0, b0) * step(b0, 1.0) * smoothstep(0.7, 1.0, spread);
	// the warning: the same ring drawing in from the edge
	float outer = 1.0 - warn * 0.86;
	float b1 = (d - (outer - 0.14)) / 0.14;
	vec2 wuv = 0.5 + dir * mix(0.675, 0.9, clamp(b1, 0.0, 1.0)) * 0.5;
	vec4 wr = texture(ring, wuv);
	float warn_a = smoothstep(0.04, 0.2, wr.a) * step(0.0, b1) * step(b1, 1.0) * step(0.001, warn);
	float ring_a = max(rim_a, warn_a);
	vec3 ring_col = warn_a > rim_a ? wr.rgb : rim.rgb;
	vec3 rn = warn_a > rim_a ? texture(ring_n, wuv).rgb : texture(ring_n, ruv).rgb;
	NORMAL_MAP = mix(texture(roots_n, uv).rgb, rn, ring_a);
	NORMAL_MAP_DEPTH = 1.3;
	ALBEDO = mix(rt.rgb * 0.62, ring_col * 0.9, ring_a);
	ROUGHNESS = 0.62;
	SPECULAR = 0.3;
	// the spore pustules: in the mat (breathing, brighter as the pulse nears, flashing on it) and on the warning ring;
	// the warning ring's roots themselves glow, brightest where the painting is lit, so it reads as roots, not a band
	float pm = smoothstep(0.06, 0.22, rt.g - max(rt.r, rt.b)) * mat_a;
	float pr = smoothstep(0.06, 0.22, wr.g - max(wr.r, wr.b)) * warn_a;
	float wl = dot(wr.rgb, vec3(0.3, 0.55, 0.15));
	float breathe = 0.8 + 0.2 * sin(TIME * 2.6 + d * 4.0);
	float glow = pm * (0.4 * breathe + 0.9 * warn * warn + 2.2 * pulse) + pr * (1.2 + 1.8 * warn) + warn_a * (0.14 + 0.42 * warn) * (0.4 + 1.4 * wl);
	EMISSION = vec3(0.75, 0.95, 0.3) * glow;
	ALPHA = clamp(max(mat_a, ring_a), 0.0, 1.0) * fade;
}
"""
	return _rsh

# ---------------------------------------------------------------- the events (PlagueFx), on every game
## Corpse Bloom's events: "bloom" {p, r, n: its id, x: seconds it breathes, a: seconds between pulses} (the Bloom keeps
## its own clock: growth, warning ring, pulse), "pulse" {p, n, t: the monsters its roots lash}, "obj" {n, x: blows
## left} (PvP: it flinches, and at none it dies). On another player's game in a match it has a stand-in to strike
## (PvpObjects.proxy).
static func play(h: Hero, ev: Dictionary) -> bool:
	var st := PlagueFx.state(h)
	if not st.has("blooms"):
		st["blooms"] = []
	var blooms: Array = st["blooms"]
	match str(ev["e"]):
		"bloom":
			var w: World = h.game.world
			var g: Vector3 = ev["p"]
			var r := float(ev.get("r", Skill.num("bloom", "radius", 3.5)))
			var oid := int(ev.get("n", 0))
			var grow := Skill.num("bloom", "grow_s", 1.0)
			var active := float(ev.get("x", Skill.num("bloom", "active_s", 6.0)))
			var node := Bloom.new()
			w.fx_root.add_child(node)
			node.global_position = g
			node.setup(w, g, r, grow, active, float(ev.get("a", Skill.num("bloom", "every", 2.0))), Skill.num("bloom", "warn", 0.6))
			blooms.append({"node": node, "pos": g, "age": 0.0, "life": grow + active, "oid": oid, "proxy": PlagueFx.proxy(h, oid, "bloom", g)})
			Sfx.play_at("impact_metal", g, -10.0, 0.7)
			Sfx.play_at("drip", g, -6.0, 0.5)
		"pulse":
			Sfx.play_at("blight_burst", ev["p"], -3.0, 0.8)
			var b := _of(blooms, int(ev.get("n", 0)))
			for e in ev.get("t", []):
				if not b.is_empty():
					lash(b["node"], e)
		"obj":
			var b := _of(blooms, int(ev.get("n", 0)))
			if b.is_empty():
				return true
			var left := int(ev.get("x", 0))
			PvpObjects.set_left(b.get("proxy"), left)
			var node = b["node"]
			if left > 0:
				if is_instance_valid(node):
					(node as Bloom).hurt()
			else:
				blooms.erase(b)
				if is_instance_valid(node):
					(node as Bloom).kill()
		_:
			return false
	return true

static func _of(blooms: Array, oid: int) -> Dictionary:
	for b in blooms:
		if int(b["oid"]) == oid:
			return b
	return {}

## Each withers at the end of its life (its own clock); a stand-in stays on it.
static func update(_h: Hero, st: Dictionary, delta: float) -> void:
	for b in (st.get("blooms", []) as Array).duplicate():
		b["age"] = float(b["age"]) + delta
		if not is_instance_valid(b["node"]) or float(b["age"]) >= float(b["life"]):
			# (or freed under it: a zone change; a typed hold on a freed node errors every frame)
			(st["blooms"] as Array).erase(b)
			PvpObjects.drop(b.get("proxy"))
			if is_instance_valid(b["node"]):
				(b["node"] as Bloom).wither()
			continue
		PvpObjects.keep_on(b.get("proxy"), b["pos"])

static func clear(_h: Hero, st: Dictionary) -> void:
	for b in st.get("blooms", []):
		if is_instance_valid(b["node"]):
			(b["node"] as Node).queue_free()
		PvpObjects.drop(b.get("proxy"))
	st.erase("blooms")
