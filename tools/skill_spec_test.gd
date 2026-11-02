extends SceneTree
## The skill format (SkillSpec, CLAUDE.md "Skill design"): every Data.SKILLS entry's fields are checked (known keys,
## types and ranges), and a skill in the format plays by its data (Molten Fists: its use time, its impact frame, its
## area, damage and burn, and a "cancel": false skill can't be dodged out of).
##   godot --headless --path . -s tools/skill_spec_test.gd
var fails := 0
const KEYS := ["id", "cls", "name", "key", "lvl", "mana", "cd", "aim", "range", "desc", "channel", "hold", "style", "use", "hit",
	"speed", "lock", "cancel", "dmg", "base", "per_lvl", "type", "knock", "area", "dot", "tags", "power", "role", "pvp"]

## Styles more than one user plays (the weapon swings, monsters' attacks, the shared skills): a skill's "hit" must
## not retime them.
## Tags that allow a cooldown (CLAUDE.md "Skill design": cooldowns are for utility).
const UTILITY := ["movement", "warcry", "buff", "cc", "trap", "summon", "command", "ultimate", "sustain"]
const SHARED_STYLES := ["over", "back", "side", "thrust", "cast", "slam", "smash", "claw", "bite", "lob", "cleave",
	"swipe1", "swipe2", "swipe3", "burst", "cackle", "scoop", "bow", "chop"]

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[K] " + ("ok   " if ok else "FAIL ") + what)

## (the game's classes are looked up at run time, after the autoloads, as the other tool scripts do)
var SS
var DG
var AN
var SH

func _initialize():
	_run()

func _num(v) -> bool:
	return v is float or v is int

func _validate(s: Dictionary) -> String:
	var id := str(s.get("id", "?"))
	for k in s.keys():
		if not KEYS.has(k):
			return "%s: unknown field \"%s\"" % [id, k]
	for k in ["use", "lock", "dmg", "per_lvl", "knock", "cd", "mana"]:
		if s.has(k) and not (_num(s[k]) and float(s[k]) >= 0.0):
			return "%s: \"%s\" must be a number >= 0" % [id, k]
	if s.has("hit") and not (_num(s["hit"]) and float(s["hit"]) > 0.0 and float(s["hit"]) < 1.0):
		return "%s: \"hit\" must be between 0 and 1" % id
	if s.has("hit") and not s.has("style"):
		return "%s: \"hit\" needs a \"style\" (the animation it lands in)" % id
	if s.has("hit") and SHARED_STYLES.has(s["style"]):
		return "%s: \"hit\" on the shared style \"%s\" would move every user's impact (monsters too): give the skill its own style, or leave \"hit\" out" % [id, s["style"]]
	if str(s.get("cls", "")) == "any" and not (SH.IDS as Array).has(id) and not ["attack", "block"].has(id):
		return "%s: a shared skill (\"cls\": \"any\") must be handled in SharedSkills (add it to IDS)" % id
	if s.has("use") and float(s["use"]) < 0.2:
		return "%s: \"use\" under 0.2 s" % id
	if s.has("speed") and not ["attack", "cast"].has(s["speed"]):
		return "%s: \"speed\" is attack or cast" % id
	if s.has("type") and not ["phys", "fire", "cold", "lightning", "poison"].has(s["type"]):
		return "%s: unknown \"type\" %s" % [id, s["type"]]
	if s.has("base") and not (s["base"] is Array and (s["base"] as Array).size() == 2):
		return "%s: \"base\" is [min, max]" % id
	if s.has("area"):
		var ar = s["area"]
		if not (ar is Dictionary and ["wedge", "circle", "line", "single"].has(ar.get("shape", "")) and _num(ar.get("r", 0))):
			return "%s: \"area\" needs a shape (wedge, circle, line, single) and an \"r\"" % id
	if s.has("dot"):
		var dt = s["dot"]
		if not (dt is Dictionary and ["burn", "chill", "slow"].has(dt.get("kind", "")) and _num(dt.get("secs", 0)) and float(dt.get("secs", 0)) > 0.0):
			return "%s: \"dot\" needs a kind (burn, chill, slow) and \"secs\"" % id
	if s.has("tags") and not s["tags"] is Array:
		return "%s: \"tags\" is a list" % id
	if s.has("pvp") and not (s["pvp"] is Dictionary and (s["pvp"] as Dictionary).values().all(func(v): return _num(v) and float(v) >= 0.0)):
		return "%s: \"pvp\" is a dictionary of numbers >= 0" % id
	# the Path of Exile way: a main skill has no cooldown (its use time is its limit); a cooldown is for utility
	if float(s.get("cd", 0.0)) > 0.0 and not (s.get("tags", []) as Array).any(func(t): return UTILITY.has(t)):
		return "%s: a cooldown on a main skill; take it off (its \"use\" time is the limit) or tag it as utility (%s)" % [id, ", ".join(UTILITY)]
	return ""

func _run() -> void:
	var g = (load("res://main.tscn") as PackedScene).instantiate()
	SS = load("res://scripts/skill_spec.gd")
	DG = load("res://scripts/dodge.gd")
	AN = load("res://scripts/anim.gd")
	SH = load("res://scripts/shared_skills.gd")
	get_root().add_child(g)
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	var bad := []
	for s in Data.SKILLS + Data.COMMON_SKILLS:
		var why := _validate(s)
		if why != "":
			bad.append(why)
	check(bad.is_empty(), "every skill's fields are valid (%d skills)%s" % [Data.SKILLS.size(), ("\n      " + "\n      ".join(bad)) if not bad.is_empty() else ""])
	await g.start_game(false)
	var h = g.hero
	# every class (and any added later): all its skills open at level 1, and every hotkey on the bar holds one
	var shut := []
	for c in Data.CLASSES.keys():
		h.set_class(c)
		h.new_character()
		h.set_level(1)
		h.binds = h.default_binds()
		var own: Array = h.skill_list()
		for s in own:
			if Data.skill_locked(s, 1):
				shut.append("%s %s" % [c, s["id"]])
		var filled := 0
		for k in h.BIND_KEYS:
			if str(h.binds.get(k, "")) != "":
				filled += 1
		var want := mini(6, own.size() + Data.shared_skills().size())
		if filled < want:
			shut.append("%s: %d of %d on the bar" % [c, filled, want])
		# an old save's bar with gaps fills them with the skills not on it
		h.from_save(h.to_save().merged({"binds": {"lmb": "attack", "Q": str((own + Data.shared_skills())[0]["id"])}}, true))
		var refill := 0
		for k in h.BIND_KEYS:
			if str(h.binds.get(k, "")) != "":
				refill += 1
		if refill < want:
			shut.append("%s: an old save's bar kept %d empty" % [c, want - refill])
	check(shut.is_empty(), "every class has every skill at level 1 and a full bar (%d classes)%s" % [Data.CLASSES.size(), ("\n      " + "\n      ".join(shut)) if not shut.is_empty() else ""])
	h.set_class("demon")
	h.set_level(10)
	g.test_immortal = true
	await create_timer(0.5).timeout
	check(is_equal_approx(AN.impact_at("fists"), float(Data.skill_def("fists")["hit"])), "Molten Fists lands at its data's hit (%.2f)" % AN.impact_at("fists"))
	h.mana = h.max_mana
	var home: Vector3 = h.global_position
	var foe = g.spawn_enemy("zombie", home + Vector3(0, 0, -2.0), 10)
	await create_timer(0.3).timeout
	h._face(Vector3(0, 0, -1))
	var l0: float = foe.life
	check(h.use_skill("fists", h.skill_aim("fists", foe.global_position)), "Molten Fists cast")
	check(is_equal_approx(h.atk_dur, SS.use_time(h, "fists")), "its use time is its data's (%.2f s)" % h.atk_dur)
	check(SS.targets(h, "fists").has(foe), "the foe ahead is in its wedge")
	await create_timer(h.atk_dur + 0.2).timeout
	check(not is_instance_valid(foe) or foe.life < l0, "it struck")
	check(not is_instance_valid(foe) or foe.dead or foe.burn_t > 0.0, "and set it burning (its dot)")
	# a skill whose data says "cancel": false can't be dodged out of while it winds up
	SS.over["fists"] = {"cancel": false}
	h.mana = h.max_mana
	h.use_skill("fists", home + Vector3(0, 0, -3))
	await create_timer(0.3).timeout
	check(not DG.can_roll(h), "\"cancel\": false holds against the dodge roll")
	SS.over.clear()
	check(DG.can_roll(h), "and by default the dodge can break it")
	# the shared skills on two kinds of body (the knight's, the legless Wraith's): each casts, and does what it says
	for c in ["knight", "wraith"]:
		h.set_class(c)
		h.new_character()
		h.set_level(10)
		await create_timer(0.3).timeout
		for id in SH.IDS:
			h.global_position = home
			h._face(Vector3(0, 0, -1))
			var foes := []
			for i in 3:
				foes.append(g.spawn_enemy("zombie", home + Vector3(i - 1.0, 0, -2.5 - i * 0.6), 10))
			await create_timer(0.3).timeout
			var lives := func(): return foes.reduce(func(t, f): return t + (f.life if is_instance_valid(f) and not f.dead else 0.0), 0.0)
			var l0b: float = lives.call()
			h.mana = h.max_mana
			h.buff_t = 0.0
			for k in h.cds.keys():
				h.cds[k] = 0.0
			var cast_ok: bool = h.use_skill(id, h.skill_aim(id, foes[1].global_position))
			await create_timer(h.atk_dur + 0.3).timeout
			var did: bool = h.buff_t > 0.0 if id == "war_cry" else float(lives.call()) < l0b
			check(cast_ok and did, "%s: %s works (%s)" % [c, id, "buffed" if id == "war_cry" else "%d damage" % int(l0b - float(lives.call()))])
			for f in foes:
				if is_instance_valid(f):
					f.queue_free()
	print("[K] done, %d failed" % fails)
	quit()
