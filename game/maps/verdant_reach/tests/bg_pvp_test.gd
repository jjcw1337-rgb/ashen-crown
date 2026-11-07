extends SceneTree
## Battlegrounds PvP, three processes:
##   godot --headless --path . -s game/maps/verdant_reach/tests/bg_pvp_test.gd -- --server --port 24671 --raid-fast server
##   godot --headless --path . -s game/maps/verdant_reach/tests/bg_pvp_test.gd -- a 24671 [addr <host>] [cloud <nakama url> <server key>]
##   godot --headless --path . -s game/maps/verdant_reach/tests/bg_pvp_test.gd -- b 24671 [addr <host>] [cloud <nakama url> <server key>]
## Two real characters enter the crypt. On a's screen b is an invisible stand-in target (Battlegrounds.sync_proxies);
## a walks up to b and swings at it: b's life drops through the server (Net.sv_pvp_hit, PVP_MULT) until b falls.
## b's gear drops, the server announces who killed whom, and a picks b's things up. Both raid as run characters
## (RunBuild, the multiplayer overhaul: fresh at level 0, each given its class's first skill here); b's saved
## character is untouched by the fall. Fallen, b spectates a (the camera on a) until a leaves, then leaves the crypt.
## With "doug" after the port on both players' lines, a plays Doug: his first skill is the Cream Pie, and b checks it
## was Pied by it (the crowd control crossing to another player: DougSkills._cc -> Net.send_pvp_effect).
## With "archer" instead, a plays the Archer and drops Thunderstep's sigil on b, and b checks it was stunned for its
## three seconds (Thunderstep -> PvpStatus "stagger" -> the server -> b). His skills, his wolf and his rites run on
## the server (ServerRules): the server checks it made them; a checks its own game holds none.
## With "warlock" instead, a plays the Warlock: Drain Life (her first skill) on b, then Corruption and Terrify. Her
## skills run on the server: the server checks it made them and that her curse ticks there; a checks its own game holds
## no curse, fright or drain and that the drain's life came back to it from the server; b checks it was hurt and
## frightened through the server, and that her spells were aimed at it on its screen.
## With "dragon <wyrm|serpent|wyvern>" instead (on all three lines), a plays that dragon and uses every skill of its
## kit and its run's on b, each from where it reaches (the Obsidian Wyrm has none yet: only its claws). A dragon's
## skills run on the server: the server checks it made them and that its copy of a decides a's hits; a checks its own
## game keeps none of their state (no breath held, no tomb, no cloud) and doesn't decide its hits; b checks it was
## hurt, staggered and slowed through the server, and that the skills were aimed at it on its screen.

var g
var role := "a"
var port := 24671
var host := "127.0.0.1"
var fails := 0

## The dragon modes: each dragon's skills (its own, then its run's), how far from the other player a casts each, and
## how long each takes to play out.
const DRAGON_SKILLS := {"wyrm": [], "serpent": ["frost_breath", "s_tomb", "s_coil", "s_lance"],
	"wyvern": ["storm_arc", "v_dive", "v_cloud", "v_gale"]}
const DRAGON_FROM := {"frost_breath": 3.0, "s_tomb": 6.0, "s_coil": 2.0, "s_lance": 4.0, "storm_arc": 5.0, "v_dive": 8.0,
	"v_cloud": 7.0, "v_gale": 3.0}
const DRAGON_WAIT := {"frost_breath": 1.8, "s_tomb": 2.4, "s_coil": 1.4, "s_lance": 1.4, "storm_arc": 1.2, "v_dive": 1.4,
	"v_cloud": 2.0, "v_gale": 1.2}

## The dragon this run plays ("dragon <class>"), or "".
func _dragon() -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find("dragon")
	return str(a[i + 1]) if i >= 0 and i + 1 < a.size() and DRAGON_SKILLS.has(a[i + 1]) else ""

func _initialize():
	var a := OS.get_cmdline_user_args()
	role = "server" if a.has("server") else ("b" if a.has("b") else "a")
	for i in a.size():
		if a[i].is_valid_int() and int(a[i]) > 1024:
			port = int(a[i])
	if role != "server":
		Battlegrounds.id_path = "user://bg_pvp_%s_%d_id.txt" % [role, port]      # (per port: other runs at once don't collide)
		DirAccess.remove_absolute(Battlegrounds.id_path)
		var ai := a.find("addr")
		if ai >= 0 and ai + 1 < a.size():
			host = a[ai + 1]
		var ci := a.find("cloud")
		if ci >= 0 and ci + 2 < a.size():
			BuildEnv.forced = {"cloud": "1", "nakama_url": a[ci + 1], "nakama_key": a[ci + 2]}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[%s] %s%s" % [role.to_upper(), "ok   " if ok else "FAIL ", what])

func wait(n: int) -> void:
	for i in n:
		await process_frame

func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

func until(f: Callable, t: float) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		if f.call():
			return true
		await process_frame
	return false

func _run() -> void:
	Engine.max_fps = 60
	await wait(30)
	if role == "server":
		await _server()
	else:
		await _player()
	print("[%s] done, %d failed" % [role.to_upper(), fails])
	quit()

func _server() -> void:
	await until(func(): return g.bg != null and g.net.active and not g._busy, 40.0)
	check(await until(func(): return g.net.players.size() == 2, 60.0), "both players are in the crypt")
	check(await until(func(): return g.bg.last_hit.size() > 0, 60.0), "a player struck another (through the server)")
	if OS.get_cmdline_user_args().has("archer"):
		check(await until(func(): return ServerRules.made_count >= 3, 30.0), "the Archer's skills ran here: the server made his arrow, his sigil and his flask's burst (%d)" % ServerRules.made_count)
		var arch = g.net.players.values().map(func(p): return p["hero"]).filter(func(h): return is_instance_valid(h) and h.cls == "archer")
		check(not arch.is_empty() and arch[0].decides() and await until(func(): return arch[0].beasts.any(func(w): return is_instance_valid(w) and w._deals()), 10.0), "his wolf runs here too, the one that bites, and his rites fire here (Hero.decides)")
		# thorns: a server-run hero's game can only claim a blow the server sent it, once
		var vic: int = int(g.net.players.keys().filter(func(pid): return g.net.players[pid]["hero"].cls != "archer")[0])
		await until(func(): return not g.net._blows_sent.get(vic, []).is_empty(), 30.0)
		check(g.net.took_blow(vic, 1.0) and not g.net.took_blow(vic, 1e9), "a blow the server sent counts for thorns, a made-up one doesn't")
	if OS.get_cmdline_user_args().has("warlock"):
		var wl = g.net.players.values().map(func(p): return p["hero"]).filter(func(h): return is_instance_valid(h) and h.cls == "warlock")
		check(not wl.is_empty() and wl[0].decides(), "the Warlock's copy here decides her hits (Hero.decides)")
		var cursed := false
		var t_end := Time.get_ticks_msec() + 40000
		while Time.get_ticks_msec() < t_end and not cursed:
			cursed = not wl.is_empty() and is_instance_valid(wl[0]) and wl[0].kit.has("hex") and not wl[0].kit["hex"].dots.is_empty()
			await process_frame
		check(cursed, "her curse ticks here, on the other player's stand-in")
		check(await until(func(): return ServerRules.made_count >= 3, 30.0), "the Warlock's skills ran here: the server made her drain's latch, her curse and her fright (%d made, %d refused)" % [ServerRules.made_count, ServerRules.refused_count])
	var dcls := _dragon()
	if dcls != "":
		var drg = g.net.players.values().map(func(p): return p["hero"]).filter(func(h): return is_instance_valid(h) and h.cls == dcls)
		check(not drg.is_empty() and drg[0].decides(), "the %s's copy here decides its hits (Hero.decides)" % dcls)
		var n_sk: int = (DRAGON_SKILLS[dcls] as Array).size()
		if n_sk > 0:
			check(await until(func(): return ServerRules.made_count >= n_sk, 40.0), "the %s's skills ran here: the server made %s (%d made, %d refused)" % [dcls, str(DRAGON_SKILLS[dcls]), ServerRules.made_count, ServerRules.refused_count])
	check(await until(func(): return g.bg.died_items.size() > 0, 60.0), "and killed them: their body dropped its gear")
	await until(func(): return g.net.players.is_empty(), 90.0)

func _player() -> void:
	while g._busy:
		await wait(5)
	await secs(2.0 if role == "a" else 4.0)
	g.char_dir = "user://bg_pvp_%s_%d_chars/" % [role, port]
	DirAccess.make_dir_recursive_absolute(g.char_dir)
	for fn in DirAccess.get_files_at(g.char_dir):
		DirAccess.remove_absolute(g.char_dir + fn)
	var doug := OS.get_cmdline_user_args().has("doug")
	var archer := OS.get_cmdline_user_args().has("archer")
	var warlock := OS.get_cmdline_user_args().has("warlock")
	var dcls := _dragon()
	g.hero.set_class(("doug" if doug else ("archer" if archer else ("warlock" if warlock else "knight"))) if role == "a" else "wraith")
	if role == "a" and dcls != "":
		g.hero.set_class(dcls)
	g.hero.new_character()
	g.hero.set_level(8)
	g.char_id = g.new_char_id()
	g.char_name = "Attacker" if role == "a" else "Victim"
	g.net.my_name = g.char_name
	g.save_game()
	var path: String = g.char_dir + g.char_id + ".json"
	await g.start_battlegrounds("%s:%d" % [host, port], g.char_id)
	check(await until(func(): return g.cur_zone == Battlegrounds.ZONE and not g._busy and not g.net.loading, 30.0), "entered the crypt")
	var inv_saved := _saved_items(path)
	if g.hero.run != null and not g.hero.skill_list().is_empty():      # (the Obsidian Wyrm has none yet)
		g.hero.run.add_skill(str(g.hero.skill_list()[0]["id"]), g.hero.binds)     # (as a camp chest would give it)
		g.hero.run_changed()
	# a round starts in the antechambers, PvP off behind the gates: ring a bell and wait for the raid
	await until(func(): return not g.bg_raid.is_empty(), 10.0)
	if str(g.bg_raid.get("state", "")).begins_with("lobby"):
		var bells: Array = g.world.interactables.filter(func(t): return t.kind == "bell")
		if not bells.is_empty():
			g._interact(bells[0])
	check(await until(func(): return str(g.bg_raid.get("state", "")) == "raid", 30.0), "the raid is on")
	check(await until(func(): return g.net.puppets().size() == 1 and g.net.puppets()[0].net_has, 40.0), "the other player is here")
	if role == "a":
		g.test_immortal = true
		var foe = g.net.puppets()[0]
		check(await until(func(): return _proxy() != null, 10.0), "they are a target for my blows (a stand-in)")
		# a skill first: its effects go to the other player through the server (Net.pl_fx, relayed)
		g.hero.mana = g.hero.max_mana
		if warlock:
			# (Drain Life, her first skill, needs them within its reach)
			g.hero.global_position = g.world.free_spot_near(foe.global_position + Vector3(4.0, 0, 0), 0.5)
			await secs(0.6)
		var sk: String = str(g.hero.skill_list()[0]["id"]) if not g.hero.skill_list().is_empty() else ""
		check(sk == "" or g.hero.use_skill(sk, foe.global_position), "cast %s at them" % sk)
		if archer:
			# Thunderstep from beside them: the sigil drops where I stood, on them, as I flip away
			await secs(1.0)
			g.test_allskills = true
			g.hero.mana = g.hero.max_mana
			g.hero.cds.erase("snare")
			g.hero.global_position = g.world.free_spot_near(foe.global_position + Vector3(1.0, 0, 0), 0.5)
			await secs(0.6)      # (the server hears where I am before the sigil goes down: it checks that)
			check(g.hero.use_skill("snare", foe.global_position), "Thunderstep beside them")
			await secs(0.3)
			check(Archer.skill(g.hero, "snare").sigils.is_empty() and Archer.skill(g.hero, "pierce").shots.is_empty(), "my game keeps no sigil or arrow of its own: the server's copy of me deals them")
			check(not g.hero.decides() and not g.hero.beasts.is_empty() and not g.hero.beasts[0]._deals(), "and my wolf here is only seen (the server's bites)")
			RunTalents.throw_flask(g.hero, "flask_fire", foe.global_position)      # (its burst is the server's too)
			await secs(1.7)
		if warlock:
			# Drain Life (above) lets go after its least time (no key held); then a curse and a fright from near them
			await secs(1.4)
			g.test_allskills = true
			g.hero.global_position = g.world.free_spot_near(foe.global_position + Vector3(4.0, 0, 0), 0.5)
			await secs(0.6)      # (the server hears where I am: it checks every spell against it)
			for id in ["w_corruption", "w_terrify"]:
				g.hero.mana = g.hero.max_mana
				g.hero.cds.erase(id)
				check(g.hero.use_skill(id, foe.global_position), "%s on them" % id)
				await secs(1.0)
			# (her classes aren't named here: this script compiles before the Sfx autoload they need)
			var hx = g.hero.kit.get("hex")
			var dr = g.hero.kit.get("drain")
			check(hx != null and hx.dots.is_empty() and hx.feared.is_empty() and dr != null and not dr.latched, "my game keeps no curse, fright or drain of its own: the server's copy of me deals them")
			check(not g.hero.decides(), "and my game doesn't decide my hits (Hero.decides)")
			check(await until(func(): return ServerRules.given_count > 0, 5.0), "the server's Drain Life gave me life back through my own game (%d)" % ServerRules.given_count)
		if dcls != "":
			# every skill of its kit and its run's, each from where it reaches them
			g.test_allskills = true
			for id in DRAGON_SKILLS[dcls]:
				g.hero.mana = g.hero.max_mana
				g.hero.cds.erase(id)
				await until(func(): return g.hero.atk_t < 0.0, 3.0)      # (the cast before it done)
				g.hero.global_position = g.world.free_spot_near(foe.global_position + Vector3(float(DRAGON_FROM.get(id, 3.0)), 0, 0), 0.5)
				await secs(0.6)      # (the server hears where I am: it checks every skill against it)
				check(g.hero.use_skill(id, foe.global_position), "%s at them" % id)
				await secs(float(DRAGON_WAIT.get(id, 1.2)))
			# (its classes aren't named here: this script compiles before the Sfx autoload they need)
			var held: Array = []
			for id in DRAGON_SKILLS[dcls]:
				var dsk = g.hero.kit.get(id)
				if dsk == null:
					continue
				for prop in ["tombs", "clouds"]:
					if dsk.get(prop) is Array and not (dsk.get(prop) as Array).is_empty():
						held.append(id)
				if dsk.get("latched") is bool and dsk.get("latched"):
					held.append(id)
			check(held.is_empty(), "my game keeps none of my skills' state: the server's copy of me deals them %s" % str(held))
			check(not g.hero.decides(), "and my game doesn't decide my hits (Hero.decides)")
		var life_seen: Array = []
		for i in 60:
			if not is_instance_valid(foe) or foe.dead:
				break
			g.hero.global_position = g.world.free_spot_near(foe.global_position + Vector3(1.2, 0, 0), 0.5)
			var p = _proxy()
			if p != null:
				g.hero._hit_enemy(p, 3.0)
			if is_instance_valid(foe):
				life_seen.append(foe.life)
			await secs(0.25)
		check(life_seen.size() > 1 and float(life_seen.back()) < float(life_seen.front()), "their life fell as I hit them (%d -> %d)" % [int(life_seen.front()), int(life_seen.back())])
		check(await until(func(): return not is_instance_valid(foe) or foe.dead, 15.0), "they fell")
		var at: Vector3 = foe.global_position if is_instance_valid(foe) else g.hero.global_position     # (their puppet goes when they leave)
		await secs(4.0)
		# a run character takes what fits: consumables into its belt, gear it can wear (a swap for a worn slot)
		var near: Array = g.world.items_root.get_children().filter(func(gi): return is_instance_valid(gi) and gi is GroundItem and gi.global_position.distance_to(at) < 6.0)
		var n0: int = near.size()
		for gi in near:
			if not is_instance_valid(gi) or gi.is_queued_for_deletion():
				continue
			g.hero.global_position = g.world.free_spot_near(gi.global_position, 0.8)
			g._pickup(gi)
			if g.ui.run_ui.mode == "swap":
				g.ui.run_ui.close()
				g.run_swap(gi.item, gi)
			await secs(0.4)
		await secs(1.5)
		var taken: int = near.filter(func(gi): return not is_instance_valid(gi) or gi.is_queued_for_deletion()).size()
		check(n0 > 0 and taken > 0, "their things fell and I took some (%d of %d)" % [taken, n0])
		await secs(3.0)
	else:
		g.test_immortal = false
		# (against full life: a slow start can find the attacker already at work, even done)
		var l0: float = g.hero.max_life
		if doug:
			check(await until(func(): return g.hero.pied_t > 0.0, 60.0), "Doug's cream pie Pied me (through the server)")
		if archer:
			check(await until(func(): return g.hero.daze_t > 2.0, 60.0), "Thunderstep stunned me through the server (%.1f s)" % g.hero.daze_t)
			check(await until(func(): return SkillFx.aimed_at_me > 0, 10.0), "and its blast was aimed at me on my screen (%d effects)" % SkillFx.aimed_at_me)
		if warlock:
			check(await until(func(): return PvpStatus.landed.any(func(x): return str(x[0]) == "fear"), 60.0), "the Warlock's Terrify frightened me through the server (%s)" % str(PvpStatus.landed))
			check(g.hero.life < l0, "her drain and curse hurt me through the server before any blow (%d of %d)" % [int(g.hero.life), int(l0)])
			check(SkillFx.aimed_at_me > 0, "and her spells were aimed at me on my screen (%d effects)" % SkillFx.aimed_at_me)
		if dcls != "" and not (DRAGON_SKILLS[dcls] as Array).is_empty():
			check(await until(func(): return PvpStatus.landed.any(func(x): return str(x[0]) == "stagger"), 60.0), "the %s's skills staggered me through the server (%s)" % [dcls, str(PvpStatus.landed)])
			check(await until(func(): return PvpStatus.landed.any(func(x): return str(x[0]) == "slow"), 20.0), "and slowed me (%s)" % str(PvpStatus.landed))
			check(await until(func(): return g.hero.life < l0, 20.0), "its skills hurt me through the server (%d of %d)" % [int(g.hero.life), int(l0)])
			check(await until(func(): return SkillFx.aimed_at_me > 0, 10.0), "and were aimed at me on my screen (%d effects)" % SkillFx.aimed_at_me)
		check(await until(func(): return g.hero.life < l0 or g.hero.dead, 60.0), "I'm being hit by the other player")
		check(await until(func(): return g.hero.dead, 60.0), "and I fell")
		# fallen, I watch the one still alive (Game.spectate_*), until they leave too
		check(await until(func(): return g.ui.spectate_panel.visible, 6.0) and not g.ui.death_panel.visible, "I'm spectating (not the plain death screen)")
		check(g.ui.spectate_name() == "Attacker", "watching the Attacker (%s)" % g.ui.spectate_name())
		await secs(1.5)
		var att = g.spectate_hero()
		check(att != null and g.cam_target.distance_to(att.global_position) < 3.0, "the camera follows them")
		check(await until(func(): return g.net.puppets().is_empty(), 40.0), "they left")
		await secs(0.5)
		check(g.spectating == 0 and str(g.ui._spec_name.text).begins_with("No one"), "no one left to watch: it says so")
		(g.ui.spectate_panel.find_child("leave", true, false) as Button).pressed.emit()
		check(await until(func(): return not g.bg_mode and not g._busy, 20.0), "the raid is over for me")
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		var h: Dictionary = d.get("hero", {}) if d is Dictionary else {}
		var inv: Array = (h.get("inventory", []) as Array).filter(func(x): return x != null)
		check(int(h.get("level", 0)) == 8 and inv.size() == inv_saved, "my saved character is untouched by the fall (level 8, %d items)" % inv.size())
		check(g.net.fx_got > 0, "I saw the other player's skill effects (%d events, through the server)" % g.net.fx_got)
	g.net.shutdown()
	await secs(1.0)

func _saved_items(p: String) -> int:
	var d = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	var h: Dictionary = d.get("hero", {}) if d is Dictionary else {}
	return (h.get("inventory", []) as Array).filter(func(x): return x != null).size()

func _proxy():
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.pvp_pid > 0:
			return e
	return null
