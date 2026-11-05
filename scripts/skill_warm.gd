class_name SkillWarm
extends RefCounted
## The first cast of every skill used to freeze the game for 0.1-0.5 s (jj, 2026-11-04: "everytime i load into the
## game ... and i use fire arrow attack theres intense lag and freezing ... similiar to other skills"): the driver
## compiling the effect's shaders and pipelines and the effect loading its models and textures, all on the frame it
## first appears. Under the loading screen, the first time a class enters a zone this session, an unseen co-op puppet
## of the hero plays everything the class's skills draw (their recorded fx events, SkillWarmData.EVENTS, made by
## tools/skill_warm_capture.gd), muted, beside him for a few frames; then all of it is swept away. A puppet
## deals nothing (every handler only draws on one), so it is safe among monsters.
## Measured on the proof range (first cast's worst frame): Fire Arrow 198 ms, Thunderstep 183, Spirit Beast 544.

const SETTLE := 2.2          # seconds the effects are left to play out (Frost Volley shatters at 1.95)
## The settle runs in fast-forward (Engine.time_scale): every effect still lives its whole 2.2 s of game time and
## draws each of its stages (pipelines compile on the frame a thing is first drawn), in up to a quarter of the
## wall-clock wait under the loading screen (nightly 2026-11-05: the warm was 2.5-2.7 s of every first load). A
## frame never steps more than MAX_STEP of game time (a 15 fps frame, what a slow Ultra frame already stepped at 1x),
## so a short-lived stage is never stepped over: slow frames get less of the speed-up.
const SPEED := 4.0
const MAX_STEP := 0.066

static var _done := {}

static func _load() -> Dictionary:
	return SkillWarmData.EVENTS

## Warm the hero's class's effects (once per class per session). Awaited by Game.load_zone before the loading
## screen goes.
static func run(g) -> void:
	if g == null or g.hero == null or g.world == null or g.net.server or g.shot_path != "":
		return
	if DisplayServer.get_name() == "headless":
		return
	var cls: String = g.hero.cls
	if _done.has(cls):
		return
	_done[cls] = true
	var evs: Array = _load().get(cls, [])
	if evs.is_empty():
		return
	var root: Node3D = g.world.fx_root
	var before := {}
	for c in root.get_children():
		before[c.get_instance_id()] = true
	var p := Hero.new()
	p.puppet = true
	p.peer_id = 98
	p.name = "WarmPuppet"
	g.add_child(p)
	p.setup(g)
	p.apply_net_gear(g.hero.net_gear())
	var origin: Vector3 = g.hero.global_position
	p.global_position = origin
	p.net_pos = origin
	p.net_st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
	p.net_has = true
	var was_muted: bool = Sfx.muted
	Sfx.set_muted(true)
	var t0 := Time.get_ticks_msec()
	for w in evs:
		if w is Dictionary:
			SkillFx.play(p, _rebuild(w, origin))
	var tree: SceneTree = g.get_tree()
	for i in 3:
		await RenderingServer.frame_post_draw
	# what a skill draws on the bow through its draw (from the attack's progress, not an event): the Fire Arrow's
	# fire on the nocked arrow, Frost Volley's rime and the high aim
	if cls == "archer":
		ArrowFx.draw_charge(p, "fire", 0.7)
		FrostVolleyFx.draw(p, 0.5)
	for i in 4:
		await RenderingServer.frame_post_draw
	if cls == "archer":
		ArrowFx.end_draw(p)
		FrostVolleyFx.end_draw(p)
	var was_scale := Engine.time_scale
	var left := SETTLE
	while left > 0.0:
		var real := tree.root.get_process_delta_time() / maxf(Engine.time_scale, 0.01)
		Engine.time_scale = clampf(MAX_STEP / maxf(real, 0.001), 1.0, SPEED)
		await tree.process_frame
		left -= tree.root.get_process_delta_time()
	Engine.time_scale = was_scale if was_scale <= 1.0 else 1.0
	SkillFx.clear(p)
	p.queue_free()
	if is_instance_valid(root):
		for c in root.get_children():
			if not before.has(c.get_instance_id()):
				c.queue_free()
	await tree.process_frame
	Sfx.set_muted(was_muted)
	print("[warm] %s: %d effects in %d ms" % [cls, evs.size(), Time.get_ticks_msec() - t0])

## A recorded event back as one to play: its places put round `origin`, no monsters.
static func _rebuild(w: Dictionary, origin: Vector3) -> Dictionary:
	var ev := {}
	for k in w:
		ev[k] = _value(w[k], origin)
	if not ev.has("t"):
		ev["t"] = []
	return ev

static func _value(v, origin: Vector3):
	if v is Dictionary:
		if v.has("v3"):
			var a: Array = v["v3"]
			return origin + Vector3(float(a[0]), float(a[1]), float(a[2]))
		if v.has("pv3"):
			var out := PackedVector3Array()
			for a in v["pv3"]:
				out.append(origin + Vector3(float(a[0]), float(a[1]), float(a[2])))
			return out
		var d := {}
		for k in v:
			d[k] = _value(v[k], origin)
		return d
	if v is Array:
		var arr: Array = []
		for x in v:
			arr.append(_value(x, origin))
		return arr
	return v
