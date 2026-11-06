extends SceneTree
## The Hero Codex (scripts/codex.gd, data/codex/) reaches the game: live skills and rites match the codex files,
## design entries stay out of the run's pools, and a live data-only rite joins its class's pool.
##   godot --headless --path . -s tools/_late.gd -- res://tools/codex_test.gd   (RunTalents needs the autoloads)

var fails := 0

func _ok(c: bool, what: String) -> void:
	print(("[OK] " if c else "[FAIL] ") + what)
	if not c:
		fails += 1

func _initialize() -> void:
	var n := 0
	for cls in Data.CLASSES:
		var h := Codex.hero(cls)
		for e in h.get("skills", []):
			if not Codex.live(e):
				_ok(Data.skill_def(e["id"]).is_empty(), "%s design skill %s is not in the game" % [cls, e["id"]])
				continue
			var s := Data.skill_def(e["id"])
			_ok(not s.is_empty(), "%s live skill %s exists" % [cls, e["id"]])
			if s.get("name") != e.get("name") or float(s.get("mana", 0)) != float(e.get("mana", 0)):
				_ok(false, "%s skill %s matches the codex" % [cls, e["id"]])
			if e.has("rarity"):
				_ok(RunBuild.skill_rarity(s) == int(e["rarity"]), "%s skill %s rarity is the codex's" % [cls, e["id"]])
			n += 1
		var pool := RunBuild.passive_pool(cls)
		var ids := {}
		for p in pool:
			ids[p["id"]] = p
		for e in h.get("rites", []):
			if Codex.live(e):
				_ok(ids.has(e["id"]), "%s live rite %s is offered" % [cls, e["id"]])
				if ids.has(e["id"]):
					_ok(str(ids[e["id"]]["name"]) == str(e["name"]) and int(ids[e["id"]]["rarity"]) == int(e.get("rarity", 0)), "%s rite %s name/rarity" % [cls, e["id"]])
			else:
				_ok(not ids.has(e["id"]), "%s design rite %s is not offered" % [cls, e["id"]])
	_ok(n > 30, "%d live skills checked" % n)
	var pact := RunBuild.passive_def("warlock", "w_r_pact")
	_ok(not pact.is_empty() and pact["fx"].has("dmg:drain"), "the data-only rite Thirsting Pact is in the Warlock's pool")
	var r := RunBuild.new()
	r.passives["w_r_pact"] = 2
	_ok(is_equal_approx(float(r.fx("warlock").get("ls", 0)), 2.0), "Thirsting Pact's fx add up (2 stacks: 2% life steal)")
	_ok(Codex.data_only({"fx": {"dmg": 5}}) and not Codex.data_only({"fx": {"dot_flat": 1}}) and Codex.data_only({"fx": {"dot_flat": 1}}, "warlock"), "data-only check (shared and class keys)")
	_ok(Codex.fx_keys("warlock").has("dot_flat") and (load("res://scripts/warlock_hex.gd").RITE_KEYS as Array).all(func(k): return Codex.fx_keys("warlock").has(k)), "fx_keys.json lists every WarlockHex rite key")
	print("[codex_test] %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
