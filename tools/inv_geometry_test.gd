extends SceneTree
## The inventory's geometry (UI._build_inventory): every socket, label, the alcove and the gold plate sit inside
## the frame's trim without touching any of its ornament (the corner pieces' spikes, the trim), as the frame
## is actually drawn (its 9-patch, corners at their size, the edges tiled); no two sockets overlap; the bag
## has its 40 sockets and the window fits above the action bar. Prints [G] lines.
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[G] %s %s" % ["ok  " if ok else "FAIL", what])

## The frame texture pixel drawn at window point p (NinePatchRect with TILE_FIT middles).
func _tex_at(p: Vector2, W: Vector2, tw: Vector2, pm: float) -> Vector2:
	var out := Vector2.ZERO
	for ax in 2:
		var v: float = p[ax]
		var size: float = W[ax]
		var t: float = tw[ax]
		if v < pm:
			out[ax] = v
		elif v >= size - pm:
			out[ax] = t - (size - v)
		else:
			var mid_t := t - 2.0 * pm
			var mid_w := size - 2.0 * pm
			var n := maxf(1.0, roundf(mid_w / mid_t))
			var tile := mid_w / n
			out[ax] = pm + fmod(v - pm, tile) / tile * mid_t
	return out

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	var ui = g.ui
	ui.inv_panel.visible = true
	await process_frame
	var body: Control = ui.inv_panel.get_node("body")
	var frame: NinePatchRect = body.get_node("frame")
	var img: Image = frame.texture.get_image()
	var W: Vector2 = frame.size
	var tw := Vector2(img.get_width(), img.get_height())
	var pm := float(frame.patch_margin_left)
	var origin: Vector2 = body.get_global_rect().position
	# the frame's ornament: its bright or warm (bronze) pixels, where most of the 5 x 5 around are too (the
	# plain iron inside is dark and grey, its odd scratch doesn't count)
	var iw := int(tw.x)
	var ih := int(tw.y)
	var sat := PackedInt32Array()
	sat.resize((iw + 1) * (ih + 1))
	for y in ih:
		var row := 0
		for x in iw:
			var c := img.get_pixel(x, y)
			if (c.r + c.g + c.b) / 3.0 > 0.245 or c.r - c.b > 0.075:
				row += 1
			sat[(y + 1) * (iw + 1) + x + 1] = sat[y * (iw + 1) + x + 1] + row
	var ornament := func(p: Vector2) -> bool:
		var t := _tex_at(p, W, tw, pm)
		var x0 := clampi(int(t.x) - 2, 0, iw - 5)
		var y0 := clampi(int(t.y) - 2, 0, ih - 5)
		var n := sat[(y0 + 5) * (iw + 1) + x0 + 5] - sat[y0 * (iw + 1) + x0 + 5] - sat[(y0 + 5) * (iw + 1) + x0] + sat[y0 * (iw + 1) + x0]
		return n >= 13
	var items := []
	for k in ui.equip_cells.keys():
		items.append([k, (ui.equip_cells[k] as Control).get_global_rect()])
	for i in ui.inv_cells.size():
		items.append(["bag %d" % i, (ui.inv_cells[i] as Control).get_global_rect()])
	var captions := body.get_children().filter(func(c): return c.get_class() == "Control" and c.get("text") != null and c.get("font") != null)
	for c in captions:
		items.append(["label " + str(c.text), (c as Control).get_global_rect()])
	items.append(["alcove", Rect2(ui.INV_ALCOVE.position - Vector2(3, 3) + origin, ui.INV_ALCOVE.size + Vector2(6, 6))])
	items.append(["gold plate", Rect2(ui.INV_PLATE.position + origin, ui.INV_PLATE.size)])
	var bad := []
	var worst := 0
	for it in items:
		var r: Rect2 = it[1]
		var hits := 0
		var y := r.position.y
		while y < r.end.y:
			var x := r.position.x
			while x < r.end.x:
				if ornament.call(Vector2(x, y) - origin):
					hits += 1
					if hits == 1:
						print("[G]   first hit for %s at %s (tex %s)" % [it[0], Vector2(x, y) - origin, _tex_at(Vector2(x, y) - origin, W, tw, pm)])
				x += 1.0
			y += 1.0
		if hits > 0:
			bad.append("%s (%d px, rect %s)" % [it[0], hits, Rect2(r.position - origin, r.size)])
			worst = maxi(worst, hits)
	check(bad.is_empty(), "nothing touches the frame's ornament or trim (%d pieces checked)%s" % [items.size(), "" if bad.is_empty() else ": " + ", ".join(bad)])
	# the sockets don't overlap one another, and the labels sit clear of every socket
	var rects := items.filter(func(it): return not str(it[0]) in ["alcove", "gold plate"] and not str(it[0]).begins_with("label")).map(func(it): return it[1])
	var overl := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j]):
				overl += 1
	check(overl == 0, "no two sockets overlap (%d pairs)" % overl)
	var lab_hits := 0
	for c in captions:
		for r in rects:
			if (c as Control).get_global_rect().intersects(r):
				lab_hits += 1
				print("[G]   label %s %s runs into %s" % [c.text, (c as Control).get_global_rect(), r])
	check(captions.size() == 10 and lab_hits == 0, "the 10 labels sit clear of every socket (%d touching)" % lab_hits)
	check(ui.inv_cells.size() == 40 and ui.equip_cells.size() == 10, "40 bag sockets, 10 equipment sockets")
	var bar_top: float = (ui.action_bar as Control).get_global_rect().position.y
	check(ui.inv_panel.get_global_rect().end.y <= bar_top + 2.0, "the window ends above the action bar (%.0f, bar at %.0f)" % [ui.inv_panel.get_global_rect().end.y, bar_top])
	print("[G] done, %d failed" % fails)
	quit()
