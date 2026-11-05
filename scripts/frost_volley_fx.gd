class_name FrostVolleyFx
extends RefCounted
## Frost Volley's look (jj's remake, 2026-11-04). Draws only: ArcherFx plays its events and Archer._rain calls `strike`
## for every arrow that falls, on the archer's own game and on his puppet's alike, so partners see the same storm; the
## damage and the chill stay in archer.gd. Its stages:
##  - the draw (`draw`, every frame of the shot, from ArcherFx.update): he leans back and aims high (the rig's "sky"
##    meta, KnightMocapRig._shot_body), pulls a glacier arrow from the quiver instead of a war arrow, rime creeps over
##    it and cold vapour falls off the bow, a cold light on his hands;
##  - the release (`release`, the "impact" event): a fan of glacier arrows streaks up out of the bow, each shedding
##    frost mist and glints as it climbs, a burst of frost off the bow;
##  - the storm (`update`, from STORM_AT): hoarfrost spreads over the ground out to the radius with a bright edge (the
##    Meshy-painted hoarfrost, GROUND_SHADER), freezing fog pools over it (the "rime" Mantaflow book), snow and glints
##    fall through a cold light;
##  - the rain (`strike`): each glacier arrow drops on a slant with a mist streak, sticks in the ground and bursts in a
##    puff of cold mist (the "frost" book) and ice splinters; some strikes burst a Meshy ice-crystal cluster up out of
##    the ground; foes under it frost over (`frost_body`: rime crawling up from the feet on Enemy's rest overlay, cold
##    vapour falling off them; one that dies frozen shatters);
##  - the end (`update`, SHATTER_AT after the rain): every crystal breaks into its Blender-fractured pieces and every
##    arrow into glints, at once, with a crash of ice; the frost thaws from the edges in.
## Counts follow InfernalFx.tier (Low / web: fewer of everything). Models: assets/models/arrows/frost.glb (Meshy,
## concept "glacier arrow"), assets/models/fx/frost/crystal.glb and crystal_pieces.glb (Meshy, prep_prop.py,
## trim_below.py, fracture_rock.py); books: tools/blender/fx/smoke_flipbook.py frost | rime (DemonKitFx.BOOKS).

const CRYSTAL := "res://assets/models/fx/frost/crystal.glb"
const CRYSTAL_PIECES := "res://assets/models/fx/frost/crystal_pieces.glb"
const HOARFROST := "res://assets/textures/fx/frost/hoarfrost.png"
const PALE := Color(0.82, 0.94, 1.0)
const DEEP := Color(0.25, 0.55, 0.95)
const MIST := Color(0.72, 0.82, 0.92)
## seconds after the release: the storm gathers, the rain ends (Archer: the volley's 1.3 s from its first tick at
## 0.25 s), everything shatters, the frost is gone
const STORM_AT := 0.2
const RAIN_END := 1.55
const SHATTER_AT := 1.95
const THAW := 3.2
const UP_SPEED := 30.0
const FALL_T := 0.24
const MAX_STUCK := 26
const CRYSTAL_GAP := 1.15

static var _shaders := {}
static var _tex: Texture2D
static var _bodies := {}
static var _body_frame := -1

static func shader(key: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = {"ground": GROUND_SHADER, "streak": STREAK_SHADER, "rim": RIM_SHADER, "body": BODY_SHADER}[key]
		_shaders[key] = s
	return _shaders[key]

static func hoarfrost() -> Texture2D:
	if _tex == null and ResourceLoader.exists(HOARFROST):
		_tex = load(HOARFROST)
	return _tex

static func _mat(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(key)
	return m

static func _tier(h: Hero) -> int:
	return InfernalFx.tier(h.game)

# ---------------------------------------------------------------- the glacier arrow
## The Meshy glacier arrow with a cold rim of light over it (the model is ice already: no tint).
static func arrow(glow := 1.0) -> Node3D:
	var n := Archer._arrow_mesh("frost", true)
	var rim := _mat("rim")
	rim.set_shader_parameter("col", PALE)
	rim.set_shader_parameter("glow", glow)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = rim
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.set_meta("rim", rim)
	return n

## A mist streak behind something flying along `axis`: a camera-facing strip `length` long, its head at the node.
static func streak(parent: Node3D, axis: Vector3, length: float, width: float, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, length)
	q.center_offset = Vector3(0, -length * 0.5, 0)
	mi.mesh = q
	var m := _mat("streak")
	m.set_shader_parameter("axis", axis.normalized())
	m.set_shader_parameter("col", PALE)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("noise_tex", InfernalFx.noise())
	m.set_shader_parameter("seed", randf() * 10.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = length
	parent.add_child(mi)
	mi.top_level = true
	return mi

static func _aim_streak(s: MeshInstance3D, at: Vector3, axis: Vector3) -> void:
	if is_instance_valid(s):
		s.global_transform = Transform3D(Basis(), at)
		(s.material_override as ShaderMaterial).set_shader_parameter("axis", axis.normalized())

# ---------------------------------------------------------------- the draw
## A volley's shot on its way (ArcherFx.update; `a` = the attack's progress, also on the puppet): the glacier arrow on
## the string and in his hand from the quiver, rime creeping over it with the draw, cold vapour falling, the cold
## light on his hands, and the rig told to aim high.
static func draw(h: Hero, a: float) -> void:
	if h.rig != null:
		h.rig.set_meta("sky", 1.0)
	var w: Node3D = h.weapon_node
	if w == null or not is_instance_valid(w) or not w.has_meta("nocked"):
		return
	var k := clampf((a - Archer.GRAB) / (Anim.impact_at("bow") - 0.06 - Archer.GRAB), 0.0, 1.0)
	for key in ["nocked", "hand"]:
		var ar: Node3D = w.get_meta("nocked") if key == "nocked" else w.get_node_or_null("HandArrow")
		if ar != null:
			_glacier_on(ar, true, k)
	var nocked: Node3D = w.get_meta("nocked")
	var ch := nocked.get_node_or_null("FrostCharge") as Node3D
	if ch == null:
		ch = Node3D.new()
		ch.name = "FrostCharge"
		ch.position = Vector3(0, 0, -0.3)
		nocked.add_child(ch)
		var tr := _tier(h)
		# cold vapour spilling off the head and falling
		var mist := ElementalFx._dust(ch, ch.global_position, MIST, 0.22, 0.32, {"one_shot": false, "amount": [3, 5, 7, 9][tr],
			"life": 0.9, "explosive": 0.0, "shape": "sphere", "r": 0.05, "dir": Vector3.DOWN, "spread": 30.0, "vel": [0.05, 0.2],
			"gravity": -0.6, "damping": [0.4, 0.8], "scale": [0.6, 1.1], "grow": [0.5, 1.6]})
		mist.name = "Mist"
		# glints of frost forming on it
		var gl := InfernalFx.particles(ch, ch.global_position, {"one_shot": false, "amount": [3, 4, 6, 8][tr], "life": 0.5,
			"explosive": 0.0, "shape": "sphere", "r": 0.1, "dir": Vector3.UP, "spread": 180.0, "vel": [0.0, 0.1],
			"gravity": 0.0, "scale": [0.4, 1.0], "size": 0.012,
			"colors": [[0.0, Color(PALE, 0)], [0.3, Color(1.2, 1.3, 1.45)], [1.0, Color(PALE, 0)]]})
		gl.name = "Glints"
		var lt := OmniLight3D.new()
		lt.name = "Light"
		lt.light_color = PALE
		lt.omni_range = 2.4
		lt.shadow_enabled = false
		lt.position = Vector3(0, 0.12, 0)
		ch.add_child(lt)
	ch.visible = nocked.visible
	(ch.get_node("Mist") as GPUParticles3D).amount_ratio = 0.3 + 0.7 * k
	(ch.get_node("Light") as OmniLight3D).light_energy = (0.25 + 0.9 * k) * (0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.02))

## Swaps an arrow on the bow (or in his hand) for the glacier arrow (`on`), the rime on it `k` 0..1, or back.
static func _glacier_on(ar: Node3D, on: bool, k := 0.0) -> void:
	var g := ar.get_node_or_null("Glacier") as Node3D
	if g == null:
		if not on:
			return
		g = arrow(0.4)
		g.name = "Glacier"
		g.scale = Vector3.ONE * 0.9
		ar.add_child(g)
	for c in ar.get_children():
		if c is Node3D and c != g and c.name != "FrostCharge" and c.name != "Charge":
			(c as Node3D).visible = not on
	g.visible = on
	if on and g.has_meta("rim"):
		(g.get_meta("rim") as ShaderMaterial).set_shader_parameter("glow", 0.35 + 1.1 * k)

## The shot is over (or wasn't a volley): the war arrow back on the string, the rig upright again.
static func end_draw(h: Hero) -> void:
	if h.rig != null and h.rig.has_meta("sky"):
		h.rig.set_meta("sky", 0.0)
	var w: Node3D = h.weapon_node
	if w == null or not is_instance_valid(w) or not w.has_meta("nocked"):
		return
	var nocked: Node3D = w.get_meta("nocked")
	_glacier_on(nocked, false)
	var hand := w.get_node_or_null("HandArrow") as Node3D
	if hand != null:
		_glacier_on(hand, false)
	var ch := nocked.get_node_or_null("FrostCharge")
	if ch != null:
		ch.queue_free()

# ---------------------------------------------------------------- the release
## The "impact" event: the flight going up out of the bow, the burst of frost off it; the storm over `g` (radius r)
## starts from here (state in h.fxs["frost_volleys"], run by `update`).
static func release(h: Hero, g: Vector3, r: float) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := _tier(h)
	var from: Vector3 = h.global_position + Vector3(0, 1.55, 0)
	var J: Dictionary = h.rig.get_meta("j") if h.rig != null and h.rig.has_meta("j") else {}
	if J.has("at_hand_l"):
		from = (J["at_hand_l"] as Node3D).global_position
	var flat := (g - h.global_position) * Vector3(1, 0, 1)
	var fwd := flat.normalized() if flat.length() > 0.2 else h.facing()
	var side := fwd.cross(Vector3.UP).normalized()
	# the fan of glacier arrows climbing steeply toward the mark
	var n: int = [4, 5, 7, 7][tr]
	for i in n:
		var f := (float(i) - (n - 1) * 0.5) / maxf(1.0, (n - 1) * 0.5)
		var d := (fwd * cos(deg_to_rad(64.0 + randf_range(-4.0, 4.0))) + Vector3.UP * sin(deg_to_rad(64.0))).normalized()
		d = d.rotated(Vector3.UP, f * deg_to_rad(13.0)) + side * randf_range(-0.03, 0.03)
		_climb(h, root, from + side * f * 0.1, d.normalized(), randf_range(0.0, 0.07), tr)
	# frost blown off the bow, glints, a cold flash
	Fx.flash(root, from, PALE, 2.4, 0.3, 4.5)
	InfernalFx.particles(root, from, {"amount": [6, 9, 14, 20][tr], "life": 0.55, "explosive": 1.0, "shape": "sphere",
		"r": 0.08, "dir": (fwd + Vector3.UP * 1.6).normalized(), "spread": 40.0, "vel": [2.0, 5.0], "gravity": -6.0,
		"damping": [1.0, 2.0], "scale": [0.4, 1.0], "size": 0.016,
		"colors": [[0.0, Color(1.2, 1.3, 1.45)], [0.5, PALE], [1.0, Color(DEEP, 0)]]})
	ElementalFx._dust(root, from, MIST, 0.34, 0.2, {"amount": [2, 3, 4, 5][tr], "life": 1.1, "explosive": 1.0,
		"shape": "sphere", "r": 0.1, "dir": Vector3.DOWN, "spread": 60.0, "vel": [0.2, 0.6], "gravity": -0.8,
		"damping": [1.5, 2.5], "scale": [0.7, 1.2], "grow": [0.6, 1.8]})
	SkillFx.snd(h, "frost_loose", -3.0, randf_range(0.97, 1.03))
	SkillFx.shake(h, 0.08)
	var vs: Array = h.fxs.get("frost_volleys", [])
	vs.append({"g": g, "r": r, "t": 0.0, "fwd": fwd, "stage": 0, "crystals": [], "stuck": [], "strikes": 0})
	h.fxs["frost_volleys"] = vs

## One glacier arrow climbing out of the bow: its streak and its trail of mist and glints, gone into the sky.
static func _climb(h: Hero, root: Node3D, from: Vector3, d: Vector3, delay: float, tr: int) -> void:
	var ar := arrow(1.2)
	root.add_child(ar)
	ar.global_position = from
	ar.look_at(from + d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)
	ar.visible = delay <= 0.0
	var sk := streak(ar, d, 2.4, 0.09, 0.32)
	sk.visible = ar.visible
	var trail := ElementalFx._dust(ar, from, MIST, 0.28, 0.2, {"one_shot": false, "amount": [6, 8, 12, 16][tr], "life": 0.9,
		"explosive": 0.0, "shape": "sphere", "r": 0.04, "dir": -d, "spread": 25.0, "vel": [0.1, 0.4], "gravity": -0.4,
		"damping": [1.0, 2.0], "scale": [0.6, 1.0], "grow": [0.5, 1.9]})
	var glints := InfernalFx.particles(ar, from, {"one_shot": false, "amount": [6, 10, 14, 20][tr], "life": 0.5,
		"explosive": 0.0, "shape": "sphere", "r": 0.05, "dir": -d, "spread": 30.0, "vel": [0.3, 1.0], "gravity": -2.0,
		"scale": [0.4, 1.0], "size": 0.014, "colors": [[0.0, Color(1.2, 1.3, 1.45)], [1.0, Color(PALE, 0)]]})
	trail.emitting = ar.visible
	glints.emitting = ar.visible
	var life := 0.5
	var tw := ar.create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(ar):
			return
		var on := t >= 0.0
		ar.visible = on
		sk.visible = on
		trail.emitting = on
		glints.emitting = on
		var p := from + d * UP_SPEED * maxf(t, 0.0)
		ar.global_position = p
		_aim_streak(sk, p, d), -delay, life, life + delay)
	tw.tween_callback(func():
		# the trail is left to drift and fade in the air, never cut off
		for e in [trail, glints]:
			if is_instance_valid(e):
				var gp: Vector3 = (e as Node3D).global_position
				ar.remove_child(e)
				root.add_child(e)
				(e as Node3D).global_position = gp
				(e as GPUParticles3D).emitting = false
				Fx._free_later(e, 1.2)
		ar.queue_free())

# ---------------------------------------------------------------- the rain
## One arrow of the rain (Archer._rain, on every game): it drops onto p on a slant from the archer's side, sticks in,
## and the strike bursts in mist and splinters; some strikes grow a crystal cluster. `v` is the volley (h.volleys).
static func strike(h: Hero, p: Vector3) -> void:
	var st := _volley_at(h, p)
	if st.is_empty():
		return
	var root: Node3D = h.game.world.fx_root
	var tr := _tier(h)
	var fwd: Vector3 = st["fwd"]
	var d := (fwd * randf_range(0.35, 0.55) + Vector3(randf_range(-0.12, 0.12), -1.0, randf_range(-0.12, 0.12))).normalized()
	var top := p - d * 10.0
	# one of the six, never the same one twice running
	var last: int = int(st.get("last_kind", -1))
	var ki := randi() % RAIN.size()
	if ki == last:
		ki = (ki + 1 + randi() % (RAIN.size() - 1)) % RAIN.size()
	st["last_kind"] = ki
	var k: Dictionary = RAIN[ki]
	var col: Color = k["col"]
	var ar := rain_arrow(k)
	root.add_child(ar)
	ar.global_position = top
	var aim := Basis.looking_at(d, Vector3.UP)
	ar.global_transform = Transform3D(aim, top)
	var sk := streak(ar, d, float(k["trail"]), float(k["width"]), 0.5)
	(sk.material_override as ShaderMaterial).set_shader_parameter("col", col)
	# what it sheds as it falls: glints and wisps in its own colour, left in the air
	var shed: GPUParticles3D = null
	if tr >= 1:
		shed = InfernalFx.particles(ar, top, {"one_shot": false, "amount": [0, 5, 8, 12][tr], "life": 0.45, "explosive": 0.0,
			"shape": "sphere", "r": 0.06, "dir": -d, "spread": 35.0, "vel": [0.4, 1.4], "gravity": -1.5, "scale": [0.4, 1.0],
			"size": 0.016, "colors": [[0.0, Color(col.r * 1.4, col.g * 1.4, col.b * 1.5)], [1.0, Color(col, 0.0)]]})
	var delay := randf_range(0.0, 0.17)
	var spin: float = float(k["spin"]) * (1.0 if randf() < 0.5 else -1.0)
	ar.visible = false
	sk.visible = false
	if shed != null:
		shed.emitting = false
	var tw := ar.create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(ar):
			return
		var on := t >= 0.0
		ar.visible = on
		sk.visible = on
		if shed != null:
			shed.emitting = on
		var q := top.lerp(p, clampf(t / FALL_T, 0.0, 1.0))
		# turning on its own axis as it falls
		ar.global_transform = Transform3D(aim * Basis(Vector3.BACK, spin * maxf(t, 0.0)), q)
		_aim_streak(sk, q, d), -delay, FALL_T, FALL_T + delay)
	tw.tween_callback(func():
		if not is_instance_valid(ar):
			return
		sk.queue_free()
		if shed != null and is_instance_valid(shed):
			var gp := shed.global_position
			ar.remove_child(shed)
			root.add_child(shed)
			shed.global_position = gp
			shed.emitting = false
			Fx._free_later(shed, 0.8)
		# in to a third of its length, at the angle it fell
		ar.global_position = p + d * 0.28 * float(k["scale"])
		ar.set_meta("col", col)
		_land(h, st, p, ar))

## The rain's arrows (jj: "each arrow unique and visually stunning"): six Meshy ice arrows (concepts in
## exports/frost_volley/rain), each lit from inside by its own ice (its albedo's blues glow), with its own cold rim,
## streak, trail and spin.
const RAIN_GLB := "res://assets/models/arrows/rain/%s.glb"
const RAIN := [
	{"id": "spear", "col": Color(0.62, 0.85, 1.0), "glow": 0.5, "spin": 7.0, "trail": 2.4, "width": 0.1, "scale": 1.25},
	{"id": "icicle", "col": Color(0.85, 0.95, 1.0), "glow": 0.45, "spin": 3.0, "trail": 2.0, "width": 0.08, "scale": 1.3},
	{"id": "runic", "col": Color(0.55, 0.78, 1.0), "glow": 0.75, "spin": 11.0, "trail": 2.2, "width": 0.09, "scale": 1.2},
	{"id": "shard", "col": Color(0.5, 0.68, 1.0), "glow": 0.55, "spin": 4.0, "trail": 1.8, "width": 0.11, "scale": 1.3},
	{"id": "snowflake", "col": Color(0.75, 0.95, 1.0), "glow": 0.7, "spin": 14.0, "trail": 2.6, "width": 0.08, "scale": 1.2},
	{"id": "wraith", "col": Color(0.5, 0.95, 0.95), "glow": 0.7, "spin": 6.0, "trail": 2.3, "width": 0.09, "scale": 1.25},
]

static func rain_arrow(k: Dictionary) -> Node3D:
	var n := DemonKitFx.model(RAIN_GLB % str(k["id"]))
	if n == null:
		return arrow(1.0)
	var col: Color = k["col"]
	DemonKitFx.heat_model(n, float(k["glow"]), col)
	var rim := _mat("rim")
	rim.set_shader_parameter("col", col)
	rim.set_shader_parameter("glow", 1.3)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = rim
	n.set_meta("rim", rim)
	var root := Node3D.new()
	root.add_child(n)
	n.scale = Vector3.ONE * float(k["scale"])
	root.set_meta("rim", rim)
	return root

static func _land(h: Hero, st: Dictionary, p: Vector3, ar: Node3D) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := _tier(h)
	st["strikes"] = int(st["strikes"]) + 1
	var stuck: Array = st["stuck"]
	stuck.append(ar)
	while stuck.size() > MAX_STUCK:
		var old = stuck.pop_front()
		if is_instance_valid(old):
			_glints(root, (old as Node3D).global_position, 4)
			(old as Node3D).queue_free()
	if ar.has_meta("rim"):
		InfernalFx.tween_param(ar, ar.get_meta("rim"), "glow", 2.2, 0.6, 0.4)
	# a puff of cold mist rolling out from the strike (every other one on the lower tiers)
	if tr >= 2 or int(st["strikes"]) % 2 == 0:
		DemonKitFx.smoke(root, p, "frost", randf_range(1.0, 1.45), randf_range(0.8, 1.0), false, Color(0.62, 0.7, 0.8))
	# ice splinters and frost dust thrown up
	var kc: Color = ar.get_meta("col", PALE)
	InfernalFx.particles(root, p + Vector3(0, 0.08, 0), {"amount": [4, 6, 8, 11][tr], "life": 0.5, "explosive": 1.0,
		"shape": "sphere", "r": 0.06, "dir": Vector3.UP, "spread": 65.0, "vel": [1.5, 3.4], "gravity": -13.0,
		"scale": [0.4, 1.0], "size": 0.022, "colors": [[0.0, Color(1, 1, 1)], [0.6, kc], [1.0, Color(DEEP, 0.0)]]})
	_glints(root, p + Vector3(0, 0.2, 0), [2, 3, 4, 6][tr])
	# some strikes burst a crystal cluster up out of the frost (kept apart, a few per volley)
	var crystals: Array = st["crystals"]
	var cap: int = [3, 5, 8, 10][tr]
	if crystals.size() < cap and randf() < 0.5:
		var clear := true
		for c in crystals:
			if (c["at"] as Vector3).distance_to(p) < CRYSTAL_GAP:
				clear = false
				break
		if clear and (p * Vector3(1, 0, 1)).distance_to(st["g"] * Vector3(1, 0, 1)) < float(st["r"]) * 0.95:
			var cn := _crystal(root, p, randf_range(0.6, 1.1), tr)
			if cn != null:
				crystals.append({"n": cn, "at": p})
	# the cold light over the storm flickers with the strike
	var lt = st.get("light")
	if is_instance_valid(lt):
		st["flick"] = 1.0
	Sfx.play_at("ice_arrow_hit", p, -7.0, randf_range(0.9, 1.12))
	GrassField.impulse(p, 0.7, 0.35, 0.25)
	# what is under it frosts over (on every game: cosmetic; the chill itself is archer.gd's)
	for e in h.game.enemies_near(p, 1.4):
		if not e.dead:
			frost_body(h.game, e, 2.6)

## A Meshy ice-crystal cluster bursting up out of the ground at p, `s` metres tall: grows with an overshoot, its blue
## lit from inside (the albedo's own blues glow) and a cold rim.
static func _crystal(root: Node3D, p: Vector3, s: float, tr: int) -> Node3D:
	var n := DemonKitFx.model(CRYSTAL)
	if n == null:
		return null
	DemonKitFx.heat_model(n, 0.9, Color(0.45, 0.75, 1.0))
	var rim := _mat("rim")
	rim.set_shader_parameter("col", PALE)
	rim.set_shader_parameter("glow", 1.6)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_overlay = rim
		for i in m.get_surface_override_material_count():
			var c = m.get_surface_override_material(i)
			if c is StandardMaterial3D:
				(c as StandardMaterial3D).roughness = 0.12
				(c as StandardMaterial3D).metallic_specular = 0.9
	n.set_meta("rim", rim)
	root.add_child(n)
	n.global_position = p + Vector3(0, -0.06 * s, 0)
	n.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
	n.set_meta("s", s)
	n.scale = Vector3.ONE * 0.02
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * s, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	InfernalFx.tween_param(n, rim, "glow", 3.0, 1.2, 0.5)
	# the ground bursts round its foot
	ElementalFx._dust(root, p + Vector3(0, 0.1, 0), MIST, 0.6 * s + 0.3, 0.4, {"amount": [2, 3, 4, 5][tr], "life": 0.9,
		"explosive": 1.0, "shape": "ring", "r": 0.25 * s, "r_in": 0.1, "dir": Vector3.UP, "spread": 20.0, "vel": [0.2, 0.5],
		"radial": [1.0, 2.0], "damping": [2.0, 3.0], "scale": [0.7, 1.1], "grow": [0.5, 1.5]})
	return n

static func _glints(root: Node3D, at: Vector3, n: int) -> void:
	InfernalFx.particles(root, at, {"amount": n, "life": 0.7, "explosive": 0.8, "shape": "sphere", "r": 0.25,
		"dir": Vector3.UP, "spread": 90.0, "vel": [0.2, 0.9], "gravity": -0.6, "scale": [0.4, 1.0], "size": 0.016,
		"colors": [[0.0, Color(PALE, 0)], [0.2, Color(1.2, 1.35, 1.5)], [0.5, Color(PALE, 0.4)], [0.7, Color(1.2, 1.35, 1.5)], [1.0, Color(DEEP, 0)]]})

## The volley this strike belongs to: the nearest storm still raining.
static func _volley_at(h: Hero, p: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for st in h.fxs.get("frost_volleys", []):
		var d: float = (st["g"] as Vector3).distance_to(p)
		if int(st["stage"]) < 2 and d < bd:
			bd = d
			best = st
	return best

# ---------------------------------------------------------------- shaders compiled before the first cast
static var _warm_world := 0

## Compiles the volley's shaders and loads its models once per zone (the first volley hitched ~0.5 s): a speck of
## each material drawn under the archer for a moment, the crystal and its pieces loaded, the books' textures read.
static func warm(h: Hero) -> void:
	if h.game == null or h.game.world == null or not h.is_inside_tree():
		return
	var wid: int = h.game.world.get_instance_id()
	if _warm_world == wid:
		return
	_warm_world = wid
	var root: Node3D = h.game.world.fx_root
	DemonKitFx.piece_set(CRYSTAL_PIECES)
	hoarfrost()
	for key in ["ground", "streak", "rim", "body"]:
		var mi := MeshInstance3D.new()
		mi.mesh = InfernalFx.quad()
		var m := _mat(key)
		m.set_shader_parameter("noise_tex", InfernalFx.noise())
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * 0.001
		root.add_child(mi)
		mi.global_position = h.global_position + Vector3(0, 0.05, 0)
		Fx._free_later(mi, 0.3)
	var c := DemonKitFx.model(CRYSTAL)
	if c != null:
		root.add_child(c)
		c.scale = Vector3.ONE * 0.001
		c.global_position = h.global_position
		Fx._free_later(c, 0.3)
	var arrows: Array = [arrow()]
	for k in RAIN:
		arrows.append(rain_arrow(k))
	for ar in arrows:
		root.add_child(ar)
		(ar as Node3D).scale = Vector3.ONE * 0.001
		(ar as Node3D).global_position = h.global_position
		Fx._free_later(ar, 0.3)
	for k in ["frost", "rime"]:
		var sm := DemonKitFx.smoke(root, h.global_position + Vector3(0, -2, 0), k, 0.01, 0.25)
		if is_instance_valid(sm):
			sm.scale = Vector3.ONE * 0.01

# ---------------------------------------------------------------- the storm, every frame
## Runs every volley (ArcherFx.update, the caster's and the puppet's): the frost spreading, the fog, the snow and the
## light; then the shatter and the thaw. And the frost on foes.
static func update(h: Hero, delta: float) -> void:
	_bodies_update(h.game, delta)
	if h.is_archer() and not h.puppet:
		warm(h)
	if not h.fxs.has("frost_volleys"):
		return
	var vs: Array = h.fxs["frost_volleys"]
	for st in vs.duplicate():
		st["t"] = float(st["t"]) + delta
		var t: float = st["t"]
		if int(st["stage"]) == 0 and t >= STORM_AT:
			st["stage"] = 1
			_storm(h, st)
		if int(st["stage"]) == 1:
			# every foe under the storm frosts over while it rains (the chill reaches them all: archer.gd)
			st["frost_tick"] = float(st.get("frost_tick", 0.0)) - delta
			if float(st["frost_tick"]) <= 0.0 and t < RAIN_END:
				st["frost_tick"] = 0.25
				for e in h.game.enemies_near(st["g"], float(st["r"])):
					if not e.dead:
						frost_body(h.game, e, 2.2)
			var lt = st.get("light")
			if is_instance_valid(lt):
				st["flick"] = maxf(0.0, float(st.get("flick", 0.0)) - delta * 6.0)
				var up := smoothstep(STORM_AT, STORM_AT + 0.4, t)
				(lt as OmniLight3D).light_energy = (0.9 + 1.3 * float(st["flick"])) * up
		if int(st["stage"]) == 1 and t >= SHATTER_AT:
			st["stage"] = 2
			_shatter(h, st)
		if int(st["stage"]) == 2 and t >= SHATTER_AT + THAW + 0.3:
			vs.erase(st)
	if vs.is_empty():
		h.fxs.erase("frost_volleys")

## The storm gathers over the mark: hoarfrost racing out over the ground, freezing fog pooling, snow and glints falling
## through a cold light.
static func _storm(h: Hero, st: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var w = h.game.world
	var tr := _tier(h)
	var g: Vector3 = st["g"]
	var r: float = st["r"]
	var gm := _mat("ground")
	gm.set_shader_parameter("hoar", hoarfrost())
	gm.set_shader_parameter("noise_tex", InfernalFx.noise())
	gm.set_shader_parameter("pale", PALE)
	gm.set_shader_parameter("deep", DEEP)
	gm.set_shader_parameter("seed", randf() * 10.0)
	gm.set_shader_parameter("tile", maxf(1.0, r * 0.55))
	var ground := ElementalFx._piece(root, InfernalFx.disc_mesh(w, g, r * 1.12, 48, 8, 0.06), gm, g, SHATTER_AT + THAW + 1.0)
	InfernalFx.tween_param(ground, gm, "front", 0.0, 1.0, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	st["ground"] = ground
	st["gmat"] = gm
	# freezing fog pooled over it (looping until the thaw)
	st["fog"] = DemonKitFx.smoke(root, g, "rime", r * 2.3, 4.0, true, Color(0.7, 0.78, 0.88))
	var fog: MeshInstance3D = st["fog"]
	if is_instance_valid(fog):
		var fm: ShaderMaterial = fog.material_override
		InfernalFx.tween_param(fog, fm, "fade", 0.0, 0.7, 0.6)
	# snow and glints falling through the storm
	var snow := InfernalFx.particles(root, g + Vector3(0, 6.5, 0), {"one_shot": false, "amount": [18, 30, 48, 70][tr],
		"life": 1.9, "explosive": 0.0, "shape": "box", "box": Vector3(r * 0.85, 0.3, r * 0.85), "dir": Vector3.DOWN,
		"spread": 12.0, "vel": [2.5, 4.0], "gravity": -1.5, "scale": [0.4, 1.0], "size": 0.045, "turb": 0.5,
		"colors": [[0.0, Color(1, 1, 1, 0)], [0.15, Color(1.1, 1.15, 1.2)], [0.85, PALE], [1.0, Color(PALE, 0)]]})
	snow.visibility_aabb = AABB(Vector3(-r, -8, -r), Vector3(r * 2.0, 9, r * 2.0))
	st["snow"] = snow
	# the cold light over it (one per volley; the strikes make it flicker)
	var lt := OmniLight3D.new()
	lt.light_color = Color(0.62, 0.8, 1.0)
	lt.light_energy = 0.0
	lt.omni_range = r * 2.4
	lt.shadow_enabled = false
	root.add_child(lt)
	lt.global_position = g + Vector3(0, 3.2, 0)
	st["light"] = lt
	Sfx.play_at("arrow_rain", g, -5.0, randf_range(0.96, 1.04))
	Sfx.play_at("frost_spread", g, -6.0, 1.0)
	GrassField.impulse(g, r, 0.35, 0.5)

## The end: every crystal breaks into its pieces, every stuck arrow into glints, at once; a crash of ice, a flash, a
## ring of mist; the fog lifts, the snow stops, the frost begins to thaw.
static func _shatter(h: Hero, st: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var w = h.game.world
	var tr := _tier(h)
	var g: Vector3 = st["g"]
	var r: float = st["r"]
	for c in st["crystals"]:
		var n = c["n"]
		if is_instance_valid(n):
			_break(root, w, n as Node3D, tr)
	for ar in st["stuck"]:
		if is_instance_valid(ar):
			_glints(root, (ar as Node3D).global_position, [2, 3, 4, 5][tr])
			InfernalFx.particles(root, (ar as Node3D).global_position, {"amount": [2, 3, 4, 6][tr], "life": 0.5,
				"explosive": 1.0, "shape": "sphere", "r": 0.15, "dir": Vector3.UP, "spread": 70.0, "vel": [1.0, 2.4],
				"gravity": -12.0, "scale": [0.4, 0.9], "size": 0.04, "colors": [[0.0, PALE], [1.0, Color(DEEP, 0.0)]]})
			(ar as Node3D).queue_free()
	st["stuck"] = []
	st["crystals"] = []
	DemonKitFx.smoke(root, g, "frost", r * 0.95, 1.3, false, Color(0.55, 0.62, 0.72))
	Fx.flash(root, g + Vector3(0, 1.5, 0), PALE, 4.0, 0.45, r * 2.2)
	Sfx.play_at("ice_burst", g, -2.0, randf_range(0.97, 1.03))
	SkillFx.shake(h, 0.12)
	GrassField.impulse(g, r, 0.5, 0.4)
	var fog = st.get("fog")
	if is_instance_valid(fog):
		DemonKitFx.smoke_out(fog, 2.2)
	var snow = st.get("snow")
	if is_instance_valid(snow):
		(snow as GPUParticles3D).emitting = false
		Fx._free_later(snow, 2.2)
	var lt = st.get("light")
	if is_instance_valid(lt):
		var tw := (lt as Node).create_tween()
		tw.tween_property(lt, "light_energy", 0.0, 0.9)
		tw.tween_callback((lt as Node).queue_free)
	var ground = st.get("ground")
	if is_instance_valid(ground):
		InfernalFx.tween_param(ground, st["gmat"], "thaw", 0.0, 1.0, THAW).set_ease(Tween.EASE_IN_OUT)

## One crystal cluster breaking: its Voronoi pieces (fracture_rock.py) thrown out from where they sat, glinting, the
## break's faces frosted white; ice dust where it stood.
static func _break(root: Node3D, w, n: Node3D, tr: int, pieces := CRYSTAL_PIECES) -> void:
	var set := DemonKitFx.piece_set(pieces)
	var base := n.global_position
	var xf := n.global_transform
	var centre := Vector3.ZERO
	var src := n.find_children("*", "MeshInstance3D", true, false)
	if not src.is_empty():
		centre = ((src[0] as MeshInstance3D).mesh as Mesh).get_aabb().get_center()
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.85, 0.93, 1.0)
	inner.roughness = 0.35
	inner.emission_enabled = true
	inner.emission = Color(0.5, 0.75, 1.0)
	inner.emission_energy_multiplier = 0.8
	var s: float = float(n.get_meta("s", 0.6))
	var keep: int = [4, 7, 11, 99][tr]
	for i in mini(set.size(), keep):
		var pc: Dictionary = set[i]
		var mi := MeshInstance3D.new()
		mi.mesh = pc["mesh"]
		var mats: Array = pc["mats"]
		for j in mats.size():
			var mt = mats[j]
			if mt is BaseMaterial3D and str((mt as BaseMaterial3D).resource_name).to_lower().contains("interior"):
				mi.set_surface_override_material(j, inner)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var at: Vector3 = xf * (centre + (pc["at"] as Vector3))
		mi.global_transform = Transform3D(xf.basis, at)
		var out := (at - base) * Vector3(1, 0, 1)
		out = out.normalized() if out.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var v := out * randf_range(1.6, 3.6) * (0.6 + s) + Vector3(0, randf_range(2.0, 4.2) * (0.5 + s * 0.6), 0)
		var spin := Vector3(randf_range(-8, 8), randf_range(-5, 5), randf_range(-8, 8))
		DemonKitFx._throw(mi, w, v, spin, randf_range(1.0, 1.5))
	n.queue_free()
	var top := base + Vector3(0, 0.5 * s, 0)
	_glints(root, top, [4, 6, 9, 12][tr])
	InfernalFx.particles(root, top, {"amount": [6, 9, 14, 20][tr], "life": 0.7, "explosive": 1.0, "shape": "sphere",
		"r": 0.3 * s, "dir": Vector3.UP, "spread": 80.0, "vel": [1.5, 4.0], "gravity": -12.0, "scale": [0.4, 1.1],
		"size": 0.05, "colors": [[0.0, Color(1, 1, 1)], [0.5, PALE], [1.0, Color(DEEP, 0.0)]]})
	ElementalFx._dust(root, base + Vector3(0, 0.2, 0), MIST, 0.45 + 0.5 * s, 0.16, {"amount": [2, 2, 3, 4][tr], "life": 1.0,
		"explosive": 1.0, "shape": "sphere", "r": 0.3 * s, "dir": Vector3.UP, "spread": 60.0, "vel": [0.3, 0.9],
		"gravity": -0.5, "damping": [1.5, 2.5], "scale": [0.8, 1.2], "grow": [0.6, 1.7]})

# ---------------------------------------------------------------- frost on the foes
## A foe frosted over for `dur` s (refreshed by later strikes): rime crawling up from the feet (Enemy.set_frost, its
## rest overlay), wisps of cold vapour falling off it and pooling at its feet (an emitter riding it, shedding into the
## world). One that dies frozen shatters.
static func frost_body(game, e: Node3D, dur: float) -> void:
	var id := e.get_instance_id()
	if _bodies.has(id):
		_bodies[id]["t"] = maxf(float(_bodies[id]["t"]), dur)
		return
	var hgt := DemonKitFx.height_of(e)
	var tr := InfernalFx.tier(game)
	var card := ElementalFx._dust(e, e.global_position + Vector3(0, hgt * 0.55, 0), MIST, clampf(hgt * 0.28, 0.3, 0.9), 0.24,
		{"one_shot": false, "amount": [4, 6, 9, 12][tr], "life": 1.3, "explosive": 0.0, "shape": "box",
		"box": Vector3(0.22, hgt * 0.35, 0.22), "dir": Vector3.DOWN, "spread": 25.0, "vel": [0.1, 0.35], "gravity": -0.7,
		"damping": [0.6, 1.2], "scale": [0.6, 1.1], "grow": [0.5, 1.9]})
	_bodies[id] = {"e": e, "t": dur, "amt": 0.0, "card": card, "game": game}

static func _bodies_update(game, delta: float) -> void:
	var f := Engine.get_process_frames()
	if f == _body_frame:
		return
	_body_frame = f
	for id in _bodies.keys():
		var b: Dictionary = _bodies[id]
		var e = b["e"]
		var card = b["card"]
		if e == null or not is_instance_valid(e):
			_bodies.erase(id)
			continue
		if bool(e.dead):
			_shatter_body(b, e)
			_bodies.erase(id)
			continue
		b["t"] = float(b["t"]) - delta
		var on := float(b["t"]) > 0.0
		b["amt"] = clampf(float(b["amt"]) + delta * (2.2 if on else -1.6), 0.0, 1.0)
		if e.has_method("set_frost"):
			e.set_frost(float(b["amt"]))
		if is_instance_valid(card):
			(card as GPUParticles3D).emitting = on
		if not on and float(b["amt"]) <= 0.0:
			_stop(card)
			_bodies.erase(id)

## A foe that died frozen: the rime bursts off him in glints and splinters with a crack of ice.
static func _shatter_body(b: Dictionary, e) -> void:
	var game = b["game"]
	_stop(b["card"])
	if e.has_method("set_frost"):
		e.set_frost(0.0)
	if game == null or not is_instance_valid(game) or game.world == null:
		return
	var root: Node3D = game.world.fx_root
	var at: Vector3 = (e as Node3D).global_position + Vector3(0, DemonKitFx.height_of(e) * 0.5, 0)
	InfernalFx.particles(root, at, {"amount": 16, "life": 0.7, "explosive": 1.0, "shape": "sphere", "r": 0.35,
		"dir": Vector3.UP, "spread": 80.0, "vel": [1.5, 3.6], "gravity": -12.0, "scale": [0.4, 1.1], "size": 0.05,
		"colors": [[0.0, Color(1, 1, 1)], [0.5, PALE], [1.0, Color(DEEP, 0.0)]]})
	_glints(root, at, 8)
	Sfx.play_at("ice_shatter", at, -6.0, randf_range(1.0, 1.15))

## Stops a riding emitter and frees it once its last wisps are gone.
static func _stop(p) -> void:
	if is_instance_valid(p):
		(p as GPUParticles3D).emitting = false
		Fx._free_later(p as Node, 1.5)

static func clear(h: Hero) -> void:
	end_draw(h)
	h.fxs.erase("frost_volleys")

# ---------------------------------------------------------------- shaders
## The hoarfrost over the ground (InfernalFx.disc_mesh: UV 0.5 at the centre): the Meshy-painted hoarfrost tiled over
## it (RGB its colour, A its coverage), a glaze between the ferns, spreading out with a bright edge (`front`), glossy and
## glinting; the thaw (`thaw` 0..1) eats it from the edges in, leaving wet dark ground that dries.
const GROUND_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D hoar : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 pale : source_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform vec4 deep : source_color = vec4(0.25, 0.55, 0.95, 1.0);
uniform float front = 0.0;
uniform float thaw = 0.0;
uniform float seed = 0.0;
uniform float tile = 2.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float n = texture(noise_tex, UV * 2.3 + vec2(seed, 0.0)).r;
	float n2 = texture(noise_tex, UV * 7.0 + vec2(0.3, seed)).r;
	vec4 hf = texture(hoar, UV * tile + vec2(seed * 0.37, seed * 0.11));
	float edge = (n - 0.5) * 0.24;
	float inside = smoothstep(front + 0.02, front - 0.07, r + edge);
	float band = smoothstep(front - 0.12, front, r + edge) * inside * step(front, 0.995);
	float rim = smoothstep(1.0, 0.8, r + edge * 0.8);
	float keep = smoothstep((1.0 - thaw) * 1.2 - 0.02, (1.0 - thaw) * 1.2 - 0.2, r + (n - 0.5) * 0.5);
	float cover = clamp(0.3 + 1.1 * hf.a, 0.0, 1.0);
	float sparkle = smoothstep(0.86, 0.98, n2) * hf.a;
	vec3 frost = mix(deep.rgb * 0.45, hf.rgb, 0.35 + 0.65 * hf.a);
	vec3 wet = vec3(0.03, 0.035, 0.04);
	ALBEDO = mix(wet, frost, keep);
	ROUGHNESS = mix(0.1, mix(0.22, 0.6, hf.a), keep);
	SPECULAR = 0.9;
	EMISSION = (pale.rgb * (band * (0.35 + 0.6 * n2) + sparkle * 1.1 + hf.a * 0.14) + deep.rgb * 0.03) * keep;
	float wet_a = 0.32 * (1.0 - smoothstep(0.55, 1.0, thaw));
	ALPHA = clamp(mix(wet_a * step(0.001, thaw), cover, keep) * inside * rim, 0.0, 1.0);
}
"""

## A mist streak behind a flying arrow: a quad whose long side runs along `axis`, turned round it to face the camera;
## a soft core thinning to the tail, broken by drifting noise. UV.y 0 at the head (the node), 1 at the tail.
const STREAK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;
uniform vec3 axis = vec3(0.0, 1.0, 0.0);
uniform vec4 col : source_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform float alpha = 0.6;
uniform float seed = 0.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - c;
	vec3 ax = normalize(axis);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - c);
	vec3 side = normalize(cross(ax, to_cam));
	VERTEX = c + side * local.x + ax * local.y;
}
void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float along = UV.y;
	float n = texture(noise_tex, vec2(UV.x * 0.6 + seed, along * 1.4 - TIME * 1.6)).r;
	float core = pow(1.0 - across, 2.2);
	float tail = smoothstep(1.0, 0.75, along) * smoothstep(0.0, 0.08, along);
	float a = core * tail * (0.55 + 0.9 * n) * smoothstep(1.0, 0.0, along * 0.9);
	ALBEDO = col.rgb;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
"""

## A cold rim of light over ice (an overlay): bright at the silhouette, a faint glow through the faces.
const RIM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform float glow = 1.0;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float a = (pow(f, 2.6) * 0.9 + 0.05) * glow;
	ALBEDO = col.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

## Rime on a frozen body (Enemy's rest overlay; skinned, so VERTEX is the posed body): white crust and glittering
## crystals growing up from the feet to `amt` of its height, heaviest on the faces turned up, a cold rim, and a bright
## line where the frost is creeping on.
const BODY_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float amt = 0.0;
uniform float base_y = 0.0;
uniform float height = 1.8;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float hgt = clamp((wp.y - base_y) / height, 0.0, 1.0);
	float n = texture(noise_tex, vec2(wp.x + wp.z, wp.y) * 0.9).r;
	float n2 = texture(noise_tex, vec2(wp.x - wp.z, wp.y * 1.3) * 3.7).r;
	float line = amt * 1.18 - hgt + (n - 0.5) * 0.28;
	float on = smoothstep(0.0, 0.1, line);
	float up = clamp(wn.y * 0.6 + 0.5, 0.0, 1.0);
	float crust = clamp(up * 0.65 + smoothstep(0.42, 0.72, n2) * 0.7, 0.0, 1.0);
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float creep = smoothstep(0.0, 0.05, line) * (1.0 - smoothstep(0.05, 0.13, line));
	ALBEDO = mix(vec3(0.55, 0.72, 0.9), vec3(0.93, 0.97, 1.0), n2);
	ROUGHNESS = 0.22;
	SPECULAR = 0.9;
	EMISSION = vec3(0.5, 0.75, 1.0) * (pow(f, 3.0) * 0.7 * on + creep * 0.9 + smoothstep(0.8, 0.95, n2) * on * 0.4);
	ALPHA = clamp(crust * on * 0.85 + pow(f, 2.0) * 0.3 * on + creep * 0.5, 0.0, 1.0) * step(0.001, amt);
}
"""
