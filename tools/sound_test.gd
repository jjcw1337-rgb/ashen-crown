extends SceneTree
## Every class skill plays its own sounds (sfx.counts), monsters get layered impacts, crits a sting,
## kills a death sound by material, and the hero a hurt voice per body. Also checks every bank sound
## loaded. Prints [S] lines; "missing" lists expected sounds that never played.
var g
var sfx
const EXPECT := {
	"knight": {"cleave": ["cleave_swing", "impact_flesh"], "nova": ["holy_nova"], "charge": ["charge_dash"], "cry": ["battle_cry"]},
	"wraith": {"reap": ["reap_swing"], "wail": ["wail"], "shade": ["shade_in", "shade_out"], "host": ["host_summon"]},
	"demon": {"hellclaw": ["hellclaw"], "summon": ["summon_demon"], "phase": ["phase_in"], "pact": ["blood_pact"]},
	"warlock": {"drain": ["drain_start"], "blight": ["blight_cast"], "shackles": ["shackles"], "covenant": ["covenant"]},
}
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(s: float) -> void:
	await create_timer(s).timeout
func _run() -> void:
	sfx = get_root().get_node("Sfx")
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	var missing_bank := []
	for nm in sfx.BANK.keys():
		if not sfx.bank.has(nm) or (sfx.bank[nm] as Array).size() != int(sfx.BANK[nm][0]):
			missing_bank.append(nm)
	print("[S] bank: %d sounds loaded, missing %s" % [sfx.bank.size(), missing_bank])
	var buses := []
	for i in AudioServer.bus_count:
		buses.append("%s>%s" % [AudioServer.get_bus_name(i), AudioServer.get_bus_send(i)])
	print("[S] buses: %s" % [buses])
	# a cast's payoff lands on the impact frame: holy_nova's payoff is 0.3 s in, so for an impact 0.6 s away it
	# waits 0.3 s; for one 0.2 s away it starts at once, 0.1 s into the sound
	sfx.play_synced("holy_nova", 0.6)
	var queued: float = sfx._pending[0][0] if not sfx._pending.is_empty() else -1.0
	var n0 := int(sfx.counts.get("holy_nova", 0))
	sfx.play_synced("holy_nova", 0.2)
	var now := int(sfx.counts.get("holy_nova", 0)) - n0
	var p: AudioStreamPlayer = sfx.players[(sfx._next - 1 + sfx.players.size()) % sfx.players.size()]
	print("[S] synced: payoff %.2f s; impact in 0.6 s waits %.2f s; impact in 0.2 s plays now %s from %.2f s" % [sfx.hit_of("holy_nova"), queued, now == 1, p.get_playback_position() if p.playing else -1.0])
	for cls in EXPECT.keys():
		await g.start_game(false, cls)
		g.ui.close_all()
		await g.load_zone(0, "wild", "road")
		g.ui.close_all()
		g.test_immortal = true
		var h = g.hero
		h.level = 12
		h.recalc()
		h.mana = h.max_mana
		var bad := []
		for sk in EXPECT[cls].keys():
			for e in g.enemies_near(h.global_position, 30.0):
				e.queue_free()
			await process_frame
			for i in 3:
				var e = g.spawn_enemy("zombie", h.global_position + Vector3(-1.2 + i * 1.2, 0, -2.2), 3)
				e.aggro = false
			await wait(0.2)
			sfx.counts.clear()
			for k in h.cds.keys():
				h.cds[k] = 0.0
			h.mana = h.max_mana
			h.use_skill(sk, h.global_position + Vector3(0, 0, -2.5))
			await wait(1.4)
			h.end_drain() if h.has_method("end_drain") else null
			h.end_phase(false) if h.has_method("end_phase") else null
			var miss := (EXPECT[cls][sk] as Array).filter(func(n): return not sfx.counts.has(n))
			if not miss.is_empty():
				bad.append("%s:%s" % [sk, miss])
		print("[S] %s skills: %d, missing %s" % [cls, (EXPECT[cls] as Dictionary).size(), bad])
	# combat: a crit, a kill by material, the hero hurt
	sfx.counts.clear()
	var z = g.spawn_enemy("zombie", g.hero.global_position + Vector3(0, 0, -2), 1)
	z.take_damage(5.0, 0.0, g.hero.global_position, 0.5, true)
	z.take_damage(9999.0, 0.0, g.hero.global_position, 0.5, false)
	var sk = g.spawn_enemy("skel_archer", g.hero.global_position + Vector3(2, 0, -2), 1)
	sk.take_damage(9999.0, 0.0, g.hero.global_position, 0.5, false)
	g.test_immortal = false
	g.hero.life = g.hero.max_life
	g.hero.take_hit(3.0, g.hero.global_position + Vector3(0, 0, -1), "melee")
	await wait(0.2)
	var want := ["impact_flesh", "crit_sting", "kill_flesh", "impact_bone", "kill_bone", "hurt_gnome"]
	print("[S] combat: %s, missing %s" % [sfx.counts.keys(), want.filter(func(n): return not sfx.counts.has(n))])
	quit()
