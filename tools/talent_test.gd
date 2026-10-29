extends SceneTree
## Talent trees: every class's trees are well formed, points come one per level from level 2, rows
## open with points spent above them, ranks can't be taken back out from under a deeper talent, the
## talents change the numbers they say, old saves get a build, saves keep talents, skills drag onto the
## bar, and every skill still casts with every talent taken. Prints [T] lines.
var g
var fails := 0

const ICONS := ["t_sword", "t_haste", "t_star", "t_hourglass", "t_heart", "t_armor", "t_ward", "t_regen", "t_boot",
	"t_fist", "t_eye", "t_skull", "t_drop", "t_fang", "t_orb"]
const KEYS := ["str", "dex", "vit", "ene", "res", "ls", "regen", "ias", "frw", "block", "mf", "dmg", "life_pct", "mana_pct",
	"armor_pct", "crit", "crit_dmg", "buff_pow", "block_dr", "buff_dur", "phase_dur", "wail_stun", "shackle_dur", "blight_dur",
	"nova_heal", "cry_heal", "charge_cdr", "reap_heal", "reap_full", "wail_echo", "spirits", "claw_wide", "minion_speed",
	"minion_max", "pact_cost", "phase_heal", "drain_heal", "drain_fork", "drain_glut", "blight_size", "blight_twin", "shackle_range"]

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[T] %s %s" % ["ok  " if ok else "FAIL", what])

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	_check_data()
	await g.start_game(false, "knight")
	g.difficulty = 0
	await g.load_zone(0, "wild", "start")
	await wait(0.3)
	var h = g.hero
	# points and rows
	check(h.free_talent_points() == 0, "a new character has no talent points")
	h.set_level(11)
	check(h.free_talent_points() == 10, "level 11 has 10 points (got %d)" % h.free_talent_points())
	check(not h.learn_talent("k_radiance"), "row 2 is shut with nothing spent")
	for i in 3:
		h.learn_talent("k_zeal")
	check(h.talents.get("k_zeal", 0) == 3 and not h.learn_talent("k_zeal"), "Zeal stops at 3 ranks")
	check(h.learn_talent("k_radiance"), "row 2 opens after 3 points")
	check(not h.unlearn_talent("k_zeal"), "Zeal can't drop below what row 2 needs")
	check(h.unlearn_talent("k_radiance") and h.unlearn_talent("k_zeal"), "taking back the deeper rank first works")
	h.reset_talents()
	check(h.free_talent_points() == 10, "reset gives every point back")
	# numbers
	var life0: float = h.max_life
	var cost0: float = h.skill_cost("nova")
	var cd0: float = h.skill_cd("nova")
	for id in ["k_vigor", "k_vigor", "k_vigor"]:
		h.learn_talent(id)
	check(is_equal_approx(h.max_life, life0 * 1.12), "Vigor 3/3: life %.1f -> %.1f (+12%%)" % [life0, h.max_life])
	h.reset_talents()
	h.talents = {"k_zeal": 3, "k_heavy": 3, "k_steel": 1, "k_purify": 2}
	h._talents_changed()
	check(is_equal_approx(h.dmg_mult("cleave"), 1.42) and is_equal_approx(h.dmg_mult("nova"), 1.12), "damage: Holy Slam x%.2f, Holy Nova x%.2f" % [h.dmg_mult("cleave"), h.dmg_mult("nova")])
	check(is_equal_approx(h.skill_cost("nova"), cost0 * 0.7) and is_equal_approx(h.skill_cd("nova"), cd0 * 0.8), "Purifying Fire: Nova %.1f mana %.2fs" % [h.skill_cost("nova"), h.skill_cd("nova")])
	# saves: an old one gets a build, a new one keeps its own, a bad one is cleaned
	var sv: Dictionary = h.to_save()
	check(sv.has("talents") and sv["talents"].get("k_zeal") == 3, "the save holds the talents")
	sv.erase("talents")
	h.from_save(sv)
	check(Talents.spent(h.talents) == 10 and h.free_talent_points() == 0, "an old level 11 save gets 10 points spent: %s" % [h.talents])
	for i in 3:
		check(Talents.valid_tree("knight", i, h.talents), "  its tree %d is valid" % i)
	sv["talents"] = {"k_wall": 2, "w_scythe": 3, "k_zeal": 9}
	h.from_save(sv)
	check(h.talents.is_empty(), "a save with talents out of their rows loses them: %s" % [h.talents])
	sv["talents"] = {"k_tough": 2, "w_scythe": 3, "k_zeal": 9}
	h.from_save(sv)
	check(h.talents == {"k_tough": 2, "k_zeal": 3}, "foreign talents dropped, ranks capped: %s" % [h.talents])
	sv["level"] = 2
	sv["talents"] = {"k_tough": 3}
	h.from_save(sv)
	check(h.talents.is_empty(), "more points spent than the level gives: reset")
	# the window and the badge
	h.from_save(h.to_save())
	h.set_level(11)
	h.reset_talents()
	g.ui.refresh()
	check(g.ui.talent_badge.visible and g.ui.talent_badge.text.begins_with("10 "), "badge: " + g.ui.talent_badge.text)
	g.ui.toggle(g.ui.talent_panel)
	await process_frame
	var nodes: Array = g.ui.talent_cols.find_children("k_*", "Control", true, false)
	check(nodes.size() == 21 and not g.ui.talent_badge.visible, "the window shows 21 knight talents")
	h.learn_talent("k_zeal")
	g.ui.refresh()
	await process_frame
	check(g.ui.talent_head.text.begins_with("9 "), "the window follows a learned point: " + g.ui.talent_head.text)
	h.auto_talents()
	g.ui.refresh()
	check(h.free_talent_points() == 0 and not g.ui.talent_badge.visible, "Auto-assign spends the rest")
	g.ui.toggle(g.ui.talent_panel)
	# drag and drop onto the bar
	h.binds = h.default_binds()
	g.ui.drop_skill({"skill": "nova", "from": ""}, "G")
	check(h.bound("G") == "nova" and h.bound("E") == "", "drag Holy Nova from the window to G (it leaves E)")
	g.ui.drop_skill({"skill": "cleave", "from": "Q"}, "rmb")
	check(h.bound("rmb") == "cleave" and h.bound("Q") == "block", "drag Q onto right mouse: they swap")
	g.ui.drop_skill({"skill": "attack", "from": "lmb"}, "E")
	check(h.bound("E") == "attack" and h.bound("lmb") == "attack", "left mouse never ends up empty")
	# every class, every talent: cast every skill into a pack
	g.test_allskills = true
	g.test_immortal = true
	for cls in ["knight", "wraith", "demon", "warlock"]:
		h.set_class(cls)
		h.new_character()
		h.set_level(60)
		h.auto_talents()
		var all := 0
		for tr in Talents.trees(cls):
			for t in tr["talents"]:
				all += int(t["max"])
		check(Talents.spent(h.talents) == all, "%s: every talent taken at level 60 (%d ranks)" % [cls, all])
		var foes: Array = g.enemies_near(h.global_position, 200.0)
		if foes.size() > 0:
			var e = foes[0]
			h.global_position = e.global_position + Vector3(2.0, 0, 0)
		for sk in Data.skills_for(cls):
			for k in h.cds:
				h.cds[k] = 0.0
			h.mana = h.max_mana
			var aim: Vector3 = h.global_position + Vector3(-2.0, 0, 0)
			var foe = g.enemies_near(h.global_position, 12.0)
			if foe.size() > 0:
				aim = foe[0].global_position
			var ok: bool = h.use_skill(sk["id"], aim)
			await wait(1.2 if sk["id"] != "drain" else 0.4)
			if sk["id"] == "drain":
				h.end_drain()
			check(ok, "%s: %s cast" % [cls, sk["name"]])
		if cls == "wraith":
			check(h.spirits.size() == 4, "Fourth Rider: %d spirits" % h.spirits.size())
		if cls == "demon":
			for i in 4:
				h.cds["summon"] = 0.0
				h.mana = h.max_mana
				h.use_skill("summon", h.global_position)
				await wait(0.7)
			check(h.minions.size() == 4, "Legion of Hell: %d demons" % h.minions.size())
		await wait(1.0)
	print("[T] done, %d failed" % fails)
	quit()

func _check_data() -> void:
	for cls in Data.CLASSES:
		var trees: Array = Talents.trees(cls)
		check(trees.size() == 3, "%s has 3 trees" % cls)
		var ids := {}
		var skills := {}
		for s in Data.skills_known(cls):
			skills[s["id"]] = true
		for tr in trees:
			var rows := [0, 0, 0, 0]
			for t in tr["talents"]:
				ids[t["id"]] = true
				rows[int(t["row"])] += 1
				var icon_ok: bool = ICONS.has(t["icon"]) or skills.has(t["icon"])
				var keys_ok := true
				for k in t["fx"]:
					var base: String = k.split(":")[0]
					if not (KEYS.has(k) or (["dmg", "cd", "cost"].has(base) and k.contains(":") and (skills.has(k.split(":")[1]) or k == "dmg:summon"))):
						keys_ok = false
						print("[T]   unknown key ", k)
				var text_ok := not Talents.describe(t, int(t["max"])).contains("{")
				if not (icon_ok and keys_ok and text_ok):
					check(false, "%s %s: icon %s keys %s text %s" % [cls, t["id"], icon_ok, keys_ok, text_ok])
			check(rows == [2, 2, 2, 1], "%s %s rows %s" % [cls, tr["name"], rows])
		var auto: Array = Talents.AUTO[cls]
		check(auto.size() == ids.size() and auto.all(func(i): return ids.has(i)), "%s auto build names all %d talents" % [cls, ids.size()])
