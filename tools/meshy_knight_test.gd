extends SceneTree
## The knight switches to the Meshy body with no armour and back to the armoured body with armour.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "knight")
	var h = g.hero
	h.equipment.erase("armor")
	h.refresh_gear()
	await process_frame
	print("[M] no armour -> meshy body: ", h.rig.has_meta("meshy"))
	h.equipment["armor"] = {"base": "chain_mail", "rarity": 0, "affixes": [], "stats": {}}
	h.refresh_gear()
	await process_frame
	print("[M] armour -> armoured body: ", not h.rig.has_meta("meshy"))
	h.equipment.erase("armor")
	h.refresh_gear()
	for i in 30:
		h.cmd_move(h.global_position + Vector3(3, 0, 0))
		await process_frame
	print("[M] back to meshy and moving ok: ", h.rig.has_meta("meshy"), " J head ok: ", is_instance_valid(h.J["head"]))
	quit()
