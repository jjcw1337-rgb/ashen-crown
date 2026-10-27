extends SceneTree
## Potions: pickups fill the belt, then stack in the inventory (20 a cell); moving a stack to
## the belt keeps the rest; dropping one stack on another merges; loose potions from old
## saves merge on load; selling a stack pays for every potion.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	var h = g.hero
	for i in 30:
		h.add_to_inventory(Items.potion("hp_potion"))
	var cells: Array = h.inventory.filter(func(it): return it != null and it["base"] == "hp_potion")
	print("[P] 30 picked up: belt %s, inventory cells %d with %s" % [str(h.belt.map(func(b): return [b["base"], b["count"]] if b != null else null)), cells.size(), str(cells.map(func(c): return c["count"]))])
	# drink from the belt, then move the inventory stack onto the belt
	for k in 3:
		h.drink(0)
	var idx: int = h.inventory.find(cells[0])
	var before: int = cells[0]["count"]
	h.equip_from_inventory(idx)
	print("[P] stack of %d to the belt: belt slot 0 has %d, inventory keeps %d" % [before, h.belt[0]["count"], h.inventory[idx]["count"] if h.inventory[idx] != null else 0])
	# loose potions (old save) merge on load
	h.inventory = []
	h.inventory.resize(40)
	for i in 5:
		var p := Items.potion("mp_potion")
		h.inventory[i * 3] = p
	h.stack_potions()
	var mp: Array = h.inventory.filter(func(it): return it != null and it["base"] == "mp_potion")
	print("[P] 5 loose mana potions merged into %d cell(s) of %s" % [mp.size(), str(mp.map(func(c): return c["count"]))])
	# drag one stack onto another
	h.inventory[30] = Items.potion("mp_potion")
	h.inventory[30]["count"] = 4
	var at: int = h.inventory.find(mp[0])
	h.move_in_inventory(30, at)
	print("[P] dropped 4 onto the stack: %d, source cell empty %s" % [h.inventory[at]["count"], h.inventory[30] == null])
	print("[P] selling a stack of %d pays %d" % [h.inventory[at]["count"], Items.sell_price(h.inventory[at])])
	quit()
