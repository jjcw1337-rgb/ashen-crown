class_name DemonFaultFx
extends RefCounted
## Fault of the Pit's look (the Demon's R; the gameplay is DemonSkills). Tectonic, not a spell.
##
##  The slam ("impact" {p: the blow, q: the fault's middle, ps: [a, b] its ends, x: the warning, r: how long it
##  stays molten}): his fists drive into the ground (a flash, dust, a shock through the earth), and a crack runs out
##  ahead to the fault and tears along it from the middle to both ends, pulsing hotter through the warning so
##  everyone can see exactly where it will go up.
##  The eruption ("erupt" {ps, t, x}): jagged obsidian plates heave up out of the ground along the line, tilted
##  apart (the Meshy plates, procedural shards without them), magma wells up between them, a curtain of fire runs
##  its length with heat haze over it (High+), rock and embers are thrown up, anyone on it is thrown up and burns.
##  Molten (r s): the fire settles to a low burn, the magma breathes, the plates' seams glow; at the end the crust
##  darkens, the fires die, the plates crack and sink back into the ground.
## State: h.fxs["fault"], kept by `update` (a partner's copy times itself out from r).

const PLATES := [5, 7, 9, 11]
const FIRES := [3, 5, 7, 8]

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"impact":
			_slam(h, ev)
		"erupt":
			_erupt(h, ev)
		"cast":
			pass
		_:
			return false
	return true

static func _slam(h: Hero, ev: Dictionary) -> void:
	_end(h, true)
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var p: Vector3 = ev["p"]
	p.y = world.height_at(p.x, p.z)
	var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
	if ps.size() < 2:
		return
	var a: Vector3 = ps[0]
	var b: Vector3 = ps[1]
	var mid := (a + b) * 0.5
	var warn: float = float(ev.get("x", DemonSkills.FAULT_WARN))
	var life: float = float(ev.get("r", DemonSkills.FAULT_LIFE))
	# the blow itself
	var gm := InfernalFx.glow_mat(InfernalFx.MOLTEN, 1.8, 2.0, 0.4)
	var g := InfernalFx.glow(root, p + Vector3(0, 0.4, 0), 0.8, gm)
	g.create_tween().tween_property(g, "scale", Vector3.ONE * 2.6, 0.18).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, gm, "alpha", 1.0, 0.0, 0.24)
	Fx._free_later(g, 0.3)
	DemonKitFx.flash_light(root, p + Vector3(0, 0.8, 0), InfernalFx.MOLTEN, 4.0, 6.0, 0.4)
	Fx.burst(root, p + Vector3(0, 0.2, 0), Color(0.24, 0.19, 0.15, 0.8), [10, 14, 20, 24][tr], 3.4, 0.35, 0.8, false, -4.0, 70.0)
	DemonKitFx.debris(root, p + Vector3(0, 0.2, 0), [3, 5, 6, 8][tr], Vector3.UP, 3.0, 0.1)
	DemonKitFx.shock_ring(root, h.game, p, 2.2, 0.3)
	var sm := DemonFx.lava_decal(root, p, 1.1, 2.2, 0.2)
	sm.scale = Vector3(1.1, 1, 1.1)
	# the crack running out to the fault, then tearing along it from the middle to both ends
	var feed := DemonKitFx.crack(root, world, p, mid, 0.5)
	InfernalFx.tween_param(feed[0], feed[1], "front", 0.0, 1.05, warn * 0.4).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(feed[0], feed[1], "life", 1.0, 0.0, 1.2, warn + 0.8)
	Fx._free_later(feed[0], warn + 2.2)
	var halves: Array = []
	for end in [a, b]:
		var ck := DemonKitFx.crack(root, world, mid, end, DemonSkills.FAULT_W * 0.9)
		var rm: ShaderMaterial = ck[1]
		rm.set_shader_parameter("front", 0.0)
		rm.set_shader_parameter("heat", 0.55)
		var tw := (ck[0] as Node).create_tween()
		tw.tween_interval(warn * 0.35)
		tw.tween_method(func(v: float): rm.set_shader_parameter("front", v), 0.0, 1.05, warn * 0.45).set_ease(Tween.EASE_OUT)
		halves.append(ck)
	h.fxs["fault"] = {"a": a, "b": b, "halves": halves, "t": 0.0, "warn": warn, "life": life, "until": warn + life + 2.5,
		"stage": "warn", "plates": [], "fires": []}
	SkillFx.snd(h, "slam", 0.0, 0.78)
	SkillFx.snd(h, "boom", -9.0, 0.7)
	SkillFx.duck(h, -3.0, 0.5)
	SkillFx.shake(h, 0.35)

static func _erupt(h: Hero, ev: Dictionary) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var st: Dictionary = h.fxs.get("fault", {})
	var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
	if st.is_empty():
		if ps.size() < 2:
			return
		st = {"a": ps[0], "b": ps[1], "halves": [], "t": 0.0, "warn": 0.0, "life": DemonSkills.FAULT_LIFE,
			"until": DemonSkills.FAULT_LIFE + 2.5, "plates": [], "fires": []}
		h.fxs["fault"] = st
	st["stage"] = "molten"
	st["t"] = 0.0
	var a: Vector3 = st["a"]
	var b: Vector3 = st["b"]
	var d := (b - a) * Vector3(1, 0, 1)
	var len := d.length()
	var dir := d.normalized()
	var side := dir.cross(Vector3.UP)
	var life: float = float(st["life"])
	# the crack blazes
	for ck in st["halves"]:
		var rm: ShaderMaterial = ck[1]
		rm.set_shader_parameter("front", 1.05)
		InfernalFx.tween_param(ck[0], rm, "heat", 1.6, 0.85, 0.5)
	# magma welling up between the plates (a molten strip under them, breathing through the fault's life)
	var lv := DemonFx.lava_strip(root, a, b, DemonSkills.FAULT_W * 0.8, life + 1.2, 1.0)
	st["lava"] = lv
	# the plates
	var plates: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(a.x * 10.0), int(b.z * 10.0)))
	var n: int = PLATES[tr]
	for i in n:
		var u := (float(i) + rng.randf_range(0.2, 0.8)) / float(n)
		var lane := (1.0 if i % 2 == 0 else -1.0) * rng.randf_range(0.35, 0.6)
		var pp := a + d * u + side * lane * DemonSkills.FAULT_W * 0.5
		pp.y = world.height_at(pp.x, pp.z)
		var hgt := rng.randf_range(0.75, 1.35) * (1.0 - 0.35 * absf(u - 0.5) * 2.0)
		var node := DemonKitFx.model(DemonKitFx.PLATE)
		if node != null:
			DemonKitFx.heat_model(node, 2.4)
			node.scale = Vector3(rng.randf_range(0.7, 1.0), hgt, rng.randf_range(0.8, 1.1)) * 1.05
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = InfernalFx.shard_mesh(rng.randi() % 6)
			mi.material_override = InfernalFx.shard_mat()
			node = Node3D.new()
			node.add_child(mi)
			node.scale = Vector3(0.7, hgt * 1.2, 0.7)
		root.add_child(node)
		# tilted apart from the fault's spine, as if the ground had heaved up and split
		var tilt := Basis(dir, -lane * rng.randf_range(0.5, 0.9)) * Basis(Vector3.UP, atan2(-d.x, -d.z) + rng.randf_range(-0.4, 0.4))
		node.basis = tilt.scaled(node.scale)
		var rest := pp - Vector3(0, hgt * 0.15, 0)
		node.global_position = pp - Vector3(0, hgt * 1.1, 0)
		var delay := absf(u - 0.5) * 0.12 + rng.randf_range(0.0, 0.04)
		var tw := node.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(node, "global_position", rest, 0.11).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		plates.append({"node": node, "rest": rest, "h": hgt})
		if i % 2 == 0:
			Fx.burst(root, pp + Vector3(0, 0.2, 0), Color(0.24, 0.19, 0.15, 0.75), [4, 6, 8, 10][tr], 2.8, 0.3, 0.6, false, -5.0, 45.0, Vector3.UP)
	st["plates"] = plates
	# the curtain of fire: tall at the eruption, then a low burn for the fault's life
	var fires: Array = []
	var nf: int = FIRES[tr]
	for i in nf:
		var u := (float(i) + 0.5) / float(nf)
		var fp := a + d * u + side * randf_range(-0.15, 0.15)
		fp.y = world.height_at(fp.x, fp.z)
		var big := InfernalFx.fire(root, fp, randf_range(1.6, 2.2), 55.0, tr, true, true)
		var tw := big.create_tween()
		tw.tween_interval(0.45 + randf_range(0.0, 0.2))
		tw.tween_callback(func(): InfernalFx.fire_on(big, false))
		tw.tween_interval(1.2)
		tw.tween_callback(big.queue_free)
		var low := InfernalFx.fire(root, fp, randf_range(0.55, 0.8), 30.0, tr, i % 2 == 0, true)
		fires.append(low)
	st["fires"] = fires
	# the air shimmering over it
	if InfernalFx.haze_ok(h.game):
		var hz := InfernalFx.haze_mat(0.03, false)
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(len, 1.8)
		qm.center_offset = Vector3(0, 0.9, 0)
		mi.mesh = qm
		mi.material_override = hz
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.global_position = (a + b) * 0.5
		mi.look_at(mi.global_position + side, Vector3.UP)
		st["haze"] = mi
	# rock, embers and smoke thrown up along it, a light running its length
	var midp := (a + b) * 0.5
	DemonKitFx.embers(root, midp + Vector3(0, 0.3, 0), [20, 34, 48, 60][tr], 30.0, Vector2(2.0, 6.0), Vector3.UP, Vector3(len * 0.5, 0.1, 0.4).abs())
	InfernalFx.smoke(root, midp + Vector3(0, 0.6, 0), [4, 7, 10, 13][tr], Vector3(len * 0.45, 0.2, 0.4).abs(), Vector3.UP, 1.6, 2.0, 1.3, 0.75)
	for k in 2:
		DemonKitFx.debris(root, a + d * (0.25 + 0.5 * k) + Vector3(0, 0.3, 0), [2, 3, 4, 5][tr], Vector3.UP, 4.0, 0.13)
	var l := OmniLight3D.new()
	l.light_color = InfernalFx.MOLTEN
	l.light_energy = 5.0
	l.omni_range = len * 0.75
	l.shadow_enabled = InfernalFx.tier(h.game) >= 3
	root.add_child(l)
	l.global_position = midp + Vector3(0, 1.0, 0)
	st["light"] = l
	for e in DemonKitFx.targets(h, ev):
		_thrown(h, root, e, tr)
	Sfx.play_at("boom", midp, -1.0, 0.85)
	Sfx.play_at("fire_erupt", midp, -3.0, 0.75)
	Sfx.play_at("impact_bone", midp, -7.0, 0.5)
	Sfx.play_at("ice_shatter", midp, -14.0, 0.45)
	SkillFx.shake(h, 0.42)
	if bool(ev.get("x", false)):
		SkillFx.hitstop(h, 0.04)

## Someone on the fault: thrown up off their feet in a gout of fire (a monster's body lifts and drops; a player's
## own game lifts him itself, PvpStatus).
static func _thrown(h: Hero, root: Node3D, e: Node3D, tr: int) -> void:
	var c := DemonKitFx.chest(e, 0.4)
	InfernalFx.particles(root, c, {"amount": [8, 12, 16, 20][tr], "life": 0.45, "explosive": 1.0, "dir": Vector3.UP,
		"spread": 25.0, "vel": [3.0, 7.0], "gravity": -9.0, "scale": [0.5, 1.0], "size": 0.07,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.35, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	var f := InfernalFx.fire(e, e.global_position + Vector3(0, DemonKitFx.height_of(e) * 0.4, 0), DemonKitFx.height_of(e) * 0.8, 40.0, tr, true, true)
	var twf := f.create_tween()
	twf.tween_interval(0.6)
	twf.tween_callback(func(): InfernalFx.fire_on(f, false))
	twf.tween_interval(1.0)
	twf.tween_callback(f.queue_free)
	if e is Hero:
		return
	var rig = e.get("rig")
	if rig != null and is_instance_valid(rig):
		var y0: float = (rig as Node3D).position.y
		var tw := (rig as Node3D).create_tween()
		tw.tween_property(rig, "position:y", y0 + 0.9, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(rig, "position:y", y0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

## Every frame: the warning pulses, the molten fault breathes, and at the end it cools and sinks.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("fault"):
		return
	var st: Dictionary = h.fxs["fault"]
	st["t"] = float(st["t"]) + delta
	st["until"] = float(st["until"]) - delta
	if float(st["until"]) <= 0.0:
		_end(h, true)
		return
	var t: float = float(st["t"])
	match str(st["stage"]):
		"warn":
			var k := clampf(t / maxf(float(st["warn"]), 0.05), 0.0, 1.0)
			for ck in st["halves"]:
				(ck[1] as ShaderMaterial).set_shader_parameter("heat", 0.5 + 0.5 * k + 0.25 * sin(t * (18.0 + 30.0 * k)))
			if t > float(st["warn"]) + 0.6:
				st["stage"] = "molten"     # a partner who never got the eruption
				st["t"] = 0.0
		"molten":
			var life: float = float(st["life"])
			var cool := smoothstep(life - 0.9, life, t)
			var l = st.get("light")
			if l != null and is_instance_valid(l):
				var fl := 0.85 + 0.15 * sin(h.anim_time * 13.0) * sin(h.anim_time * 5.3)
				(l as OmniLight3D).light_energy = lerpf(5.0, 1.6, smoothstep(0.0, 0.6, t)) * fl * (1.0 - cool)
			for pl in st["plates"]:
				DemonKitFx.set_heat(pl["node"], lerpf(2.4, 0.9, smoothstep(0.0, 1.0, t)) * (1.0 - cool) * (0.85 + 0.15 * sin(h.anim_time * 3.0)))
			for ck in st["halves"]:
				(ck[1] as ShaderMaterial).set_shader_parameter("heat", 0.85 * (1.0 - cool))
			if t >= life and not st.has("sinking"):
				st["sinking"] = true
				_sink(h, st)

## The end: the fires die, the plates crack and sink back, the crack cools to nothing.
static func _sink(h: Hero, st: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	for f in st.get("fires", []):
		if is_instance_valid(f):
			InfernalFx.fire_on(f, false)
			Fx._free_later(f, 1.2)
	st["fires"] = []
	for pl in st.get("plates", []):
		var n = pl["node"]
		if n == null or not is_instance_valid(n):
			continue
		var rest: Vector3 = pl["rest"]
		var tw := (n as Node3D).create_tween()
		tw.tween_interval(randf_range(0.0, 0.25))
		tw.tween_property(n, "global_position", rest - Vector3(0, float(pl["h"]) * 1.2, 0), 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback((n as Node).queue_free)
		Fx.burst(root, rest + Vector3(0, 0.2, 0), Color(0.2, 0.16, 0.13, 0.6), 4, 1.4, 0.28, 0.6, false, -3.0, 70.0, Vector3.UP)
	st["plates"] = []
	for ck in st.get("halves", []):
		InfernalFx.tween_param(ck[0], ck[1], "life", 1.0, 0.0, 0.9)
		Fx._free_later(ck[0], 1.0)
	st["halves"] = []
	var hz = st.get("haze")
	if hz != null and is_instance_valid(hz):
		(hz as Node).queue_free()
	st.erase("haze")
	var l = st.get("light")
	if l != null and is_instance_valid(l):
		(l as Node).queue_free()
	st.erase("light")
	var mid := ((st["a"] as Vector3) + (st["b"] as Vector3)) * 0.5
	Sfx.play_at("impact_bone", mid, -14.0, 0.45)
	st["until"] = 1.2

static func _end(h: Hero, now: bool) -> void:
	if not h.fxs.has("fault"):
		return
	var st: Dictionary = h.fxs["fault"]
	h.fxs.erase("fault")
	for key in ["plates", "fires"]:
		for x in st.get(key, []):
			var n = x["node"] if x is Dictionary else x
			if n != null and is_instance_valid(n):
				(n as Node).queue_free()
	for ck in st.get("halves", []):
		if is_instance_valid(ck[0]):
			(ck[0] as Node).queue_free()
	for key in ["haze", "light"]:
		var n = st.get(key)
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	var lv = st.get("lava")
	if now and lv != null and is_instance_valid(lv):
		(lv as Node).queue_free()

static func clear(h: Hero) -> void:
	_end(h, true)
