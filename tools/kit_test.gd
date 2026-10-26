extends SceneTree
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(n: int) -> void:
	for i in n:
		await process_frame
func _run() -> void:
	await wait(30)
	while g._busy:
		await wait(5)
	await g.start_game(false)
	var h = g.hero
	print("[K] before: lvl %d life %d dmg %d-%d armor %d" % [h.level, h.max_life, h.dmg_min, h.dmg_max, h.armor])
	g.give_test_gear()
	print("[K] after:  lvl %d life %d mana %d dmg %d-%d armor %d aspd %.2f ls %d res %d frw %d block %.0f gold %d" % [h.level, h.max_life, h.max_mana, h.dmg_min, h.dmg_max, h.armor, h.aspd, h.ls, h.res, h.frw, h.block_chance, h.gold])
	for s in Items.EQUIP_SLOTS:
		var it = h.equipment[s]
		print("[K]  ", s, ": ", it["name"], " +", it.get("ench", 0))
	g.give_test_gear()
	var n := 0
	for it in h.inventory:
		if it != null: n += 1
	print("[K] inventory items after second press: ", n)
	g.set_sound(false)
	print("[K] master muted: ", AudioServer.is_bus_mute(0), " saved: ", g._load_setting("audio", "sound_on", true), " quality kept: ", g._load_setting("graphics", "quality", -1))
	g.set_sound(true)
	print("[K] master muted: ", AudioServer.is_bus_mute(0))
	quit()
