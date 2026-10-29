extends SceneTree
## Clicks a grid of points over every open window and checks none of them reaches the world
## (a click on a menu must never walk the hero or attack).
var g
var reached := false
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(n: int) -> void:
	for i in n:
		await process_frame
func _click(p: Vector2) -> void:
	var vp := get_root()
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	vp.push_input(m, true)
	await process_frame
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	e.global_position = p
	g.lmb_held = false
	vp.push_input(e, true)
	reached = g.lmb_held        # set only when the press got past the GUI to the game
	var u := e.duplicate()
	u.pressed = false
	vp.push_input(u, true)
	await process_frame
## The deepest visible, drawn Control under pt (not text, which floats over the map, nor plain
## containers), or "" when only the map is there.
func _drawn_at(c: Node, pt: Vector2) -> String:
	if c is CanvasItem and not (c as CanvasItem).visible:
		return ""
	var kids := c.get_children()
	kids.reverse()
	for k in kids:
		var r := _drawn_at(k, pt)
		if r != "":
			return r
	if c is Control and c != g.ui.root and (c as Control).get_global_rect().has_point(pt):
		var ctl := c as Control
		var drawn := ctl is TextureRect or ctl is Panel or ctl is PanelContainer or ctl is BaseButton or ctl is ColorRect or ctl is ProgressBar or ctl is TextureProgressBar
		if ctl is ColorRect and (ctl as ColorRect).color.a < 0.05:
			drawn = false
		# a globe is round: the clear corners of its frame are map
		var gl := ctl.get_parent() as Globe
		if gl and not gl._has_point(gl.get_global_transform().affine_inverse() * pt):
			drawn = false
		if drawn and ctl.get_global_rect().size.x < vs_w() * 0.9:
			return "%s %s" % [g.ui.root.get_path_to(ctl), Rect2i(ctl.get_global_rect())]
	return ""
func vs_w() -> float:
	return get_root().get_visible_rect().size.x
func _run() -> void:
	await wait(30)
	while g._busy:
		await wait(5)
	await g.start_game(false)
	await wait(20)
	var h = g.hero
	var panels := {"inventory": g.ui.inv_panel, "character": g.ui.char_panel, "skills": g.ui.skills_panel,
		"talents": g.ui.talent_panel, "stash": g.ui.stash_panel, "waypoints": g.ui.wp_panel, "merchant": g.ui.shop_panel}
	var bad := 0
	for nm: String in panels:
		var p: Control = panels[nm]
		g.ui.close_all()
		p.visible = true
		await wait(4)
		var r: Rect2 = p.get_global_rect()
		var leaks := []
		for ix in range(1, 12):
			for iy in range(1, 12):
				if not p.visible:
					p.visible = true
					await wait(2)
				var pt := r.position + r.size * Vector2(ix / 12.0, iy / 12.0)
				h.moving = false
				h.target = null
				h.path = PackedVector3Array()
				await _click(pt)
				if reached:
					leaks.append(Vector2i(pt))
				g.lmb_held = false
		bad += leaks.size()
		print("[U] ", nm, " rect=", Vector2i(r.size), " leaks=", leaks.size(), " ", leaks.slice(0, 6))
	# a dialog (an NPC's) and the enchanting window (the pause menu stops all play input itself)
	for nm: String in ["dialog", "enchant"]:
		g.ui.close_all()
		var p: Control
		if nm == "dialog":
			g.ui.open_dialog("Varro", "Fight for me.", [["Later", func(): pass]])
			p = g.ui.dialog_panel
		elif nm == "enchant":
			p = g.ui.ench_panel
			p.visible = true
		await wait(4)
		var r: Rect2 = p.get_global_rect()
		var n := 0
		for ix in range(1, 8):
			for iy in range(1, 8):
				var pt := r.position + r.size * Vector2(ix / 8.0, iy / 8.0)
				await _click(pt)
				n += int(reached)
		p.visible = false
		bad += n
		print("[U] ", nm, " leaks=", n)
	# the skill menu (click a bar slot): pick an item, and dismiss it by clicking outside
	for how: String in ["pick", "outside"]:
		g.ui.close_all()
		await wait(2)
		g.ui._choose_skill("Q")
		await wait(4)
		var pm: PopupMenu = null
		for c in g.ui.root.get_children():
			if c is PopupMenu:
				pm = c
		var pr := Rect2(pm.position, pm.size)
		var pt: Vector2 = pr.get_center() if how == "pick" else pr.position + Vector2(pr.size.x + 200, pr.size.y * 0.5)
		await _click(pt)
		await wait(3)
		bad += int(reached)
		print("[U] skill menu ", how, ": reaches the game=", reached, " menu still open=", is_instance_valid(pm) and pm.visible)
		if is_instance_valid(pm):
			pm.hide()
	# the HUD with no window open: a click on any drawn part of it (bar, globes, buttons, minimap)
	# must not walk; a click on the bare map must
	g.ui.close_all()
	await wait(2)
	var vs := Vector2(get_root().get_visible_rect().size)
	var hud_leaks := {}
	for ix in range(1, 40):
		for iy in range(1, 24):
			var pt := vs * Vector2(ix / 40.0, iy / 24.0)
			var over := _drawn_at(g.ui.root, pt)
			if over == "":
				continue
			await _click(pt)
			if reached:
				hud_leaks[over] = int(hud_leaks.get(over, 0)) + 1
	bad += hud_leaks.size()
	print("[U] HUD leaks: ", hud_leaks)
	g.ui.close_all()
	await wait(2)
	var mid := Vector2(get_root().get_visible_rect().size) * Vector2(0.5, 0.35)
	h.moving = false
	await _click(mid)
	print("[U] a click on the map with no window open reaches the game: ", reached)
	print("[U] done, ", bad, " leaks")
	quit()
