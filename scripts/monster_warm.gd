class_name MonsterWarm
extends RefCounted
## The first monster of a kind that turns up after the loading screen used to freeze the game while its model loaded
## and its shaders compiled (Blaine's app audit, 2026-11-05, first spawn's worst frame on the Mac mini: Grubb's gold
## grabber 766 ms, in the middle of his fight; ice troll 222, imp 166, the dinosaurs 106-123, bandits, lions and
## gladiators 58-78). Under the loading screen, each kind that can still arrive in the zone (`kinds`) is built once,
## drawn in front of the camera for a couple of frames and freed; its model stays loaded (the builders load through
## ResCache) and `SkillWarm.keep` holds its materials, so the driver keeps what it compiled. Once per kind per session.
## Kinds already standing in the zone were built under the loading screen anyway.

static var _done := {}

## What can still turn up in the built zone: ambushes, the monsters' and the boss's summons, Grubb's grabbers, the
## arena's stages; and on a co-op client (whose monsters arrive from the host) the zone's spawns too.
static func kinds(g) -> Array:
	var w = g.world
	var k := {}
	if g.net.is_client():
		for es in w.enemy_spawns:
			k[str(es["kind"])] = true
		if not w.boss_spawn.is_empty():
			k[str(g.boss_kind())] = true
	for a in w.ambushes:
		for s in a.get("spawns", []):
			k[str(s["kind"])] = true
	var present := {}
	for es in w.enemy_spawns:
		present[str(es["kind"])] = true
	if not w.boss_spawn.is_empty():
		present[str(g.boss_kind())] = true
	for kind in present.keys() + k.keys():
		var d: Dictionary = Data.ENEMIES.get(kind, {})
		if str(d.get("summon", "")) != "":
			k[str(d["summon"])] = true
		if d.get("hoard", false):
			k["grabber"] = true
	if w.has_meta("games"):
		for st in w.get_meta("games").STAGES:       # (games.gd is loaded at run time: no static reference)
			for s in st.get("spawns", []):
				k[str(s[0])] = true
			if st.has("boss"):
				k[str(st["boss"])] = true
	var out: Array = []
	for kind in k:
		if Data.ENEMIES.has(kind) and not _done.has(kind) and not (present.has(kind) and not g.net.is_client()):
			out.append(kind)
	return out

## Under the loading screen (Game.load_zone): build and draw each kind once.
static func run(g) -> void:
	if g == null or g.world == null or g.hero == null or g.net.server or g.shot_path != "":
		return
	if DisplayServer.get_name() == "headless":
		return
	var todo := kinds(g)
	if todo.is_empty():
		return
	var t0 := Time.get_ticks_msec()
	var cam: Camera3D = g.get_viewport().get_camera_3d()
	var at: Vector3 = g.hero.global_position
	if cam != null:
		at = cam.global_position - cam.global_transform.basis.z * 8.0
		at.y = g.world.height_at(at.x, at.z)
	var bodies: Array = []
	for i in todo.size():
		_done[todo[i]] = true
		var r := Enemy.build_rig(str(todo[i]))
		if r == null:
			continue
		g.world.fx_root.add_child(r)
		r.global_position = at + Vector3((i % 6 - 2.5) * 1.6, 0, (i / 6) * 1.6)
		bodies.append(r)
	for i in 3:
		await RenderingServer.frame_post_draw
	# then under the overlays a monster can wear (pipelines are per material and mesh): the hit flash, a champion's rim
	if Enemy._flash_shader == null:
		Enemy._flash_shader = Shader.new()
		Enemy._flash_shader.code = Enemy.FLASH_SHADER
	var flash := ShaderMaterial.new()
	flash.shader = Enemy._flash_shader
	flash.set_shader_parameter("col", Color(1, 1, 1, 0.5))
	for over in [flash, Mats.glow(Color(0.35, 0.55, 1.0), 1.2, 0.0, 1.0)]:
		for r in bodies:
			for m in (r as Node).find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).material_overlay = over
		for i in 2:
			await RenderingServer.frame_post_draw
	for r in bodies:
		SkillWarm.keep(r)
		r.queue_free()
	print("[warm] monsters %s in %d ms" % [",".join(todo), Time.get_ticks_msec() - t0])
