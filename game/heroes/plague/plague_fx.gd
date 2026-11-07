class_name PlagueFx
extends RefCounted
## The Plague Doctor's effects (SkillFx events: Hero.fx; the rules are his skills', skills/): every game draws them,
## his own and his partners', on his hero or their copy of him, and nothing here deals, heals or sets a status.
## Each skill's look is its own script (skills/<skill>/plague_*_fx.gd), handed its events here; what lingers (a vial in
## the air, a pool, the swarm, a bloom, the fog, the apparatus, the vat) is kept in `state(h)`, moved by `update` and
## ended by its events or its own time. That state is not Hero.fxs: his pools and blooms outlive him, as his rules'
## do, so a death's SkillFx.clear leaves them; a class change or a new character ends them (Plague.clear -> `clear`).
## On a match server nothing is drawn (Enemy.server_nopose); only where his fog is (`PlagueFogFx.seen`) is kept, so
## its monsters lose him in it.
##  Pestilence Vial / Leech Jar: "throw"; Miasma: "miasma" (PlagueVialFx)
##  his poison, Blight and Fever on monsters (PlagueAffliction): "poisoned", "cured" {x: the marks too}, "blight"
##    {n: stacks}, "fever" {p, x: seconds} (the haze, PlagueSmoke; the marks, PlagueFever)
##  his cane: "cane" {n, p, d, t, r, x} (PlagueCane); Contagion: "curse", "spread", "burst"
##  Swarmcraft: PlagueSwarmFx; Corpse Bloom: PlagueBloomFx; Fog of the Forgotten: PlagueFogFx; Transfusion:
##    PlagueTransfusionFx; The Last Experiment: PlagueExperimentFx
## (The constants and pieces further down are an older visual pass's, kept for reference: nothing calls them.)

## This game's look of him: what his skills left lingering here (see above). A new zone starts it afresh (what was
## left went with the old zone's nodes).
static func state(h: Hero) -> Dictionary:
	var wid: int = h.game.world.get_instance_id() if h.game != null and h.game.world != null else 0
	if h.has_meta("plague_fx"):
		var st: Dictionary = h.get_meta("plague_fx")
		if int(st.get("world", wid)) == wid:
			return st
		_drop(h, st)
	var fresh := {"world": wid}
	h.set_meta("plague_fx", fresh)
	return fresh

static func play(h: Hero, ev: Dictionary) -> bool:
	var s := str(ev["s"])
	var e := str(ev["e"])
	if e == "cast":
		return false          # the default cast puff (SkillFx._default), as it always was
	if s == "attack":
		if e != "cane":
			return false      # the swing's own hit and finisher (SkillFx._common)
		if not Enemy.server_nopose:
			_cane(h, ev)
		return true
	if Enemy.server_nopose:
		if s == "fog":
			PlagueFogFx.seen(h, ev)
		return true
	var root: Node3D = h.game.world.fx_root
	match s:
		"toxic", "p_leech", "p_miasma":
			match e:
				"poisoned":
					for m in ev.get("t", []):
						_haze(m, true)
				"cured":
					for m in ev.get("t", []):
						_haze(m, false)
						if int(ev.get("x", 0)) > 0 and is_instance_valid(m):
							PlagueFever.stacks(m, 0)
				"blight":
					for m in ev.get("t", []):
						if is_instance_valid(m):
							PlagueFever.stacks(m, int(ev.get("n", 0)))
				"fever":
					for m in ev.get("t", []):
						if is_instance_valid(m):
							PlagueFever.stacks(m, 0)      # the marks are spent: they burst into the Fever
							PlagueFever.fever(m, float(ev.get("x", 4.0)))
					Sfx.play_at("blight_burst", ev.get("p", h.global_position), -6.0, 0.7)
				"throw":
					PlagueVialFx.throw(h, ev)
				"miasma":
					PlagueVialFx.miasma(h, ev)
				_:
					return false
		"p_spread":
			match e:
				"curse":
					var from: Vector3 = ev["p"]
					var to: Vector3 = ev["q"]
					Fx.bolt(root, from, to + Vector3(0, 1.0, 0), Plague.TOXIC, 0.3)
					Fx.burst(root, to + Vector3(0, 1.0, 0), Plague.TOXIC, 16, 2.5, 0.1, 0.5, true, -2.0)
					for m in ev.get("t", []):
						if is_instance_valid(m) and not m.has_node("pd_curse"):
							var a := PlagueSmoke.vapour(m, Color(0.62, 0.85, 0.22, 0.32), 6, 0.42, 1.1, 0.5, 0.3 * float(m.radius) + 0.15, Vector3(0, float(m.height) * 1.1, 0), Plague.TOXIC * 0.1)
							a.name = "pd_curse"
							Fx._free_later(a, float(ev.get("x", 6.0)))
					Sfx.play_at("curse_leap", to, -3.0)
				"spread":
					var p: Vector3 = ev["p"]
					for o in ev.get("t", []):
						if is_instance_valid(o):
							Fx.bolt(root, p + Vector3(0, 1.0, 0), o.global_position + Vector3(0, 1.0, 0), Plague.TOXIC, 0.2)
				"burst":
					Fx.burst(root, (ev["p"] as Vector3) + Vector3(0, 1.0, 0), Plague.TOXIC, 30, 4.0, 0.14, 0.7, true, -1.0)
				_:
					return false
		"swarm":
			return PlagueSwarmFx.play(h, ev)
		"bloom":
			return PlagueBloomFx.play(h, ev)
		"fog":
			return PlagueFogFx.play(h, ev)
		"transfusion":
			return PlagueTransfusionFx.play(h, ev)
		"experiment":
			return PlagueExperimentFx.play(h, ev)
		_:
			return false
	return true

## Every frame, on him and on every copy of him (SkillFx.update): what lingers moves on and ends.
static func update(h: Hero, delta: float) -> void:
	if not h.has_meta("plague_fx") or h.game == null or h.game.world == null:
		return
	var st := state(h)
	PlagueVialFx.update(h, st, delta)
	PlagueSwarmFx.update(h, st, delta)
	PlagueBloomFx.update(h, st, delta)
	PlagueFogFx.update(h, st, delta)
	PlagueExperimentFx.update(h, st, delta)
	for c in (st.get("clouds", []) as Array).duplicate():
		c["t"] = float(c["t"]) - delta
		if float(c["t"]) <= 0.0:
			(st["clouds"] as Array).erase(c)
			var n = c["node"]
			if is_instance_valid(n):
				for ch in (n as Node3D).get_children():
					if ch is GPUParticles3D:
						(ch as GPUParticles3D).emitting = false

## Everything of his here goes (a class change, a new character): the vials, pools, swarm, blooms, fog, apparatus,
## vat, what his hand holds, and the stand-ins other players struck.
static func clear(h: Hero) -> void:
	if h.has_meta("plague_fx"):
		_drop(h, h.get_meta("plague_fx"))
		h.remove_meta("plague_fx")

static func _drop(h: Hero, st: Dictionary) -> void:
	PlagueVialFx.clear(h, st)
	PlagueSwarmFx.clear(h, st)
	PlagueBloomFx.clear(h, st)
	PlagueFogFx.clear(h, st)
	PlagueTransfusionFx.clear(h, st)
	PlagueExperimentFx.clear(h, st)
	for c in st.get("clouds", []):
		if is_instance_valid(c["node"]):
			(c["node"] as Node).queue_free()
	var held = st.get("held")
	if held != null and is_instance_valid(held):
		(held as Node).queue_free()
	st.clear()

## A poisoned monster trails a thin green haze (the Mantaflow vapour; its own child: it goes when the monster does).
static func _haze(e, on: bool) -> void:
	if e == null or not is_instance_valid(e):
		return
	var f: Node = e.get_node_or_null("pd_poison")
	if on and f == null and not e.dead:
		var a := PlagueSmoke.vapour(e, Color(Plague.TOXIC.r, Plague.TOXIC.g, Plague.TOXIC.b, 0.4), 7, 0.55, 1.1, 0.45, 0.25 * float(e.radius) + 0.12, Vector3(0, float(e.height) * 0.9, 0), Plague.TOXIC * 0.15)
		a.name = "pd_poison"
	elif not on and f != null:
		e.remove_child(f)      # at once, so a haze put back this frame takes the name
		f.queue_free()

## His cane's marks: the peck's flecks on what it struck, the flick's fan of poison, the slam's cracked vial and
## its little cloud (a ring of fog particles that thins away when the rules' cloud ends).
static func _cane(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var fwd: Vector3 = ev.get("d", h.aim_dir())
	match int(ev.get("n", 0)):
		1:
			for e in ev.get("t", []):
				if is_instance_valid(e) and not e.dead:
					Fx.burst(root, e.global_position + Vector3(0, 1.1 * float(e.height), 0), Plague.TOXIC, 6, 1.6, 0.06, 0.4, true, -2.0)
		2:
			for k in 5:
				var d := fwd.rotated(Vector3.UP, (k - 2) * 0.32)
				Fx.burst(root, h.global_position + Vector3(0, 1.2, 0) + d * 0.7, Plague.TOXIC, 5, 4.5, 0.05, 0.45, true, -9.0, 8.0, d + Vector3(0, 0.25, 0))
			Sfx.play_at("drip", h.global_position, -6.0, 1.3)
		3:
			var at: Vector3 = ev["p"]
			Fx.burst(root, at + Vector3(0, 0.15, 0), Color(0.8, 1.0, 0.85), 10, 3.0, 0.04, 0.35, true, -9.0)
			Fx.burst(root, at + Vector3(0, 0.3, 0), Plague.TOXIC, 18, 2.5, 0.14, 0.6, true, 0.3, 70.0)
			Sfx.play_at("ice_shatter", at, -6.0, 1.5)
			var r := float(ev.get("r", PlagueCane.SLAM_R))
			var dur := float(ev.get("x", PlagueCane.SLAM_S))
			var node := Node3D.new()
			root.add_child(node)
			node.global_position = at
			var p := Fx.aura(node, Color(Plague.TOXIC.r * 0.6, Plague.TOXIC.g * 0.75, Plague.TOXIC.b * 0.45, 0.6), int(clampf(r * r * 6.0, 24.0, 120.0)), 0.3, 0.6, 1.6, 0.15, r * 0.8, 80.0, Vector3(0, 0.35, 0), false)
			p.name = "fog"
			Fx._free_later(node, dur + 2.0)
			var st := state(h)
			if not st.has("clouds"):
				st["clouds"] = []
			(st["clouds"] as Array).append({"node": node, "t": dur})

## The effect budget by the graphics preset (0 Low .. 3 Ultra; the browser build is capped at Medium).
static func quality(h: Hero) -> int:
	if h.game == null:
		return 1
	return int(h.game.get("quality")) if h.game.get("quality") != null else 1

## A player's stand-ins for his things only exist on other players' games in a match (PvpObjects.proxy decides).
static func proxy(h: Hero, oid: int, kind: String, at: Vector3) -> Enemy:
	if not h.puppet or oid <= 0:
		return null
	return PvpObjects.proxy(h.game, h, oid, kind, int(PvpObjects.HITS[kind]), at)

# ---------------------------------------------------------------- an older visual pass's pieces (unused)
const TOXIC := Color(0.45, 0.95, 0.25)
const MIASMA := Color(0.32, 0.6, 0.18)
const LIME := Color(0.7, 1.0, 0.3)
const GLASS := Color(0.8, 1.0, 0.86)
const BRASS := Color(0.85, 0.65, 0.3)
const GOO_DEEP := Color(0.07, 0.2, 0.04)
const FUME := Color(0.22, 0.36, 0.12)
const SPORE := Color(0.86, 1.0, 0.62)
const SOOT := Color(0.1, 0.085, 0.075)
const ALCH_DEEP := Color(0.55, 0.12, 0.02)
const ALCH_MOLTEN := Color(1.0, 0.52, 0.1)
const ALCH_HOT := Color(0.94, 1.0, 0.6)

static var _shaders := {}
static var _warm_world := 0

static func shader(key: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = {"glass": GLASS_SHADER, "drop": DROP_SHADER, "bubble": BUBBLE_SHADER, "splat": SPLAT_SHADER,
			"miasma": MIASMA_SHADER, "dome_rim": DOME_RIM_SHADER}[key]
		_shaders[key] = s
	return _shaders[key]

static func _mat(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(key)
	return m

static func _tier(root: Node3D) -> int:
	return InfernalFx.tier(root.get_tree().current_scene if root != null and root.is_inside_tree() else null)

static func _world(root: Node3D):
	var g = root.get_tree().current_scene if root != null and root.is_inside_tree() else null
	return g.world if g != null and "world" in g else null

## Compiles his shaders (and InfernalFx's flames and smoke) once per zone, so a first cast doesn't hitch.
static func warm(h: Hero) -> void:
	if h == null or not h.is_inside_tree() or h.game == null or h.game.world == null:
		return
	if _warm_world == h.game.world.get_instance_id():
		return
	_warm_world = h.game.world.get_instance_id()
	InfernalFx.warm(h.game.world.fx_root, h.game)
	for k in ["glass", "drop", "bubble", "splat", "miasma", "dome_rim"]:
		var mi := MeshInstance3D.new()
		mi.mesh = InfernalFx.quad()
		mi.material_override = _mat(k)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * 0.001
		h.game.world.fx_root.add_child(mi)
		mi.global_position = h.global_position + Vector3(0, 0.05, 0)
		Fx._free_later(mi, 0.3)

# ---------------------------------------------------------------- pieces
## A light popping and dying (no sprite): the glow of the poison or the fire on what's round it.
static func light(root: Node3D, pos: Vector3, col: Color, energy: float, life: float, reach: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, life).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)

## n slivers of a flask flung out of `at` (force scales how far), with glitter falling among them.
static func glass(root: Node3D, at: Vector3, n: int, force := 1.0, tint := GLASS) -> void:
	for i in n:
		var m := _mat("glass")
		m.set_shader_parameter("tint", tint)
		var mi := ElementalFx._piece(root, InfernalFx.shard_mesh(i), m, at + Vector3(randf_range(-0.1, 0.1), randf_range(0.0, 0.15), randf_range(-0.1, 0.1)), 1.4)
		var s := randf_range(0.05, 0.11)
		mi.scale = Vector3(s * randf_range(0.6, 1.0), s * randf_range(0.9, 1.7), s * 0.22)   # thin, like a curved sliver
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var a := randf() * TAU
		var v := Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 3.0) * force + Vector3(0, randf_range(1.8, 4.2) * force, 0)
		InfernalFx.fly(mi, v, Vector3(randf_range(-18, 18), randf_range(-14, 14), randf_range(-18, 18)), randf_range(0.45, 0.75), -15.0)
	InfernalFx.particles(root, at + Vector3(0, 0.25, 0), {"amount": n * 2, "life": 0.55, "explosive": 1.0, "shape": "sphere",
		"r": 0.12, "dir": Vector3.UP, "spread": 75.0, "vel": [1.4, 3.6 * force], "gravity": -13.0, "scale": [0.4, 1.0],
		"size": 0.035, "colors": [[0.0, Color(1, 1, 1)], [0.5, tint], [1.0, Color(tint, 0.0)]]})

## Glossy gobbets of liquid flung from `at` along dir (spread in degrees), falling on arcs.
static func gobbets(root: Node3D, at: Vector3, col: Color, amount: int, vel: Array, dir := Vector3.UP, spread := 70.0, size := 0.09) -> void:
	var m := _mat("drop")
	m.set_shader_parameter("deep", GOO_DEEP)
	InfernalFx.particles(root, at, {"amount": amount, "life": 0.8, "explosive": 1.0, "shape": "sphere", "r": 0.12,
		"dir": dir, "spread": spread, "vel": vel, "gravity": -12.0, "scale": [0.5, 1.2], "size": size, "mat": m,
		"colors": [[0.0, col], [0.8, col], [1.0, Color(col, 0.0)]]})

## A wet stain splashed over the ground round `at`: it runs out to radius r in a moment, glossy, with rays and drops
## past its edge, brightest just inside its rim, and soaks away over `life` seconds.
static func splat(root: Node3D, at: Vector3, r: float, col: Color, deep := GOO_DEEP, life := 2.4) -> void:
	var m := _mat("splat")
	m.set_shader_parameter("noise_tex", InfernalFx.noise())
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("deep", deep)
	m.set_shader_parameter("seed", randf() * 10.0)
	var mi := ElementalFx._piece(root, InfernalFx.disc_mesh(_world(root), at, r * 1.6, 32, 4, 0.065), m, at, life + 0.1)
	InfernalFx.tween_param(mi, m, "spread", 0.0, 1.0, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	InfernalFx.tween_param(mi, m, "life", 1.0, 0.0, life * 0.55, life * 0.45)

## Bubbles welling up off a stain of radius r, rising a little and popping.
static func bubbles(root: Node3D, at: Vector3, r: float, col: Color, amount: int, life := 1.6) -> void:
	var m := _mat("bubble")
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	q.material = m
	InfernalFx.particles(root, at + Vector3(0, 0.08, 0), {"amount": amount, "life": 0.7, "explosive": 0.0, "one_shot": true,
		"shape": "ring", "r": r * 0.7, "r_in": 0.05, "dir": Vector3.UP, "spread": 10.0, "vel": [0.15, 0.45], "gravity": 0.0,
		"scale": [0.5, 1.3], "grow": [0.2, 1.3], "mesh": q,
		"colors": [[0.0, Color(col, 0.0)], [0.15, Color(col, 0.9)], [0.85, Color(col, 0.9)], [1.0, Color(col, 0.0)]]})
	# keep it welling for `life` seconds: a one-shot system restarted on a timer is cheaper than a looping one left on
	var tw := root.create_tween()
	for k in int(life / 0.7):
		tw.tween_interval(0.7)
		tw.tween_callback(func():
			if is_instance_valid(root):
				InfernalFx.particles(root, at + Vector3(0, 0.08, 0), {"amount": maxi(1, amount / 2), "life": 0.7, "explosive": 0.0,
					"shape": "ring", "r": r * 0.7, "r_in": 0.05, "dir": Vector3.UP, "spread": 10.0, "vel": [0.15, 0.45],
					"scale": [0.5, 1.3], "grow": [0.2, 1.3], "mesh": q,
					"colors": [[0.0, Color(col, 0.0)], [0.15, Color(col, 0.9)], [0.85, Color(col, 0.9)], [1.0, Color(col, 0.0)]]}))

## The poison's gas: rolling, noise-eroded fumes (d: InfernalFx.particles keys; size, peak alpha a).
static func fumes(root: Node3D, at: Vector3, size: float, a: float, d: Dictionary, col := FUME) -> void:
	ElementalFx._dust(root, at, col, size, a, d)

## Pale spores of the contagion drifting off a body, slow, some turning in the air.
static func spores(root: Node3D, at: Vector3, amount: int, reach := 0.8) -> void:
	InfernalFx.particles(root, at, {"amount": amount, "life": 1.3, "explosive": 0.6, "shape": "sphere", "r": 0.3,
		"dir": Vector3.UP, "spread": 120.0, "vel": [0.2, reach], "gravity": 0.15, "damping": [0.4, 0.8], "turb": 0.4,
		"scale": [0.5, 1.2], "size": 0.06, "colors": [[0.0, Color(SPORE, 0.0)], [0.2, SPORE], [0.7, Color(LIME, 0.6)], [1.0, Color(LIME, 0.0)]]})

## A poison cloud of radius r hanging over the ground round `at` (its nodes go under `root`, which sits at `at`):
## layers of rolling miasma that follow the terrain (MIASMA_SHADER: domain-warped noise, darker where it is dense,
## the curls' crests catching the colour, a ragged edge with tendrils creeping past it), noise-eroded fumes rolling
## up off it and spores drifting in it. It fades in; miasma_end thins it away. (It was ~400 soft round sprites.)
static func miasma(root: Node3D, at: Vector3, r: float, col: Color) -> void:
	var tr := _tier(root)
	var w = _world(root)
	# [disc radius, height over the ground, peak alpha, drift speed, noise scale (1/m)]: a dense ground layer, and
	# from Medium up a thinner one at knee height that drifts faster, so the fog has depth round the legs in it
	var layers := [[r * 1.25, 0.06, 0.72, 1.0, 0.11]]
	if tr >= 1:
		layers.append([r * 1.1, 0.6, 0.34, 1.7, 0.075])
	for i in layers.size():
		var ly: Array = layers[i]
		var m := _mat("miasma")
		m.set_shader_parameter("noise_tex", InfernalFx.noise())
		m.set_shader_parameter("col", Color(col.r * 0.62, col.g * 0.72, col.b * 0.42))
		m.set_shader_parameter("deep", Color(col.r * 0.14, col.g * 0.24, col.b * 0.1))
		m.set_shader_parameter("density", ly[2])
		m.set_shader_parameter("speed", ly[3])
		m.set_shader_parameter("scale", ly[4])
		m.set_shader_parameter("seed", randf() * 10.0)
		m.set_shader_parameter("fade", 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = InfernalFx.disc_mesh(w, at, ly[0], 40 if i == 0 else 32, 6 if i == 0 else 4, ly[1])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "miasma%d" % i
		root.add_child(mi)
		InfernalFx.tween_param(mi, m, "fade", 0.0, 1.0, 0.45).set_ease(Tween.EASE_OUT)
	var vis := AABB(Vector3(-r - 2.0, -1.0, -r - 2.0), Vector3(r * 2.0 + 4.0, 6.0, r * 2.0 + 4.0))
	if tr >= 1:
		var fu := ElementalFx._dust(root, at + Vector3(0, 0.3, 0), Color(col.r * 0.42, col.g * 0.55, col.b * 0.28),
			clampf(r * 0.55, 1.4, 2.6), 0.38, {"amount": maxi(4, int(clampf(r * r * 1.0, 8.0, 60.0) * [0.0, 0.6, 0.85, 1.0][tr])),
			"life": 3.0, "one_shot": false, "explosive": 0.0, "shape": "ring", "r": r * 0.75, "r_in": 0.0, "dir": Vector3.UP,
			"spread": 60.0, "vel": [0.1, 0.3], "gravity": 0.06, "damping": [0.1, 0.3], "scale": [0.8, 1.3], "grow": [0.6, 1.6],
			"spin": 10.0})
		fu.visibility_aabb = vis
	var sp := InfernalFx.particles(root, at + Vector3(0, 0.3, 0), {"amount": maxi(3, int(clampf(r * 4.0, 6.0, 40.0) * [0.4, 0.6, 0.85, 1.0][tr])),
		"life": 2.4, "one_shot": false, "explosive": 0.0, "shape": "ring", "r": r * 0.85, "r_in": 0.0, "dir": Vector3.UP,
		"spread": 30.0, "vel": [0.1, 0.35], "gravity": 0.05, "damping": [0.2, 0.4], "turb": 0.3, "scale": [0.4, 1.0], "size": 0.05,
		"colors": [[0.0, Color(SPORE, 0.0)], [0.25, Color(SPORE, 0.8)], [0.75, Color(LIME, 0.5)], [1.0, Color(LIME, 0.0)]]})
	sp.visibility_aabb = vis

## The cloud thinning away over t seconds: its miasma and its light fade, its fumes and spores stop. Safe to call twice.
static func miasma_end(root: Node3D, t := 0.7) -> void:
	if root == null or not is_instance_valid(root) or root.has_meta("miasma_end"):
		return
	root.set_meta("miasma_end", true)
	for ch in root.get_children():
		if ch is GPUParticles3D:
			(ch as GPUParticles3D).emitting = false
		elif ch is MeshInstance3D and String(ch.name).begins_with("miasma"):
			var m := (ch as MeshInstance3D).material_override as ShaderMaterial
			if m != null:
				InfernalFx.tween_param(ch, m, "fade", float(m.get_shader_parameter("fade")), 0.0, t)
		elif ch is OmniLight3D:
			ch.create_tween().tween_property(ch, "light_energy", 0.0, t)

## The Last Epidemic's foot: a band of sickly light round the dome where it meets the ground (noise-broken, flowing
## round), in place of a flat green torus. Named "edge" so the collapse takes it away with the shell.
static func dome_rim(root: Node3D, at: Vector3, r: float, col: Color) -> MeshInstance3D:
	var m := _mat("dome_rim")
	m.set_shader_parameter("noise_tex", InfernalFx.noise())
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("fade", 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = InfernalFx.wedge_mesh(_world(root), at, 0.0, maxf(r - 0.7, 0.1), r + 0.3, PI, 72, 2, 0.08)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "edge"
	root.add_child(mi)
	InfernalFx.tween_param(mi, m, "fade", 0.0, 1.0, 0.5).set_ease(Tween.EASE_OUT)
	return mi

## Alchemist's fire: InfernalFx's flame, orange at the skin, green-white at the heart.
static func alch_flame_mat(dark := 0.65, heat := 1.25) -> ShaderMaterial:
	var m := InfernalFx.flame_mat(dark, heat, 1.3)
	m.set_shader_parameter("crimson", ALCH_DEEP)
	m.set_shader_parameter("molten", ALCH_MOLTEN)
	m.set_shader_parameter("whitehot", ALCH_HOT)
	return m

## n alchemist's flames standing on a ring (or scattered over a disc when inner is 0) round pos, licking up and dying.
static func alch_flames(root: Node3D, pos: Vector3, r: float, n: int, h0: float, h1: float, life: float, inner := 0.85) -> void:
	var w = _world(root)
	for i in n:
		var a := TAU * (float(i) + randf_range(-0.3, 0.3)) / n
		var at := pos + Vector3(cos(a), 0, sin(a)) * r * randf_range(inner, 1.05)
		if w != null:
			at.y = w.height_at(at.x, at.z)
		var hh := randf_range(h0, h1)
		var m := alch_flame_mat()
		var f := InfernalFx.flame(root, at + Vector3(0, hh * 0.42, 0), Vector2(hh * 0.55, hh), m)
		f.scale = Vector3(hh * 0.55, hh * 0.15, 1.0)
		var d0 := randf_range(0.0, 0.08)
		var tw := f.create_tween()
		tw.tween_interval(d0)
		tw.tween_property(f, "scale", Vector3(hh * 0.55, hh, 1.0), 0.12).set_ease(Tween.EASE_OUT)
		InfernalFx.tween_param(f, m, "alpha", 1.0, 0.0, life * 0.6, d0 + life * 0.4)
		Fx._free_later(f, d0 + life + 0.1)

static func _sparks(root: Node3D, at: Vector3, amount: int, vel: Array) -> void:
	InfernalFx.particles(root, at, {"amount": amount, "life": 0.9, "explosive": 1.0, "shape": "sphere", "r": 0.25,
		"dir": Vector3.UP, "spread": 80.0, "vel": vel, "gravity": -7.0, "damping": [0.5, 1.2], "scale": [0.3, 0.9],
		"size": 0.07, "colors": [[0.0, Color(1.0, 1.0, 0.85)], [0.3, ALCH_MOLTEN], [1.0, Color(ALCH_DEEP, 0.0)]]})

# ---------------------------------------------------------------- the skills' moments
## Crow's Peck on a foe: a spit of poison and a breath of fumes off him.
static func peck(root: Node3D, pos: Vector3) -> void:
	var tr := _tier(root)
	gobbets(root, pos, TOXIC, [3, 4, 6, 8][tr], [0.8, 2.0], Vector3.UP, 80.0, 0.07)
	fumes(root, pos, 0.7, 0.5, {"amount": [2, 3, 4, 5][tr], "life": 0.9, "explosive": 0.9, "shape": "sphere", "r": 0.15,
		"dir": Vector3.UP, "spread": 60.0, "vel": [0.2, 0.6], "damping": [1.0, 1.5], "scale": [0.7, 1.1], "grow": [0.5, 1.4]})

## Vial Flick: drops flung across the swing from his hand (o) out along each of the fan's directions.
static func flick(root: Node3D, o: Vector3, dirs: Array) -> void:
	var tr := _tier(root)
	for d in dirs:
		var dv: Vector3 = d
		gobbets(root, o + dv * 0.5, TOXIC, [3, 4, 5, 7][tr], [3.5, 5.5], (dv + Vector3(0, 0.3, 0)).normalized(), 9.0, 0.08)

## Censer Slam's cracked vial: glass, a splash and a small stain, a puff of gas.
static func vial_crack(root: Node3D, at: Vector3) -> void:
	var tr := _tier(root)
	glass(root, at + Vector3(0, 0.1, 0), [5, 7, 9, 12][tr], 0.8)
	gobbets(root, at + Vector3(0, 0.2, 0), TOXIC, [5, 8, 11, 14][tr], [1.5, 3.2])
	splat(root, at, 0.9, TOXIC, GOO_DEEP, 2.0)
	fumes(root, at + Vector3(0, 0.25, 0), 1.0, 0.55, {"amount": [3, 4, 6, 8][tr], "life": 1.2, "explosive": 0.9,
		"shape": "sphere", "r": 0.3, "dir": Vector3.UP, "spread": 70.0, "vel": [0.4, 1.0], "damping": [1.0, 1.6],
		"scale": [0.7, 1.2], "grow": [0.5, 1.6]})
	light(root, at + Vector3(0, 0.5, 0), TOXIC, 2.0, 0.3, 3.0)

## Toxic Flask breaking where it lands: the flask's glass, the splash, the stain with bubbles, the green light.
static func flask_burst(root: Node3D, at: Vector3, r: float) -> void:
	var tr := _tier(root)
	glass(root, at + Vector3(0, 0.15, 0), [7, 10, 13, 16][tr], 1.1)
	gobbets(root, at + Vector3(0, 0.2, 0), TOXIC, [8, 12, 16, 22][tr], [2.0, 4.5], Vector3.UP, 65.0, 0.1)
	splat(root, at, r * 0.55, TOXIC, GOO_DEEP, 3.0)
	bubbles(root, at, r * 0.5, LIME, [3, 5, 7, 9][tr], 2.1)
	light(root, at + Vector3(0, 0.6, 0), TOXIC, 3.0, 0.35, r * 1.6)

## Volatile Mixture going off: a ball of alchemist's fire with a ring of flames, sparks, the bottle's glass, soot
## rolling up, the air rippling out and a burning stain left on the ground.
static func volatile_blast(root: Node3D, at: Vector3, r: float) -> void:
	var tr := _tier(root)
	var game = root.get_tree().current_scene if root.is_inside_tree() else null
	alch_flames(root, at, r * 0.55, [6, 8, 11, 14][tr], 0.9, 1.8, 0.75)
	alch_flames(root, at, r * 0.2, [2, 3, 4, 5][tr], 1.4, 2.4, 0.6, 0.0)
	var g := InfernalFx.glow(root, at + Vector3(0, 0.9, 0), 2.2, InfernalFx.glow_mat(ALCH_MOLTEN, 2.8, 2.0, 0.8))
	var tg := g.create_tween()
	tg.set_parallel(true)
	tg.tween_property(g, "scale", Vector3.ONE * 3.6, 0.3).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, g.material_override as ShaderMaterial, "alpha", 1.0, 0.0, 0.32)
	Fx._free_later(g, 0.36)
	_sparks(root, at + Vector3(0, 0.4, 0), [14, 22, 32, 44][tr], [4.0, 9.0])
	glass(root, at + Vector3(0, 0.2, 0), [5, 7, 9, 12][tr], 1.5, Color(0.95, 0.75, 0.5))
	fumes(root, at + Vector3(0, 0.6, 0), 1.9, 0.8, {"amount": [5, 7, 10, 14][tr], "life": 2.0, "explosive": 0.8,
		"shape": "sphere", "r": 0.6, "dir": Vector3.UP, "spread": 35.0, "vel": [1.2, 2.6], "gravity": 0.4,
		"damping": [0.8, 1.3], "scale": [0.8, 1.4], "grow": [0.5, 1.8], "spin": 20.0}, SOOT)
	splat(root, at, r * 0.5, ALCH_MOLTEN, Color(0.04, 0.025, 0.02), 2.2)
	if game != null:
		HolyFx.shockwave(root, game, at, r * 1.1, 0.35, 0.02)
	light(root, at + Vector3(0, 1.0, 0), ALCH_MOLTEN, 8.0, 0.45, 9.0)

## Ignition: a poison cloud the blast reached going up all at once, flames running over it.
static func cloud_ignites(root: Node3D, cp: Vector3, r: float) -> void:
	var tr := _tier(root)
	alch_flames(root, cp, r * 0.8, [5, 7, 10, 13][tr], 0.8, 1.6, 0.8, 0.0)
	_sparks(root, cp + Vector3(0, 0.5, 0), [8, 12, 18, 24][tr], [2.0, 5.0])
	fumes(root, cp + Vector3(0, 0.8, 0), 1.6, 0.7, {"amount": [4, 6, 8, 11][tr], "life": 1.6, "explosive": 0.7,
		"shape": "sphere", "r": r * 0.5, "dir": Vector3.UP, "spread": 30.0, "vel": [1.0, 2.0], "gravity": 0.3,
		"damping": [0.8, 1.2], "scale": [0.8, 1.3], "grow": [0.5, 1.6]}, SOOT)
	light(root, cp + Vector3(0, 0.8, 0), Color(1.0, 0.7, 0.2), 5.0, 0.35, r * 2.0)

## A foe catching the contagion: a cough of spores and a sickly puff round him.
static func infect(root: Node3D, pos: Vector3) -> void:
	var tr := _tier(root)
	spores(root, pos, [5, 7, 10, 14][tr], 0.9)
	fumes(root, pos, 0.8, 0.45, {"amount": [2, 3, 4, 5][tr], "life": 1.1, "explosive": 0.8, "shape": "sphere", "r": 0.25,
		"dir": Vector3.UP, "spread": 90.0, "vel": [0.2, 0.5], "damping": [0.8, 1.2], "scale": [0.7, 1.1], "grow": [0.6, 1.5]},
		Color(0.3, 0.45, 0.15))

## A Pestilent Trap set: its brass teeth clack shut, a little dust kicked up, a glint.
static func trap_set(root: Node3D, at: Vector3) -> void:
	InfernalFx.particles(root, at + Vector3(0, 0.12, 0), {"amount": 6, "life": 0.35, "explosive": 1.0, "shape": "sphere",
		"r": 0.15, "dir": Vector3.UP, "spread": 60.0, "vel": [0.8, 1.8], "gravity": -9.0, "scale": [0.4, 0.9], "size": 0.04,
		"colors": [[0.0, Color(1.0, 0.95, 0.8)], [1.0, Color(BRASS, 0.0)]]})
	fumes(root, at + Vector3(0, 0.1, 0), 0.7, 0.35, {"amount": 3, "life": 0.8, "explosive": 1.0, "shape": "ring", "r": 0.35,
		"r_in": 0.2, "dir": Vector3.UP, "spread": 20.0, "vel": [0.1, 0.3], "radial": [1.0, 2.0], "damping": [2.0, 3.0],
		"scale": [0.6, 1.0], "grow": [0.5, 1.3]}, ElementalFx.DUST_DARK)

## A trap sprung: a jet of gas hissing straight up out of it, then spilling outward; spray and a green light.
static func trap_burst(root: Node3D, pos: Vector3, r: float) -> void:
	var tr := _tier(root)
	fumes(root, pos + Vector3(0, 0.2, 0), 1.0, 0.75, {"amount": [5, 7, 10, 13][tr], "life": 1.0, "explosive": 0.85,
		"shape": "sphere", "r": 0.15, "dir": Vector3.UP, "spread": 12.0, "vel": [3.5, 6.0], "gravity": -1.0,
		"damping": [2.0, 3.0], "scale": [0.6, 1.0], "grow": [0.4, 1.8], "spin": 30.0})
	fumes(root, pos + Vector3(0, 0.2, 0), 1.3, 0.6, {"amount": [4, 6, 8, 11][tr], "life": 1.6, "explosive": 0.7,
		"shape": "ring", "r": 0.4, "r_in": 0.2, "dir": Vector3.UP, "spread": 25.0, "vel": [0.2, 0.6], "radial": [r * 1.2, r * 2.0],
		"damping": [1.8, 2.6], "scale": [0.8, 1.3], "grow": [0.5, 1.7], "spin": 15.0})
	gobbets(root, pos + Vector3(0, 0.25, 0), TOXIC, [6, 9, 12, 16][tr], [2.5, 5.5], Vector3.UP, 30.0, 0.07)
	light(root, pos + Vector3(0, 0.6, 0), TOXIC, 4.0, 0.3, 5.0)

## A wave of contagion rolling out over the ground to radius r (an Outbreak, the dome's pulse).
static func wave(root: Node3D, pos: Vector3, r: float, col := LIME) -> void:
	var tr := _tier(root)
	fumes(root, pos + Vector3(0, 0.25, 0), 1.2, 0.5, {"amount": [8, 12, 16, 22][tr], "life": 1.3, "explosive": 0.95,
		"shape": "ring", "r": 0.6, "r_in": 0.3, "dir": Vector3.UP, "spread": 15.0, "vel": [0.2, 0.5], "radial": [r * 2.6, r * 3.4],
		"damping": [2.6, 3.4], "scale": [0.8, 1.3], "grow": [0.6, 1.7], "spin": 15.0}, Color(col.r * 0.45, col.g * 0.55, col.b * 0.3))
	spores(root, pos + Vector3(0, 0.6, 0), [6, 9, 13, 18][tr], 1.4)

## The Last Epidemic's censer smashed: brass flung out, the poison splashed wide, a wave of gas rolling to the edge
## of the dome, a deep green light.
static func censer_smash(root: Node3D, g: Vector3, r: float) -> void:
	var tr := _tier(root)
	glass(root, g + Vector3(0, 0.2, 0), [5, 7, 9, 12][tr], 1.2, BRASS)
	gobbets(root, g + Vector3(0, 0.3, 0), TOXIC, [12, 18, 26, 34][tr], [3.0, 7.0], Vector3.UP, 70.0, 0.11)
	splat(root, g, 1.6, TOXIC, GOO_DEEP, 3.5)
	bubbles(root, g, 1.2, LIME, [4, 6, 8, 10][tr], 3.0)
	wave(root, g, r * 0.9, MIASMA)
	light(root, g + Vector3(0, 1.0, 0), TOXIC, 9.0, 0.5, r * 1.5)

## The dome collapsing: its gas rushing in to the middle, then blown up and out in a last cough of spores.
static func collapse(root: Node3D, g: Vector3, r: float) -> void:
	var tr := _tier(root)
	fumes(root, g + Vector3(0, 0.4, 0), 1.6, 0.65, {"amount": [10, 14, 20, 26][tr], "life": 0.7, "explosive": 1.0,
		"shape": "ring", "r": r * 0.85, "r_in": r * 0.6, "dir": Vector3.UP, "spread": 10.0, "vel": [0.2, 0.5],
		"radial": [-r * 4.0, -r * 3.0], "damping": [0.5, 1.0], "scale": [0.8, 1.3], "grow": [1.4, 0.4], "spin": 25.0}, MIASMA * 0.6)
	var tw := root.create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(func():
		if not is_instance_valid(root):
			return
		fumes(root, g + Vector3(0, 0.6, 0), 2.0, 0.7, {"amount": [6, 9, 12, 16][tr], "life": 1.6, "explosive": 0.9,
			"shape": "sphere", "r": 0.8, "dir": Vector3.UP, "spread": 25.0, "vel": [2.5, 5.0], "gravity": -0.5,
			"damping": [1.2, 1.8], "scale": [0.8, 1.4], "grow": [0.6, 1.8], "spin": 20.0})
		spores(root, g + Vector3(0, 1.2, 0), [10, 16, 22, 30][tr], 2.4)
		light(root, g + Vector3(0, 1.0, 0), TOXIC, 7.0, 0.4, r * 1.4))

# ---------------------------------------------------------------- shaders
## A sliver of glass (on InfernalFx.shard_mesh): nearly clear, glossy, its edges catching the light.
const GLASS_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;
uniform vec3 tint : source_color = vec3(0.8, 1.0, 0.86);
uniform float alpha = 1.0;
void fragment() {
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = tint * 0.25;
	ROUGHNESS = 0.04;
	SPECULAR = 1.0;
	EMISSION = tint * (0.12 + f * 1.1);
	ALPHA = clamp((0.25 + f * 0.75) * alpha, 0.0, 1.0);
}
"""

## A gobbet of liquid (a camera-facing particle): shaded like a little sphere, a highlight, glowing faintly at its rim.
const DROP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 deep : source_color = vec3(0.07, 0.2, 0.04);
uniform float glow = 0.6;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	float d = length(c);
	if (d > 1.0) { discard; }
	float z = sqrt(max(1.0 - d * d, 0.0));
	vec3 n = vec3(c.x, -c.y, z);
	vec3 l = normalize(vec3(-0.4, 0.6, 0.7));
	float lit = clamp(dot(n, l), 0.0, 1.0);
	float spec = pow(clamp(dot(reflect(-l, n), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 24.0);
	vec3 col = mix(deep, COLOR.rgb, 0.3 + 0.7 * lit) + vec3(spec) * 0.9 + COLOR.rgb * glow * (1.0 - z) * 0.6;
	ALBEDO = col;
	ALPHA = clamp(COLOR.a * smoothstep(1.0, 0.82, d), 0.0, 1.0);
}
"""

## A bubble (camera-facing particle): see-through, a bright thin rim and a window highlight.
const BUBBLE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	float d = length(c);
	if (d > 1.0) { discard; }
	float rim = smoothstep(0.62, 0.9, d) * (1.0 - smoothstep(0.92, 1.0, d));
	float hl = smoothstep(0.24, 0.0, length(c - vec2(-0.35, 0.35)));
	ALBEDO = COLOR.rgb * (0.5 + rim) + vec3(hl);
	ALPHA = clamp((rim * 0.85 + hl * 0.9 + 0.08 * (1.0 - d)) * COLOR.a, 0.0, 1.0);
}
"""

## A splash of liquid on the ground (InfernalFx.disc_mesh: UV centre 0.5, rim 0.5 out): a ragged pool with rays and
## drops past its edge that runs out (spread 0..1), wet and glossy, glowing just inside its rim; soaks away (life 1..0).
const SPLAT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 col : source_color = vec4(0.45, 0.95, 0.25, 1.0);
uniform vec4 deep : source_color = vec4(0.07, 0.2, 0.04, 1.0);
uniform float spread = 0.0;
uniform float life = 1.0;
uniform float seed = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float a = atan(d.y, d.x);
	float n = texture(noise_tex, UV * 1.8 + vec2(seed, 0.0)).r;
	float n2 = texture(noise_tex, UV * 7.0 + vec2(0.3, seed)).r;
	float rays = pow(abs(sin(a * 6.0 + seed * 3.0 + n * 4.0)), 16.0);
	float edge = (0.5 + (n - 0.5) * 0.3 + rays * 0.42) * spread;
	float pool = smoothstep(edge + 0.015, edge - 0.04, r);
	float drops = smoothstep(0.76, 0.84, n2) * step(edge, r) * smoothstep(edge * 1.45 + 0.02, edge, r);
	float m = max(pool, drops);
	float rim = pool * (1.0 - smoothstep(0.0, 0.16, edge - r));
	float wet = 0.35 + 0.4 * n2;
	ALBEDO = mix(deep.rgb, col.rgb * 0.7, wet);
	ROUGHNESS = 0.08;
	SPECULAR = 0.85;
	EMISSION = col.rgb * (0.06 + 0.5 * rim + 0.1 * drops) * life;
	ALPHA = clamp(m * 0.88 * life * smoothstep(1.0, 0.9, r), 0.0, 1.0);
}
"""

## A layer of a poison cloud's fog (on InfernalFx.disc_mesh: UV centre 0.5, rim 0.5 out): domain-warped noise laid in
## world space (scale per metre), rolling slowly; darker where it is dense, the crests of its curls catching the
## colour; a ragged edge at 0.8 of the disc with thin tendrils creeping past it. fade 0..1 brings it in and out.
const MIASMA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 col : source_color = vec4(0.34, 0.85, 0.14, 1.0);
uniform vec4 deep : source_color = vec4(0.07, 0.28, 0.03, 1.0);
uniform float density = 0.75;
uniform float speed = 1.0;
uniform float scale = 0.11;
uniform float seed = 0.0;
uniform float fade = 0.0;
varying vec2 wxz;
void vertex() { wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float t = TIME * 0.03 * speed;
	vec2 p = wxz * scale + vec2(seed, seed * 0.7);
	// blurred lookups (mip levels), a gentle warp: gas is soft at hand's breadth, its shapes a metre or two across
	vec2 q = vec2(textureLod(noise_tex, p * 0.5 + vec2(t, -t * 0.7), 2.5).r,
		textureLod(noise_tex, p * 0.5 + vec2(5.2 - t * 0.6, 1.3 + t), 2.5).r) - 0.5;
	float n = textureLod(noise_tex, p * 0.55 + q * 0.3 + vec2(t * 0.4, t * 0.25), 2.0).r;
	float n2 = textureLod(noise_tex, p * 1.3 + q * 0.2 - vec2(t * 1.1, t * 0.5), 1.5).r;
	float dens = n * 0.65 + n2 * 0.35;
	float edge = 0.8 + (n - 0.5) * 0.4;
	float body = smoothstep(edge, edge - 0.5, r);
	float fog = body * (0.35 + 0.65 * smoothstep(0.25, 0.75, dens + (0.8 - r) * 0.2));
	float tendril = smoothstep(0.55, 0.75, n2) * smoothstep(1.0, 0.75, r) * (1.0 - body);
	float a = max(fog, tendril * 0.3);
	ALBEDO = mix(deep.rgb, col.rgb, 0.3 + 0.4 * smoothstep(0.3, 0.8, dens));
	ALPHA = clamp(a * density * fade, 0.0, 1.0);
}
"""

## The Last Epidemic's foot (on InfernalFx.wedge_mesh round the full circle: UV.x round it, UV.y out across the band):
## a band of sickly light, brightest a little inside the dome's edge, broken by noise that flows slowly round.
const DOME_RIM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 col : source_color = vec4(0.55, 1.0, 0.25, 1.0);
uniform float fade = 0.0;
void fragment() {
	float t = TIME * 0.04;
	float n = texture(noise_tex, vec2(UV.x * 7.0 + t, UV.y * 0.5 - t * 0.6)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 23.0 - t * 2.0, UV.y * 1.3 + t)).r;
	float band = smoothstep(0.0, 0.62, UV.y) * smoothstep(1.0, 0.66, UV.y);
	float a = band * (0.3 + 0.7 * smoothstep(0.3, 0.72, n)) * (0.75 + 0.5 * n2);
	ALBEDO = col.rgb * (0.7 + 0.6 * band);
	ALPHA = clamp(a * 0.6 * fade, 0.0, 1.0);
}
"""
