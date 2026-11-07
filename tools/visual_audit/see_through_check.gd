extends SceneTree
## Which of a zone's tall meshes dither away round the hero (Props.see_through, Mats.PROP_SHADER and the other shaders
## with the `occlude` block) and which still can't (a material see_through leaves alone), in the running game.
##   godot --headless --path . -s tools/visual_audit/see_through_check.gd -- town lair wild
## args: Act I zones to visit in turn
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	await frames(10)
	await g.start_game(false, "knight")
	while g._busy:
		await frames(5)
	for zone in OS.get_cmdline_user_args():
		await g.travel(0, zone, "start")
		while g._busy or g.cur_zone != zone:
			await frames(5)
		await frames(5)
		_count(zone)
	quit()

func _count(zone: String) -> void:
	var conv := 0
	var dith := 0
	var left := {}
	var done := {}
	var stack: Array[Node] = [g.world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Skeleton3D or n.get_parent() is Skeleton3D:
			continue
		var mats: Array = []
		var h := 0.0
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).skin == null:
			var mi := n as MeshInstance3D
			h = (mi.global_transform * mi.mesh.get_aabb()).size.y
			for si in mi.mesh.get_surface_count():
				mats.append(mi.get_active_material(si))
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
			var mmi := n as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm.instance_count == 0:
				continue
			h = (mmi.global_transform * mm.get_aabb()).size.y
			for si in mm.mesh.get_surface_count():
				mats.append(mmi.material_override if mmi.material_override else mm.mesh.surface_get_material(si))
		if h < Props.SEE_MIN_H:
			continue
		for m in mats:
			if m is ShaderMaterial and (m as ShaderMaterial).shader:
				var sh: Shader = (m as ShaderMaterial).shader
				if sh.code.contains("global uniform vec3 player_pos") and sh.code.contains("occlude"):
					if sh == Mats.custom("see_through", Props.SEE_THROUGH_SHADER) \
							or sh == Mats.custom("see_through_2side", Props.SEE_THROUGH_SHADER.replace("cull_back", "cull_disabled")):
						conv += 1
						var nm := String(n.name) if not String(n.name).begins_with("@") else String(n.get_parent().name) + "/" + n.get_class()
						done[nm.left(32)] = int(done.get(nm.left(32), 0)) + 1
					else:
						dith += 1
					continue
			var why: String = "null" if m == null else (m as Object).get_class()
			if m is BaseMaterial3D:
				var b := m as BaseMaterial3D
				why += " transp%d emis%s shading%d" % [b.transparency, str(b.emission_enabled), b.shading_mode]
			elif m is ShaderMaterial and (m as ShaderMaterial).shader:
				var first: PackedStringArray = (m as ShaderMaterial).shader.code.strip_edges().split("\n")
				why += " (%s)" % (first[1] if first.size() > 1 else "")
			var key := "%s | %s" % [String(n.name).left(28), why]
			left[key] = int(left.get(key, 0)) + 1
	print("[ST] %s: %d surfaces converted by Props.see_through, %d dither with their own shader" % [zone, conv, dith])
	print("[ST]   converted: %s" % str(done))
	for k in left.keys():
		print("[ST]   still solid round the hero: %s x%d" % [k, left[k]])
