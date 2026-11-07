extends SceneTree
## A whole Battlegrounds run played for real (Blaine's overhaul, step 7): a fresh run character of `cls` at level 0
## on the Verdant Reach, played by the sandbox's BotBrain (the same calls as the mouse and keys: its skills, weapon,
## dodge and potions; nothing immortal, nothing one-hit) through every camp in tier order, nearest first. After each
## camp it opens the chest, takes an upgrade (a skill while a slot is empty, else the rarest passive), wears better
## gear (the swap), and goes on. Then it "extracts" (the results and Save Character), reloads the survivor as the
## Arena would and checks it matches. Prints a line per camp ([RUN-PLAY]) and a summary; a death is reported (and
## the run carries on at full life so the rest of the curve is measured, marked as a fall).
##   godot --headless --path . -s tools/run_playthrough.gd -- archer|plague [max_secs_per_camp]
var g
var cls := "archer"
var per_camp := 120.0
var fails := 0
var CA
var RB
var SV
var theme := ""
var dmg_total := 0.0

func _initialize():
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		cls = a[0]
	if a.size() > 1:
		per_camp = float(a[1])
	if a.size() > 2:
		theme = a[2]       # a build theme to chase (RunTalents.THEMES), or "random" for a player who picks blindly
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	CA = load("res://game/maps/verdant_reach/camps.gd")
	RB = load("res://game/items/run_build.gd")
	SV = load("res://scripts/survivors.gd")
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[RUN-PLAY] %s %s" % ["ok  " if ok else "FAIL", what])

func secs(t: float) -> void:
	await create_timer(t).timeout

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	SV.dir = "user://run_playthrough_survivors_%s/" % cls
	DirAccess.make_dir_recursive_absolute(SV.dir)
	for fn in DirAccess.get_files_at(SV.dir):
		DirAccess.remove_absolute(SV.dir + fn)
	await g.start_game(false, "knight")
	g.ui.hide_title()
	var h = g.hero
	h.set_class(cls)
	h.start_run()
	g.char_name = load("res://game/systems/data/data.gd").CLASSES[cls]["name"]
	g.bg_mode = true
	await g.load_zone(0, "bg", "start")
	await secs(1.0)
	check(h.level == 0 and h.run.skills.is_empty(), "%s starts at level 0 with no skills" % cls)
	var camps: Array = CA.all(g.world).duplicate()
	var start: Vector3 = h.global_position
	camps.sort_custom(func(x, y): return int(x["tier"]) * 1000 + Vector2(x["pos"].x - start.x, x["pos"].z - start.z).length() < int(y["tier"]) * 1000 + Vector2(y["pos"].x - start.x, y["pos"].z - start.z).length())
	var brain = load("res://game/maps/arena/bot_brain.gd").new()
	var falls := 0
	var t_total := 0.0
	for c in camps:
		var lvl0: int = h.level
		var frames := 0
		var hp0 := 0.0
		for e in g.world.enemies_root.get_children():
			if e is Enemy and not e.dead and e.pack_id == int(c["pack"]):
				hp0 += e.max_life
		h.global_position = g.world.free_spot_near(c["pos"] + Vector3(0, 0, float(c["r"]) + 4.0), 2.0)
		h.life = h.max_life
		h.mana = h.max_mana
		var fell := false
		var left_t := per_camp
		while not c["cleared"] and left_t > 0.0:
			var pick := func(_hh): return _nearest_of(c)
			brain.think(h, pick, 1.0 / 60.0)
			await process_frame
			frames += 1
			left_t -= 1.0 / 60.0      # (--fixed-fps 60: one frame is 1/60 s of game time)
			if h.dead:
				print("[RUN-PLAY]   fell in %s at %.0fs (life %d, %s)" % [c["name"], frames / 60.0, int(h.max_life), str(h.belt.map(func(x): return 0 if x == null else int(x.get("count", 1))))])
				fell = true
				falls += 1
				h.respawn(h.global_position)
				h.life = h.max_life
		h.bot_hold = false
		var took := frames * 1000.0 / 60.0      # game milliseconds (--fixed-fps 60)
		t_total += took / 1000.0
		dmg_total += hp0
		if not c["cleared"]:
			var hp_left := 0.0
			for e in g.world.enemies_root.get_children():
				if e is Enemy and not e.dead and e.pack_id == int(c["pack"]):
					hp_left += e.life
					var cp: Vector3 = c["pos"] if c.has("pos") else Vector3.ZERO
					print("[RUN-PLAY]   left: %s at %s (%.1f m from the camp, %.1f from the hero) life %d/%d stun %.1f scripted %.1f aggro %s" % [e.kind, str(e.global_position.snapped(Vector3(0.1, 0.1, 0.1))),
						Vector2(e.global_position.x - cp.x, e.global_position.z - cp.z).length(), e.global_position.distance_to(h.global_position), int(e.life), int(e.max_life), e.stun_t, e.scripted, str(e.aggro)])
			check(false, "%s (%s): not cleared in %ds (%d left, %d of %d life, %d falls)" % [c["name"], CA.TIER_NAMES[int(c["tier"])], int(per_camp), CA.alive(g.world, c), int(hp_left), int(hp0), falls])
			continue
		# the chest: loot for everyone, the upgrade for us
		var ch = c["chest_node"]
		h.global_position = g.world.free_spot_near(ch.global_position, 1.4)
		var before: int = g.world.items_root.get_child_count()
		g._interact(ch)
		await secs(0.3)
		var pick_txt := ""
		if g.ui.run_ui.mode == "offer":
			var o: Dictionary = h.run.offers[g.ui.run_ui.offer_key]
			var best := 0
			var empty: bool = RB.SLOTS.any(func(s): return h.bound(s) == "")
			var want_skill: bool = empty or h.run.skills.size() < 8
			var score := func(ci: Dictionary) -> int:
				# skills first while a slot is empty or the spellbook is thin (so it gets exercised), then the theme the
				# bot chases, then rarity
				var v: int = int(ci["rarity"]) * 10 + (50 if want_skill and ci["kind"] == "skill" else 0)
				if theme != "" and theme != "random" and str(ci.get("theme", "")) == theme:
					v += 45
				return v
			for i in o["choices"].size():
				if score.call(o["choices"][i]) > score.call(o["choices"][best]):
					best = i
			if theme == "random":
				best = randi() % o["choices"].size()
			var chosen: Dictionary = o["choices"][best]
			pick_txt = "%s %s%s" % [chosen["kind"], chosen["id"], (" [%s]" % chosen["theme"]) if str(chosen.get("theme", "")) != "" else ""]
			g.ui.run_ui._take(best)
			if o.get("gem", "") != "":
				pick_txt += "  gem " + str(o["gem"])
			# a themed skill learned into the spellbook takes the place of an off-theme one (between fights, as a player would)
			if theme != "" and theme != "random" and chosen["kind"] == "skill" and str(chosen.get("theme", "")) == theme and not RB.SLOTS.any(func(sl): return h.bound(sl) == chosen["id"]):
				for sl in RB.SLOTS:
					var cur: String = h.bound(sl)
					if str(load("res://game/items/run_talents.gd").SKILL_THEMES.get(cur, "")) != theme:
						h.bind(sl, chosen["id"])
						break
		await secs(0.2)
		var gear_txt := await _loot(before)
		print("[RUN-PLAY] %-22s %-8s lvl %2d -> %2d  %5.1fs  %6d hp (%4d/s)  life %3d/%3d %s  took %s%s" % [c["name"], CA.TIER_NAMES[int(c["tier"])], lvl0, h.level, took / 1000.0,
			int(hp0), int(hp0 / maxf(took / 1000.0, 0.1)), int(h.life), int(h.max_life), "FELL" if fell else "", pick_txt, gear_txt])
	var cleared: int = camps.filter(func(c): return c["cleared"]).size()
	var skills: int = h.run.skills.size()
	var slotted: int = RB.SLOTS.filter(func(s): return h.bound(s) != "").size()
	print("[RUN-PLAY] summary: %s level %d, %d/%d camps, %d bosses, %d skills (%d slotted), %d passives, %d falls, %.0fs fighting" % [
		cls, h.level, cleared, camps.size(), h.run.bosses, skills, slotted, h.run.passives.size(), falls, t_total])
	print("[RUN-PLAY] build%s: themes %s; slots %s; talents %s; gems %s; total damage %d, %.0f/s" % [
		(" (chasing %s)" % theme) if theme != "" else "", str(h.run.theme_counts(cls)), str(RB.SLOTS.map(func(sl): return h.bound(sl))),
		str(h.run.passives.keys()), str(h.run.gems), int(dmg_total), dmg_total / maxf(t_total, 1.0)])
	check(cleared == camps.size(), "every camp cleared (%d/%d)" % [cleared, camps.size()])
	check(h.run.bosses == 2, "both bosses down")
	check(h.level >= 15, "fast progression: level %d after the whole map" % h.level)
	var can_learn: int = RB.skill_pool(cls).size()
	check(slotted == mini(5, can_learn) and (skills >= mini(6, can_learn) or theme == "random"), "five slotted, the rest in the spellbook (%d of %d learned)" % [skills, can_learn])
	check(falls == 0, "no falls (%d)" % falls)
	var wk := str(load("res://game/systems/data/data.gd").BASES[h.equipment["weapon"]["base"]].get("cls", ""))
	check(wk == cls or not RB.has_own_weapons(cls), "still fighting with its own weapon kind (%s)" % h.equipment["weapon"]["name"])
	# survive and save
	var want := {"level": h.level, "skills": h.run.skills.duplicate(), "passives": h.run.passives.duplicate()}
	await g.bg_extracted([])
	await secs(0.3)
	var save_b = g.ui.run_ui.find_child("save", true, false)
	check(save_b != null, "the results offer Save Character")
	if save_b:
		save_b.pressed.emit()
	var list: Array = SV.list()
	check(list.size() == 1, "one survivor saved")
	if not list.is_empty():
		h.new_character()
		SV.load_into(g, str(list[0]["id"]))
		check(h.level == want["level"] and h.run.skills == want["skills"] and h.run.passives == want["passives"], "the survivor reloads as it was (level %d)" % h.level)
	print("[RUN-PLAY] done, %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

func _nearest_of(c: Dictionary):
	var best = null
	var bd := INF
	# (as a player would: a boss camp's boss first; Mossbeard grows his mushrooms back while he lives)
	for e in g.world.enemies_root.get_children():
		if e is Enemy and not e.dead and e.pack_id == int(c["pack"]) and e.boss:
			return e
	for e in g.world.enemies_root.get_children():
		if e is Enemy and not e.dead and e.pack_id == int(c["pack"]):
			var d: float = e.global_position.distance_to(g.hero.global_position)
			if d < bd:
				bd = d
				best = e
	return best

## Take what's on the ground by the chest: potions into the belt, gear swapped in when it's better.
func _loot(before: int) -> String:
	var out := ""
	var items: Array = g.world.items_root.get_children().slice(before)
	for gi in items:
		if not is_instance_valid(gi) or not gi is GroundItem or gi.is_queued_for_deletion():
			continue
		var it: Dictionary = gi.item
		g.hero.global_position = g.world.free_spot_near(gi.global_position, 0.6)
		g._pickup(gi)
		if g.ui.run_ui.mode == "swap":
			var slot: String = RB.gear_slot(it)
			var old = g.hero.equipment.get(slot)
			g.ui.run_ui.close()
			if _better(it, old):
				g.run_swap(it, gi)
				out += "  +" + str(it["name"])
		await process_frame
	return out

func _better(a: Dictionary, b) -> bool:
	if b == null:
		return true
	var I = load("res://game/items/items.gd")
	if a.has("dmg") and b.has("dmg"):
		var da: Array = I.damage_of(a)
		var db: Array = I.damage_of(b)
		return da[0] + da[1] > db[0] + db[1]
	return I.defense_of(a) + int(a.get("rarity", 0)) * 3 > I.defense_of(b) + int(b.get("rarity", 0)) * 3
