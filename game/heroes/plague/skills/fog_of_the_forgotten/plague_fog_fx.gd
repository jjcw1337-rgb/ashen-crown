class_name PlagueFogFx
extends RefCounted
## Fog of the Forgotten's look (the Plague Doctor's F; gameplay and the hiding rules in plague.gd).
##
## Not a poison cloud: pale grey with a faint lavender, like smelling salts and incense, moving in slow curls. He
## dashes his censer down (the Meshy censer, game/heroes/plague/skills/fog_of_the_forgotten/censer.glb, held in his hand until then) and it
## lies there smoking while the fog billows out of it. Every puff of the fog is the Mantaflow simulation of one heavy
## puff hitting the floor and rolling out (PlagueSmoke.FOG, played over each puff's life from where it has already
## rolled out), in three layers: a heavy ground roll, the body, thin wisps curling off the top. Under them a ground
## layer from the Meshy cloud painting (fog_base: its wisps kept, alpha from their brightness), two copies turning
## against each other into churning tendrils, lit by the scene, thinning at the rim so the edge reads; faint glinting
## glass-dust motes inside, and a cool light that halos what's in it. It
## billows out from the censer (the emitters' reach grows over ROLL_T) and at the end thins from the rim inward.
## Budgets by the graphics preset.

const COL := Color(0.66, 0.66, 0.74)
const DEEP := Color(0.5, 0.49, 0.6)
const ROLL_T := 0.6
const CENSER_GLB := "res://game/heroes/plague/skills/fog_of_the_forgotten/censer.glb"
const BASE_TEX := "res://game/heroes/plague/skills/fog_of_the_forgotten/fog_base_albedo.png"

## The censer in his hand before he dashes it down: hanging upright under his fist, smoking.
static func censer_in_hand() -> Node3D:
	var root := Node3D.new()
	if ResourceLoader.exists(CENSER_GLB):
		var m: Node3D = ResCache.inst(CENSER_GLB)
		root.add_child(m)
		# the model lies on its side along x, its crown toward +x: stood up, crown to his fist
		m.rotation = Vector3(0.0, 0.0, PI * 0.5)
		m.scale = Vector3.ONE * 0.6
		m.position = Vector3(0.07, -0.16, 0.0)
	PlagueSmoke.vapour(root, Color(0.85, 0.85, 0.92, 0.35), 5, 0.25, 1.2, 0.35, 0.03, Vector3(0, -0.1, 0))
	return root

class Fog extends Node3D:
	var layers: Array[GPUParticles3D] = []
	var base: MeshInstance3D
	var bmat: ShaderMaterial
	var lamp: OmniLight3D
	var censer: Node3D
	var r := 6.0
	var age := 0.0
	var ending := -1.0
	func setup(w: World, g: Vector3, radius: float, _dur: float, quality: int) -> void:
		r = radius
		var q := clampi(quality, 0, 3)
		if OS.has_feature("web"):
			q = mini(q, 1)
		var k: float = [0.55, 0.75, 1.0, 1.25][q]
		# ground roll: big flattened puffs hugging the floor
		layers.append(_layer(int(34 * k), 3.6, 5.2, 0.25, 0.12, PlagueFogFx.DEEP, 0.55, Vector3(0, 0.4, 0), 0.15))
		# the body: the cloud itself
		layers.append(_layer(int(46 * k), 3.0, 4.6, 0.9, 0.18, PlagueFogFx.COL, 0.42, Vector3(0, 1.2, 0), 0.3))
		# wisps curling off the top
		layers.append(_layer(int(22 * k), 1.6, 2.4, 1.8, 0.35, PlagueFogFx.COL.lightened(0.1), 0.22, Vector3(0, 2.1, 0), 0.6))
		# glints: glass dust catching the light
		var glint := Fx.aura(self, Color(0.95, 0.95, 1.0, 0.8), int(14 * k), 0.2, 0.018, 2.5, 0.05, radius * 0.7, 180.0, Vector3(0, 1.0, 0))
		glint.name = "glints"
		base = PlagueVialFx._ground_disc(w, g, radius * 1.1, 10, 48, 0.06)
		bmat = ShaderMaterial.new()
		bmat.shader = PlagueFogFx._base_shader()
		bmat.set_shader_parameter("spread", 0.0)
		bmat.set_shader_parameter("fade", 1.0)
		bmat.set_shader_parameter("col", PlagueFogFx.COL)
		bmat.set_shader_parameter("cloud", PlagueVialFx._tex(PlagueFogFx.BASE_TEX))
		base.material_override = bmat
		add_child(base)
		base.position = Vector3(0, -g.y, 0)
		lamp = OmniLight3D.new()
		lamp.light_color = Color(0.75, 0.75, 0.95)
		lamp.light_energy = 0.0
		lamp.omni_range = radius
		lamp.position = Vector3(0, 1.6, 0)
		add_child(lamp)
		# the censer dashed down at its heart: it hits, bounces once and lies there smoking
		if ResourceLoader.exists(PlagueFogFx.CENSER_GLB):
			censer = ResCache.inst(PlagueFogFx.CENSER_GLB)
			add_child(censer)
			for mi in censer.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			censer.rotation.y = randf() * TAU
			censer.position = Vector3(0, 0.7, 0)
			var tw := censer.create_tween()
			tw.tween_property(censer, "position", Vector3.ZERO, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(censer, "position", Vector3(0, 0.12, 0), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(censer, "position", Vector3.ZERO, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			var smoke := PlagueSmoke.vapour(censer, Color(0.86, 0.86, 0.93, 0.5), 7, 0.6, 1.8, 0.5, 0.06, Vector3(0, 0.15, 0))
			smoke.name = "smoke"
		# the burst as it hits: wisps of the fog-bank simulation thrown out level across the ground, and brass glints
		PlagueSmoke.puffs(self, g + Vector3(0, 0.3, 0), PlagueSmoke.WISP, Color(0.86, 0.86, 0.92, 0.6), 10, 3.2, 1.5, 6.0, 0.3, 0.0, 0.0, Vector3.UP, true)
		Fx.burst(self, g + Vector3(0, 0.3, 0), Plague.BRASS, 8, 3.0, 0.03, 0.4, true, -9.0)
	func _layer(n: int, smin: float, smax: float, rise: float, vel: float, col: Color, alpha: float, at: Vector3, life_k: float) -> GPUParticles3D:
		var p := GPUParticles3D.new()
		p.amount = maxi(n, 6)
		p.lifetime = 3.2 + life_k * 2.0
		p.preprocess = 0.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = 0.6
		pm.emission_ring_inner_radius = 0.0
		pm.emission_ring_height = 0.3 + at.y * 0.5
		pm.direction = Vector3.UP
		pm.spread = 80.0
		pm.initial_velocity_min = vel * 0.5
		pm.initial_velocity_max = vel * 1.5
		pm.gravity = Vector3(0.05, rise * 0.06, 0.03)
		pm.damping_min = 0.2
		pm.damping_max = 0.5
		pm.scale_min = smin
		pm.scale_max = smax
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -12.0
		pm.angular_velocity_max = 12.0
		var g := Gradient.new()
		g.set_color(0, Color(col.r, col.g, col.b, 0.0))
		g.add_point(0.15, Color(col.r, col.g, col.b, alpha))
		g.add_point(0.75, Color(col.r * 0.95, col.g * 0.95, col.b, alpha * 0.85))
		g.set_color(g.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		# each puff plays the fog-bank simulation over its life: a fluffy bank, then spreading out thin and soft into
		# its neighbours
		PlagueSmoke.anim(pm, true)
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		# lit by the scene (it takes the zone's dusk instead of glowing white in it)
		q.material = PlagueSmoke.mat(PlagueSmoke.WISP, true, col * 0.12)
		p.draw_pass_1 = q
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = at
		add_child(p)
		return p
	func end() -> void:
		if ending < 0.0:
			ending = 0.0
			for p in layers:
				p.emitting = false
			if censer != null:
				var smoke := censer.get_node_or_null("smoke") as GPUParticles3D
				if smoke != null:
					smoke.emitting = false
	func _process(delta: float) -> void:
		age += delta
		var roll := 1.0 - pow(1.0 - clampf(age / PlagueFogFx.ROLL_T, 0.0, 1.0), 3.0)
		# the emitters' reach grows as it billows out
		for p in layers:
			(p.process_material as ParticleProcessMaterial).emission_ring_radius = maxf(0.6, r * 0.8 * roll)
		var f := 1.0
		if ending >= 0.0:
			ending += delta
			f = clampf(1.0 - ending / 1.6, 0.0, 1.0)
			if censer != null and ending > 1.2:
				censer.scale = censer.scale.lerp(Vector3.ZERO, clampf(delta * 3.0, 0.0, 1.0))
			if ending > 4.0:
				queue_free()
				return
		bmat.set_shader_parameter("spread", roll * (0.4 + 0.6 * f))
		bmat.set_shader_parameter("fade", f)
		lamp.light_energy = 0.4 * roll * f

## A partner standing in a co-op partner's fog is drawn faded (in the Battlegrounds, enemies are hidden instead).
static func ghostly(rig: Node3D, on: bool) -> void:
	for mi in rig.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).transparency = 0.55 if on else 0.0

static var _bsh: Shader
## The fog's ground layer: the Meshy cloud painting (fog_base, blurred), two copies turning slowly through each other
## and drifting, edged by `spread` with a ragged rim, thinning as `fade` goes.
static func _base_shader() -> Shader:
	if _bsh != null:
		return _bsh
	_bsh = Shader.new()
	_bsh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;
uniform vec4 col : source_color;
uniform float spread = 1.0;
uniform float fade = 1.0;
uniform sampler2D cloud : source_color, filter_linear_mipmap;
varying vec2 lp;
vec2 turn(vec2 p, float a) { return vec2(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y); }
void vertex() { lp = UV * 2.0 - 1.0; }
void fragment() {
	float d = length(lp) * 1.1;
	// the painting's wisps, two copies turning against each other: tendrils crossing and churning, lit by the scene
	vec4 c1 = texture(cloud, turn(lp, TIME * 0.035) * 0.48 + 0.5);
	vec4 c2 = texture(cloud, turn(lp * 1.15, -TIME * 0.028 + 1.7) * 0.48 + 0.5 + vec2(sin(TIME * 0.11), cos(TIME * 0.09)) * 0.02);
	float n = clamp(c1.a * 0.65 + c2.a * 0.55, 0.0, 1.0);
	float edge = spread * (0.95 + (n - 0.5) * 0.3);
	float inside = smoothstep(edge, edge - 0.5, d);
	ALBEDO = col.rgb * (0.55 + 0.3 * n);
	ROUGHNESS = 1.0;
	EMISSION = col.rgb * 0.03 * n;
	ALPHA = inside * (0.08 + 0.28 * n) * fade;
}
"""
	return _bsh

# ---------------------------------------------------------------- the events (PlagueFx), on every game
## Fog of the Forgotten's events: "fog" {p, r, x: seconds} (the censer down and the fog billowing out), "reveal" (he
## struck from it: seen for a moment). Where each of his fogs is and when it lifts is kept here (`zones`, by the game's
## clock) on every game, a match server's too (`seen`), for who is hidden from whom (FogOfTheForgotten.hidden_from).
static func play(h: Hero, ev: Dictionary) -> bool:
	var node: Fog = null
	if str(ev["e"]) == "fog":
		var w: World = h.game.world
		var g: Vector3 = ev["p"]
		var r := float(ev.get("r", Skill.num("fog", "radius", 6.0)))
		node = Fog.new()
		w.fx_root.add_child(node)
		node.global_position = g
		node.setup(w, g, r, float(ev.get("x", Skill.num("fog", "secs", 6.0))), PlagueFx.quality(h))
		Sfx.play_at("impact_metal", g, -6.0, 0.6)
		Sfx.play_at("phase_erupt", g, -9.0, 1.3)
	return seen(h, ev, node)

## Where his fog is, and when he showed himself in it (on every game; a match server keeps only this).
static func seen(h: Hero, ev: Dictionary, node: Fog = null) -> bool:
	var st := PlagueFx.state(h)
	match str(ev["e"]):
		"fog":
			if not st.has("fogs"):
				st["fogs"] = []
			(st["fogs"] as Array).append({"pos": ev["p"], "r": float(ev.get("r", Skill.num("fog", "radius", 6.0))),
				"until": GameClock.now() + float(ev.get("x", Skill.num("fog", "secs", 6.0))), "node": node})
			st["fog_reveal"] = 0.0
		"reveal":
			st["fog_reveal"] = GameClock.now() + Skill.num("fog", "reveal_s", 1.0)
		_:
			return false
	return true

## Is `p` in one of his fogs as this game shows them, and is he not showing himself? (FogOfTheForgotten's hiding)
static func covers(h: Hero, p: Vector3) -> bool:
	if not h.has_meta("plague_fx"):
		return false
	var st := PlagueFx.state(h)
	var now := GameClock.now()
	if float(st.get("fog_reveal", 0.0)) > now:
		return false
	for f in st.get("fogs", []):
		var c: Vector3 = f["pos"]
		if float(f["until"]) > now and Vector2(p.x - c.x, p.z - c.z).length() < float(f["r"]) * 0.92:
			return true
	return false

## Each fog thins away when its time is up; a copy of him in it is hidden from this game's player (the
## Battlegrounds) or drawn faded (co-op).
static func update(h: Hero, st: Dictionary, _delta: float) -> void:
	var now := GameClock.now()
	for f in (st.get("fogs", []) as Array).duplicate():
		if float(f["until"]) <= now:
			(st["fogs"] as Array).erase(f)
			if f["node"] != null and is_instance_valid(f["node"]):
				(f["node"] as Fog).end()
	if not h.puppet or h.rig == null or h.game == null:
		return
	var hide := false
	var fade := false
	if covers(h, h.global_position):
		if h.game.bg_mode:
			hide = FogOfTheForgotten.hidden_from(h, h.game.hero)
		else:
			fade = true
	h.fog_hidden = hide       # Hero._puppet_process: the whole puppet (body, name tag, minimap dot) goes
	if h.rig.has_meta("fog_fade") != fade:
		if fade:
			h.rig.set_meta("fog_fade", true)
		else:
			h.rig.remove_meta("fog_fade")
		ghostly(h.rig, fade)

static func clear(h: Hero, st: Dictionary) -> void:
	for f in st.get("fogs", []):
		if f["node"] != null and is_instance_valid(f["node"]):
			(f["node"] as Node).queue_free()
	st.erase("fogs")
	st.erase("fog_reveal")
	h.fog_hidden = false
	if h.rig != null and is_instance_valid(h.rig) and h.rig.has_meta("fog_fade"):
		h.rig.remove_meta("fog_fade")
		ghostly(h.rig, false)
