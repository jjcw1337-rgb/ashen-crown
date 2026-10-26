extends SceneTree
func _initialize():
	var out := []
	for d in [0, 3]:
		World.detail = d
		var w := World.new()
		get_root().add_child(w)
		w.build(0, "wild", 4200 + 7)
		var sig := []
		for it in w.interactables:
			sig.append([it.kind, snapped(it.global_position.x, 0.01), snapped(it.global_position.z, 0.01)])
		for es in w.enemy_spawns:
			sig.append([es["kind"], snapped(es["pos"].x, 0.01), es["count"]])
		var grass := 0
		for c in w.props_root.get_children():
			if c is MultiMeshInstance3D and c.is_in_group("grass"):
				grass += c.multimesh.instance_count
		out.append([sig, grass])
		w.free()
	print("[D] layout identical Low vs Ultra: ", out[0][0] == out[1][0], "  grass+ferns Low=", out[0][1], " Ultra=", out[1][1])
	quit()
