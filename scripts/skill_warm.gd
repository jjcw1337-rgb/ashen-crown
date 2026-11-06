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
## Let every delayed visual stage render at normal simulation speed.
const LOW_RES := 0.25

static var _done := {}

static func context(g) -> String:
	return "%s:%s:%d:%d" % [str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		RenderingServer.get_video_adapter_name(), g.quality, g.get_viewport().msaa_3d]


## What the capture's 2.2 s per skill doesn't reach of the Plague Doctor's (Plague.remote events).
const PLAGUE_TAIL := ["cloud|~0,0,-3|3.0|4.0|toxic", "cloud|~2,0,-2|2.0|2.5|cane", "trans_end|1.0", "burst|8.0|2",
	"spew|~0,0,-3.5|~0,0,-7", "swarm_scatter", "reveal"]

static func _load() -> Dictionary:
	return SkillWarmData.EVENTS

## Warm the party's classes' effects (once per class per session): the hero's and every co-op partner's, since a
## partner's spells are drawn on this screen too, from his puppet (the stress fight, Blaine 2026-11-05: an unwarmed
## partner Archer's first Fire Arrow froze the host 0.7 s). Awaited by Game.load_zone before the loading screen goes;
## Game prepares all classes before online/competitive entry so late arrivals are covered.
## `classes` overrides the party (tools and the shared content preparation policy).
static func run(g, classes: Array = []) -> void:
	if g == null or g.hero == null or g.world == null or g.net.server or g.shot_path != "":
		return
	if DisplayServer.get_name() == "headless":
		return
	if classes.is_empty():
		classes = [g.hero.cls]
		for pp in g.net.puppets():
			if is_instance_valid(pp) and not classes.has(str(pp.cls)):
				classes.append(str(pp.cls))
	var todo: Array = []
	for c in classes:
		if not _done.has(context(g) + ":" + str(c)) and not (_load().get(c, []) as Array).is_empty():
			todo.append(c)
	if todo.is_empty():
		return
	var root: Node3D = g.world.fx_root
	var before := {}
	for c in root.get_children():
		before[c.get_instance_id()] = true
	var was_muted: bool = Sfx.muted
	Sfx.set_muted(true)
	# under the loading screen nothing of the 3D view is seen: drawn at a quarter of its size, its frames come
	# quicker. Effect timers still run at normal simulation speed; readiness is recorded after drawing.
	var vp: Viewport = g.get_viewport()
	var was_3d := vp.scaling_3d_scale
	vp.scaling_3d_scale = LOW_RES
	var t0 := Time.get_ticks_msec()
	var origin: Vector3 = g.hero.global_position
	var pups: Array = []
	var n := 0
	for cls in todo:
		var p := Hero.new()
		p.puppet = true
		p.peer_id = 98 - pups.size()
		p.name = "WarmPuppet_" + str(cls)
		g.add_child(p)
		p.setup(g)
		if cls == g.hero.cls:
			p.apply_net_gear(g.hero.net_gear())
		else:
			p.set_class(cls)
		p.global_position = origin
		p.net_pos = origin
		p.net_st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
		p.net_has = true
		pups.append(p)
		for w in _load()[cls]:
			if w is Dictionary:
				SkillFx.play(p, _rebuild(w, origin))
				n += 1
		# the Plague Doctor draws through his own Plague (a puppet's is a ghost that only shows), not SkillFx
		if cls == "plague" and p.pd != null:
			for ev in SkillWarmData.PLAGUE:
				p.pd.remote(_pd_rebuild(str(ev), origin))
				n += 1
	# Shared run procs and consumable variants can appear on any class mid-match.
	for event in RunTalents.preparation_events(origin):
		SkillFx.play(pups[0], event)
		n += 1
	var tree: SceneTree = g.get_tree()
	for i in 3:
		await RenderingServer.frame_post_draw
	# what a skill draws on the bow through its draw (from the attack's progress, not an event): the Fire Arrow's
	# fire on the nocked arrow, Frost Volley's rime and the high aim
	var archer: Hero = pups[todo.find("archer")] if todo.has("archer") else null
	if archer != null:
		ArrowFx.draw_charge(archer, "fire", 0.7)
		FrostVolleyFx.draw(archer, 0.5)
	for i in 4:
		await RenderingServer.frame_post_draw
	if archer != null:
		ArrowFx.end_draw(archer)
		FrostVolleyFx.end_draw(archer)
	await _settle(tree, SETTLE * 0.5)
	# the Plague Doctor's later moments: his clouds, the transfusion's end, the experiment's burst and spew
	var plague: Hero = pups[todo.find("plague")] if todo.has("plague") else null
	if plague != null and plague.pd != null:
		for ev in PLAGUE_TAIL:
			plague.pd.remote(_pd_rebuild(ev, origin))
			n += 1
	await _settle(tree, SETTLE * 0.5)
	# keep every material the effects drew with (Godot 4.3 frees a StandardMaterial3D's or ParticleProcessMaterial's
	# generated shader with the last material using it, so sweeping the effects away threw away what was just
	# compiled, and the first real cast compiled it all again: Blaine, 2026-11-05)
	for p in pups:
		keep(p)
	if is_instance_valid(root):
		for c in root.get_children():
			if not before.has(c.get_instance_id()):
				keep(c)
	for p in pups:
		SkillFx.clear(p)
		p.queue_free()
	vp.scaling_3d_scale = was_3d
	if is_instance_valid(root):
		for c in root.get_children():
			if not before.has(c.get_instance_id()):
				c.queue_free()
	await tree.process_frame
	Sfx.set_muted(was_muted)
	for cls in todo:
		_done[context(g) + ":" + str(cls)] = true
	print("[warm] %s: %d effects in %d ms" % [",".join(todo), n, Time.get_ticks_msec() - t0])

## Lets delayed effects render without changing the global simulation clock.
static func _settle(tree: SceneTree, secs: float) -> void:
	# Preparation must never accelerate live multiplayer simulation or somebody else's timers.
	var deadline := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame

static var _kept: Array = []
static var _kept_ids := {}

## Holds on to every material under n for the rest of the session (see run).
static func keep(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var nodes: Array = [n]
	nodes.append_array(n.find_children("*", "", true, false))
	for x in nodes:
		# a model an effect instanced (a glb): its PackedScene, or the cache lets it go with the effect and the first
		# real cast parses the file again
		var sp: String = (x as Node).scene_file_path
		if sp != "" and not _kept_ids.has(sp) and ResourceLoader.has_cached(sp):
			_kept_ids[sp] = true
			_kept.append(load(sp))
		if x is GeometryInstance3D:
			var gi := x as GeometryInstance3D
			_keep_mat(gi.material_override)
			_keep_mat(gi.material_overlay)
			if gi is MeshInstance3D:
				var mi := gi as MeshInstance3D
				for i in mi.get_surface_override_material_count():
					_keep_mat(mi.get_surface_override_material(i))
				if mi.mesh != null:
					for i in mi.mesh.get_surface_count():
						_keep_mat(mi.mesh.surface_get_material(i))
			elif gi is GPUParticles3D:
				var gp := gi as GPUParticles3D
				_keep_mat(gp.process_material)
				for i in gp.draw_passes:
					var dm := gp.get_draw_pass_mesh(i)
					if dm != null:
						for j in dm.get_surface_count():
							_keep_mat(dm.surface_get_material(j))
			elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null and (gi as MultiMeshInstance3D).multimesh.mesh != null:
				var mm := (gi as MultiMeshInstance3D).multimesh.mesh
				for i in mm.get_surface_count():
					_keep_mat(mm.surface_get_material(i))

static func _keep_mat(m: Material) -> void:
	if m == null or _kept_ids.has(m.get_instance_id()):
		return
	_kept_ids[m.get_instance_id()] = true
	_kept.append(m)
	if m.next_pass != null:
		_keep_mat(m.next_pass)

## A recorded Plague event back as one to play: its "~x,y,z" places put round `origin`.
static func _pd_rebuild(ev: String, origin: Vector3) -> String:
	var a := ev.split("|")
	for i in a.size():
		if a[i].begins_with("~"):
			var v := Plague._pv(a[i].substr(1)) + origin
			a[i] = "%.2f,%.2f,%.2f" % [v.x, v.y, v.z]
	return "|".join(a)

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

## Leaving gameplay retires warm-only references. Live nodes keep their own resources.
static func release_prepared() -> void:
	_done.clear()
	_kept.clear()
	_kept_ids.clear()
