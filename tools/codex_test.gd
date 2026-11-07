extends SceneTree
## The Hero Codex (game/systems/data/codex.gd, data/codex/) reaches the game: live skills and rites match the codex files,
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
	_merge_checks()
	for f in ["shared.json", "gems.json", "consumables.json"] + Array(Data.CLASSES.keys()).map(func(c): return "heroes/%s.json" % c):
		var doc := Codex.file(f)
		for key in ["skills", "rites", "entries"]:
			var seen := {}
			var dup := []
			for e in doc.get(key, []):
				var i := str(e.get("id", "")) if e is Dictionary else ""
				if seen.has(i):
					dup.append(i)
				seen[i] = true
			if not doc.get(key, []).is_empty():
				_ok(dup.is_empty(), "%s %s: every id once%s" % [f, key, (" (twice: %s)" % ", ".join(dup)) if not dup.is_empty() else ""])
	print("[codex_test] the codex overrides %d code values%s" % [Codex.overrides.size(), (": " + ", ".join(Codex.overrides.slice(0, 60))) if OS.get_environment("CODEX_LIST") != "" else ""])
	if not Codex.code_newer.is_empty():
		print("[codex_test] NOTE: changed in code since the last export, the code's value kept (run tools/codex_export.gd): " + ", ".join(Codex.code_newer))
	if not Codex.conflicts.is_empty():
		print("[codex_test] NOTE: changed in code and in the codex, the codex's value taken: " + ", ".join(Codex.conflicts))
	print("[codex_test] %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)

## The three-way merge (Codex._take) on a made-up base: the code's edits survive, the codex's win, both = codex.
func _merge_checks() -> void:
	var saved = Codex._files.get("code_base.json")
	Codex._files["code_base.json"] = {"t": {"x": {"a": 1, "b": 1, "c": 1, "d": {"k": 1}}}}
	var nn := Codex.code_newer.size()
	var nc := Codex.conflicts.size()
	_ok(Codex._take("t", "x", "a", 1, 2), "merge: only the codex changed it: the codex's value")
	_ok(not Codex._take("t", "x", "b", 2, 1) and Codex.code_newer.size() == nn + 1, "merge: only the code changed it: the code's value kept")
	_ok(Codex._take("t", "x", "c", 2, 3) and Codex.conflicts.size() == nc + 1, "merge: both changed it: the codex's, noted")
	_ok(not Codex._take("t", "x", "d", {"k": 2}, {"k": 1.0}), "merge: dictionaries and JSON floats compare by value")
	_ok(Codex._take("t", "y", "a", 5, 6), "merge: no base (never exported): the codex's value")
	Codex.code_newer.resize(nn)
	Codex.conflicts.resize(nc)
	Codex.overrides = Codex.overrides.filter(func(w): return not str(w).begins_with("t "))
	if saved == null:
		Codex._files.erase("code_base.json")
	else:
		Codex._files["code_base.json"] = saved
