extends SceneTree
## The shipwright on the Mournwater Coast (coast.gd, boat_shop.gd, Game._shipwright_talk / buy_boat): Osric
## stands at his boathouse with a nameplate and a minimap mark, talking to him opens his dialogue, "See
## the boat" opens the boat window (portrait, boat, price, how to sail); without the gold the purchase
## is refused; with it the boat is bought, paid for and owned; ownership survives saving and loading;
## walking away closes the window; the boat for sale lies alongside the pier.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func frames(n: int) -> void:
	for i in n:
		await process_frame
func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.load_zone(0, "coast", "from_town")
	var w = g.world
	var osric: Inter = null
	for it in w.interactables:
		if it.kind == "vendor" and str(it.data.get("role", "")) == "shipwright":
			osric = it
	print("[B] shipwright: %s '%s' (%s), boat moored at the pier %s" % [osric != null, osric.label if osric else "", VendorUI.title_for(osric) if osric else "", w.has_meta("moored_boat")])
	var path: PackedVector3Array = w.find_path(w.spawns["start"], w.spawns["shipwright"])
	print("[B] walkable from the camp path to him: %s" % (path.size() > 0))
	g.hero.gold = 150
	g.hero.boats = []
	g.hero.global_position = w.spawns["shipwright"]
	g._interact(osric)
	await frames(3)
	print("[B] talk: dialogue open %s, title '%s'" % [g.ui.dialog_panel.visible, g.ui.dialog_name.text])
	var see: Button = g.ui.dialog_btns.get_child(0)
	see.pressed.emit()
	await frames(5)
	var bs: BoatShop = g.ui.boat_shop
	print("[B] boat window open %s: '%s' %s, buy button '%s', portrait %s" % [g.ui.boat_panel.visible, bs.name_lbl.text, bs.price_lbl.text, bs.buy_btn.text, bs.face.get_child_count() > 0])
	bs.buy_btn.pressed.emit()
	await frames(2)
	print("[B] with 150 gold: owned %s, gold %d (refused, unchanged)" % [g.hero.owns_boat("gull"), g.hero.gold])
	g.hero.gold = 1000
	bs.refresh()
	bs.buy_btn.pressed.emit()
	await frames(2)
	print("[B] with 1000 gold: owned %s, gold %d (paid %d), button '%s' disabled %s" % [g.hero.owns_boat("gull"), g.hero.gold, 1000 - g.hero.gold, bs.buy_btn.text, bs.buy_btn.disabled])
	bs.buy_btn.pressed.emit()
	print("[B] buying again: gold still %d" % g.hero.gold)
	g.save_game()
	g.hero.boats = []
	g.load_game()
	print("[B] saved and loaded: owned %s, gold %d" % [g.hero.owns_boat("gull"), g.hero.gold])
	g.hero.global_position = w.spawns["start"]
	await frames(4)
	print("[B] walked away: window closed %s" % (not g.ui.boat_panel.visible))
	g._interact(osric)
	await frames(2)
	print("[B] talking again once owned: '%s'" % g.ui.dialog_text.text.substr(0, 40))
	quit()
