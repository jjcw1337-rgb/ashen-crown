extends SceneTree
## The camp's traders, stash and bonfire can be clicked and reached from every side (jj: Agnes couldn't be clicked
## from beside or behind her stall): for each class in CLASSES the hero stands at 8 points round each one, the
## mouse ray through its pick point must find it (Game.pick_inter), and walking to it must open it (Game._interact:
## ui.trade_with, or the stash / bonfire window) within 8 s. Prints [R] lines, one FAIL per class, place and side.
## godot --headless --path . -s tools/npc_reach_test.gd [-- knight demon ...]
var g
var fails := 0
const CLASSES := ["knight", "demon", "plague"]
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("[R] FAIL ", what)
func _run() -> void:
	var classes: Array = OS.get_cmdline_user_args() if not OS.get_cmdline_user_args().is_empty() else CLASSES
	while g.world == null or g._busy:
		await process_frame
	for cls in classes:
		await g.start_game(false, cls)
		while g._busy:
			await process_frame
		g.ui.close_all()
		var h = g.hero
		var targets := []
		for it in g.world.interactables:
			if is_instance_valid(it) and it.kind in ["vendor", "stash", "bonfire"]:
				targets.append(it)
		var ok_n := 0
		var n := 0
		for it in targets:
			for k in 8:
				var a := TAU * k / 8.0
				var want: Vector3 = it.global_position + Vector3(sin(a), 0, cos(a)) * 4.5
				var at: Vector3 = g.world.free_spot_near(want, 0.8)
				g.ui.close_all()
				g.ui.trade_with = null
				g.ui.dialog_panel.visible = false
				h.target = null
				h.moving = false
				h.path = PackedVector3Array()
				h.global_position = at
				for f in 3:
					await process_frame
				# the mouse ray through its pick point, from the game camera where the hero stands now
				var py: float = float(it.get_meta("pick_y")) if it.has_meta("pick_y") else 1.0
				var sp: Vector2 = g.cam.unproject_position(it.global_position + Vector3(0, py, 0))
				var picked = g.pick_inter(g.cam.project_ray_origin(sp), g.cam.project_ray_normal(sp))
				n += 1
				var side := "%d°" % int(rad_to_deg(a))
				check(picked == it, "%s: %s from %s: the mouse finds %s" % [cls, it.label, side, picked.label if picked != null else "nothing"])
				# walk to it
				h.target = it
				var end := Time.get_ticks_msec() + 8000
				var opened := false
				while Time.get_ticks_msec() < end:
					await process_frame
					if g.ui.trade_with == it or g.ui.stash_panel.visible or (it.kind == "bonfire" and g.ui.burn_panel.visible) or g.ui.dialog_panel.visible:
						opened = true
						break
				var d: float = Vector2(h.global_position.x - it.global_position.x, h.global_position.z - it.global_position.z).length()
				check(opened, "%s: %s from %s: walking to it never opened it (stopped %.1f m away, its reach %.1f)" % [cls, it.label, side, d, it.radius])
				if opened and picked == it:
					ok_n += 1
		print("[R] %s: %d of %d sides fine" % [cls, ok_n, n])
	print("[R] done, %d failed" % fails)
	quit()
