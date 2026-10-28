extends SceneTree
## Warlock class: Drain Life (latch, forks, healing, retarget, channel end), Blight Bolt and its
## pool, Soul Shackles, Fel Covenant, save/load and class swap.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "warlock")
	var h = g.hero
	print("[W] class ", h.cls, " warlock rig ", h.rig.has_meta("warlock"), " skills ", h.skill_list().map(func(s): return s["id"]))
	print("[W] stats str %d dex %d vit %d ene %d life %d mana %d weapon %s shield %s" % [h.str_, h.dex, h.vit, h.ene, h.max_life, h.max_mana, h.equipment["weapon"]["name"], str(h.equipment["shield"])])
	h.mana = h.max_mana
	print("[W] drain with nobody around: ", h.use_skill("drain", h.global_position + Vector3(3, 0, 0)), " channel ", h.drain_t)
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	h.level = 12
	h.recalc()
	g.test_immortal = true
	var lives := func():
		var t := 0.0
		for e in g.world.get_node("Enemies").get_children():
			t += e.life
		return t
	# find a pack: the enemy with the most neighbours
	var best = null
	var bn := -1
	for e in g.enemies_near(h.global_position, 400.0):
		var n: int = g.enemies_near(e.global_position, 5.5).size()
		if n > bn:
			bn = n
			best = e
	h.global_position = best.global_position + Vector3(6.0, 0, 0)
	await create_timer(0.3).timeout
	h.life = h.max_life * 0.5
	h.mana = h.max_mana
	var l0: float = lives.call()
	var life0: float = h.life
	var ok: bool = h.use_skill("drain", best.global_position)
	await create_timer(0.5).timeout
	# main: latched onto the pack that was aimed at (the facing assist may pick any of it)
	print("[W] drain ok=%s channel=%s main=%s victims=%d (pack of %d) beams=%d light=%s" % [ok, h.drain_t >= 0.0, h.drain_main != null and (h.drain_main == best or (h.drain_main as Node3D).global_position.distance_to(best.global_position) < 5.5), h._drain_victims().size(), bn, h.drain_beams.size(), h.drain_light != null])
	print("[W] can_act while channelling: ", h.can_act())
	var lit := func():
		return g.world.get_node("Enemies").get_children().filter(func(e): return e._drained).size()
	print("[W] polish: drained rims %d sigil %s" % [lit.call(), h.drain_sigil != null and is_instance_valid(h.drain_sigil)])
	await create_timer(0.4).timeout
	print("[W] drain damage %d healed %d" % [int(l0 - lives.call()), int(h.life - life0)])
	await create_timer(0.5).timeout
	print("[W] channel ended after tap: ", h.drain_t < 0.0, " beams left ", h.drain_beams.size(), " rims left ", lit.call(), " sigil ", h.drain_sigil)
	# retarget: kill the main victim mid-channel
	h.mana = h.max_mana
	var foes: Array = g.enemies_near(h.global_position, 11.0)
	if foes.size() >= 2:
		h.use_skill("drain", foes[0].global_position)
		await create_timer(0.2).timeout
		var first = h.drain_main
		first.take_damage(first.life * 10.0 + 9999.0, 0.0, h.global_position, 0.0, false)
		await create_timer(0.1).timeout
		print("[W] retarget after kill: ", h.drain_t >= 0.0 and h.drain_main != null and h.drain_main != first)
	else:
		print("[W] retarget after kill: skipped (", foes.size(), " foes)")
	await create_timer(1.2).timeout
	# moving breaks the channel
	h.mana = h.max_mana
	foes = g.enemies_near(h.global_position, 11.0)
	if foes.size() > 0:
		h.use_skill("drain", foes[0].global_position)
		await create_timer(0.1).timeout
		h.cmd_move(h.global_position + Vector3(0, 0, 3))
		print("[W] moving breaks channel: ", h.drain_t < 0.0)
	# Blight Bolt
	foes = g.enemies_near(h.global_position, 30.0)
	if foes.size() > 0:
		h.global_position = foes[0].global_position + Vector3(5.0, 0, 0)
		await create_timer(0.2).timeout
		h.mana = h.max_mana
		l0 = lives.call()
		h.use_skill("blight", foes[0].global_position)
		await create_timer(0.7).timeout
		print("[W] blight: bolts in flight %d pools %d damage %d" % [h.bolts.size(), h.blights.size(), int(l0 - lives.call())])
		await create_timer(2.0).timeout
		print("[W] blight pool after 2.7s: pools %d total damage %d" % [h.blights.size(), int(l0 - lives.call())])
		await create_timer(2.5).timeout
		print("[W] blight pool expired: ", h.blights.is_empty())
	# Soul Shackles
	foes = g.enemies_near(h.global_position, 40.0)
	if foes.size() > 0:
		h.global_position = foes[0].global_position + Vector3(3.0, 0, 0)
		await create_timer(0.2).timeout
		h.mana = h.max_mana
		var near: Array = g.enemies_near(h.global_position, 7.0)
		h.use_skill("shackles", h.global_position)
		await create_timer(0.6).timeout
		print("[W] shackles: %d in range, stunned %d" % [near.size(), near.filter(func(e): return is_instance_valid(e) and (e.dead or e.stun_t > 0.0)).size()])
	# Fel Covenant: more forks
	h.mana = h.max_mana
	h.use_skill("covenant", h.global_position)
	await create_timer(0.9).timeout
	print("[W] covenant: buff %.1f covenant %.1f" % [h.buff_t, h.covenant_t])
	g.save_game()
	await g.travel(0, "town", "start")
	while g._busy:
		await process_frame
	print("[W] after travel: bolts %d pools %d channel %s" % [h.bolts.size(), h.blights.size(), h.drain_t >= 0.0])
	h.set_class("knight")
	print("[W] switched to knight: covenant ", h.covenant_t, " slots ", g.ui.skill_slots.map(func(s): return (s.get_node("glyph") as Control).get("id")))
	g.load_game()
	print("[W] after load: class ", h.cls, " warlock rig ", h.rig.has_meta("warlock"), " net class ", h.net_gear().get("_cls"))
	quit()
