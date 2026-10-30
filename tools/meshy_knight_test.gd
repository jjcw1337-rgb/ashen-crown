extends SceneTree
## The knight's bodies: the Meshy shirt-and-shorts body with no armour, the Meshy plate with armour,
## and the helm toggle (hidden helm: no helm model, stats kept; saved, and sent to co-op partners).
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func helm_drawn(h) -> bool:
	for n in (h.J["head"] as Node3D).get_children():
		if n in h.gear_nodes:
			return true
	return false
func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	var h = g.hero
	h.equipment.erase("armor")
	h.refresh_gear()
	await process_frame
	print("[M] no armour -> plain meshy body: ", h.rig.get_meta("meshy", "") == "plain")
	h.equipment["armor"] = {"base": "chain_mail", "rarity": 0, "affixes": [], "stats": {}}
	h.refresh_gear()
	await process_frame
	print("[M] armour -> armoured meshy body: ", h.rig.get_meta("meshy", "") == "armored", " cape bones ", (h.rig.get("hair_bones") as Array).size())
	var helm := Items.generate(Items.pick_base(5, RandomNumberGenerator.new(), "helm"), 5, 0, RandomNumberGenerator.new())
	h.equipment["helm"] = helm
	h.show_helm = true
	h.refresh_gear()
	h.recalc()
	var arm_shown: int = h.armor
	var drawn := helm_drawn(h)
	h.show_helm = false
	h.refresh_gear()
	h.recalc()
	print("[M] helm shown draws it: ", drawn, "  hidden draws none: ", not helm_drawn(h), "  stats kept: ", h.armor == arm_shown and arm_shown > 0)
	var d: Dictionary = h.to_save()
	print("[M] saved show_helm: ", d.get("show_helm", true) == false, "  net gear carries it: ", h.net_gear().get("_helm", true) == false)
	h.show_helm = true
	h.equipment.erase("armor")
	h.refresh_gear()
	for i in 30:
		h.cmd_move(h.global_position + Vector3(3, 0, 0))
		await process_frame
	print("[M] back to plain and moving ok: ", h.rig.get_meta("meshy", "") == "plain", " J head ok: ", is_instance_valid(h.J["head"]))
	# running, the weapon is carried head up at a steady slant, not turning with the arm's pump
	for body in ["plain", "armored"]:
		if body == "armored":
			h.equipment["armor"] = {"base": "chain_mail", "rarity": 0, "affixes": [], "stats": {}}
		h.equipment["weapon"] = Items.make("hand_axe", 0, 1)
		h.refresh_gear()
		await process_frame
		var lo := 1.0
		var hi := -1.0
		var start: Vector3 = h.global_position
		for i in 90:
			h.cmd_move(start + Vector3(30, 0, 0), true)
			await process_frame
			if i > 30 and h.weapon_node != null:
				var blade: Vector3 = -h.weapon_node.global_transform.basis.z.normalized()
				lo = minf(lo, blade.y)
				hi = maxf(hi, blade.y)
		h.cmd_move(h.global_position)
		print("[M] %s running: the axe's head stays up (blade up %.2f .. %.2f, %s)" % [body, lo, hi, "ok" if lo > 0.5 else "FAIL"])
	quit()
