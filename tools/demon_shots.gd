extends SceneTree
## The Demon's body from the game camera in the Arena's hall: standing, running, Hellfire Claw, a cast, phased into
## the Underworld, dead and cooling. outdir/<name>.png. Needs a display:
##   xvfb-run -a godot --rendering-driver opengl3 --path . -s tools/demon_shots.gd -- outdir
var g
var out := ""

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _snap(nm: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "/" + nm + ".png")

func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "demon")
	g.difficulty = 0
	await g.load_zone(0, "sandbox", "start")
	g.ui.close_all()
	g.test_immortal = true
	g.hero.set_level(12)
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	var p0: Vector3 = g.world.spawns["start"]
	var h = g.hero
	h.global_position = Vector3(p0.x, g.world.height_at(p0.x, p0.z), p0.z)
	g.zoom = 0.7
	await create_timer(1.5).timeout
	print("[DS] body: mocap=%s wings=%s tail=%s mats=%d" % [str(h.rig.get_meta("meshy", "")), str(h.rig.get("wing_bones") != null and not (h.rig.get("wing_bones") as Dictionary).is_empty()),
		str(h.rig.get("tail_bones") != null and (h.rig.get("tail_bones") as Array).size()), (h.rig.get_meta("demon_mats") as Array).size() if h.rig.has_meta("demon_mats") else 0])
	await _snap("idle")
	h.direct_dir = Vector3(1, 0, 0)
	h.sprint = false
	await create_timer(1.2).timeout
	await _snap("run")
	h.sprint = true
	await create_timer(1.0).timeout
	await _snap("sprint")
	h.sprint = false
	h.direct_dir = Vector3.ZERO
	await create_timer(0.8).timeout
	h.mana = h.max_mana
	h.use_skill("hellclaw", h.global_position + Vector3(3, 0, 0))
	await create_timer(0.35).timeout
	await _snap("hellclaw")
	await create_timer(1.0).timeout
	h.mana = h.max_mana
	h.use_skill("fists", h.global_position + Vector3(0, 0, -2.0))
	await create_timer(0.4).timeout
	await _snap("fists")
	await create_timer(1.0).timeout
	h.mana = h.max_mana
	h.use_skill("wrath", h.global_position)
	await create_timer(2.6).timeout
	await _snap("wrath")
	print("[DS] wrath=%s heat=%.2f" % [str(h.dm.has("wrath")), float(((h.rig.get_meta("demon_mats") as Array)[0] as ShaderMaterial).get_shader_parameter("wrath"))])
	DemonSkills.clear(h)
	await create_timer(1.0).timeout
	g.test_immortal = false
	h.take_hit(99999.0, h.global_position + Vector3(1, 0, 0))
	await create_timer(0.9).timeout
	await _snap("death_fall")
	await create_timer(2.6).timeout
	await _snap("death_cooled")
	print("[DS] dead=%s cool=%.2f embers=%s" % [str(h.dead), float(((h.rig.get_meta("demon_mats") as Array)[0] as ShaderMaterial).get_shader_parameter("cool")), str((h.rig.get_meta("death_embers") as GPUParticles3D).emitting)])
	quit()
