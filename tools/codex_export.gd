extends SceneTree
## Writes the Hero Codex (data/codex/, see scripts/codex.gd) from the game's own data: every class's skills
## (Data.SKILLS), its rites (Talents.TREES, its three directions), the shared skills and generic passives
## (RunBuild.GENERIC) and the consumables (Data.BASES potions). A file that exists keeps what only the codex has:
## design entries, a hero's fantasy and directions text, gems, and extra fields on live entries.
## It also writes code_base.json (what the code says, the base of Codex's three-way merge), so run it after changing a
## skill's or talent's numbers or text in code: the game already plays the code's change, the export puts it in the codex.
##   godot --headless --path . -s tools/_late.gd -- res://tools/codex_export.gd   (after the autoloads: RunTalents needs them)

const OUT := "res://data/codex/"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "heroes"))
	var n := 0
	for cls in Data.CLASSES:
		var own := Data.skills_for(cls)
		var trees: Array = Talents.TREES.get(cls, [])
		if own.is_empty() and trees.is_empty():
			continue
		var path := "heroes/%s.json" % cls
		var old := _read(path)
		var skills := []
		for s in own:
			var e0 := _skill(s)
			if str(e0["direction"]) == "":
				e0["direction"] = _theme_name(cls, str(RunTalents.SKILL_THEMES.get(str(s["id"]), "")))
			skills.append(e0)
		for s in Data.run_skills_for(cls):
			var e := _skill(s)
			e["run"] = true      # (a run-only skill, Data.RUN_SKILLS)
			e["direction"] = _theme_name(cls, str(RunTalents.SKILL_THEMES.get(str(s["id"]), "")))
			skills.append(e)
		var rites := []
		var dirs := []
		# the class's three directions: its run themes (RunTalents.THEMES) when it has them, else its talent trees
		var tt: Array = RunTalents.TREE_THEME.get(cls, [])
		for th in RunTalents.THEMES.get(cls, []):
			dirs.append({"id": str(th["name"]), "name": str(th["name"]), "desc": str(th.get("desc", ""))})
		for ti in trees.size():
			var tree: Dictionary = trees[ti]
			var dn: String = _theme_name(cls, str(tt[ti])) if ti < tt.size() else ""
			if dn == "":
				dn = str(tree["name"])
			if not RunTalents.THEMES.has(cls):
				dirs.append({"id": dn, "name": dn, "desc": str(tree.get("desc", ""))})
			for t in tree["talents"]:
				rites.append(_rite(t, dn, clampi(int(t["rarity"]), 0, 2) if t.has("rarity") else [0, 0, 1, 2][clampi(int(t["row"]), 0, 3)]))
		for t in RunTalents.TALENTS:
			if str(t["cls"]) != "any" and str(t["cls"]).split(",").has(cls):
				rites.append(_run_rite(t, cls))
		var c: Dictionary = Data.CLASSES[cls]
		var d := {"cls": cls, "name": str(c.get("name", cls)), "fantasy": str(old.get("fantasy", c.get("desc", ""))),
			"directions": _merge_dirs(old.get("directions", []), dirs),
			"skills": [], "rites": []}
		var names := {}
		for dd in d["directions"]:
			names[str(dd["id"])] = true
		d["skills"] = _merge(old.get("skills", []), skills, names)
		d["rites"] = _merge(old.get("rites", []), rites, names)
		for k in old:
			if not d.has(k):
				d[k] = old[k]
		_write(path, d)
		n += 1
	var sh := _read("shared.json")
	var ss := []
	for s in Data.shared_skills():
		ss.append(_skill(s))
	var gr := []
	for p in RunBuild.GENERIC:
		gr.append(_rite(p, "", int(p["rarity"])))
	for t in RunTalents.TALENTS:
		if str(t["cls"]) == "any":
			gr.append(_run_rite(t, ""))
	_write("shared.json", {"skills": _merge(sh.get("skills", []), ss), "rites": _merge(sh.get("rites", []), gr)})
	var co := _read("consumables.json")
	var cl := []
	for k in Data.BASES:
		var b: Dictionary = Data.BASES[k]
		if str(b.get("slot", "")) != "potion":
			continue
		var e := {"id": k, "name": str(b["name"]), "status": "live", "kind": "consumable", "rarity": 0}
		for f in ["heal", "mana", "invis", "rejuv"]:
			if b.has(f):
				e[f] = b[f]
		cl.append(e)
	_write("consumables.json", {"entries": _merge(co.get("entries", []), cl)})
	var ge := _read("gems.json")
	var gl := []
	for gm in RunTalents.GEMS:
		var e := {"id": str(gm["id"]), "status": "live", "name": str(gm["name"]), "rarity": int(gm.get("rarity", 0)),
			"color": "#" + (gm["color"] as Color).to_html(false) if gm.get("color") is Color else "#888888",
			"fx": gm.get("fx", {}).duplicate(true), "text": str(gm.get("text", ""))}
		for k in gm:
			if not e.has(k) and k != "color" and (gm[k] is String or gm[k] is float or gm[k] is int or gm[k] is Dictionary):
				e[k] = gm[k]
		gl.append(e)
	var gd := {"about": str(ge.get("about", "")), "entries": _merge(ge.get("entries", []), gl)}
	_write("gems.json", gd)
	# what the code says for every field the codex lays over: the next load's three-way merge base (Codex._take)
	_write("code_base.json", {"about": "Written by tools/codex_export.gd: the code's own values when the codex was last exported. Don't edit.",
		"skills": Codex.code_now.get("skills", {}), "rites": Codex.code_now.get("rites", {}), "gems": Codex.code_now.get("gems", {})})
	print("[codex_export] %d heroes, %d shared skills, %d generic rites, %d consumables" % [n, ss.size(), gr.size(), cl.size()])
	quit()

func _skill(s: Dictionary) -> Dictionary:
	var e := {"id": str(s["id"]), "status": "live", "name": str(s["name"]), "rarity": RunBuild.skill_rarity(s),
		"direction": str(s.get("direction", "")), "desc": str(s.get("desc", ""))}
	for k in ["mana", "cd", "use", "power", "range", "role", "tags", "lvl"]:
		if s.has(k):
			e[k] = s[k]
	return e

## A run talent (RunTalents.TALENTS): its numbers are "k" (the text's {keys}), what it does is its "proc".
func _run_rite(t: Dictionary, cls: String) -> Dictionary:
	var e := {"id": str(t["id"]), "status": "live", "name": str(t["name"]), "rarity": int(t.get("rarity", 0)), "run": true,
		"direction": _theme_name(cls, str(t.get("theme", ""))), "max": int(t.get("max", 1)), "text": str(t.get("text", "")),
		"icon": str(t.get("icon", ""))}
	for k in ["k", "fx", "per", "proc"]:
		if t.has(k):
			e[k] = t[k].duplicate(true) if (t[k] is Dictionary or t[k] is Array) else t[k]
	return e

func _theme_name(cls: String, theme: String) -> String:
	for th in RunTalents.THEMES.get(cls, []):
		if str(th["id"]) == theme:
			return str(th["name"])
	return ""

func _rite(t: Dictionary, dir: String, rarity: int) -> Dictionary:
	return {"id": str(t["id"]), "status": "live", "name": str(t["name"]), "rarity": rarity, "direction": dir,
		"max": int(t["max"]), "fx": t["fx"].duplicate(true), "text": str(t.get("text", "")), "icon": str(t.get("icon", ""))}

## Live entries from the game, in the game's order, each keeping fields only the codex has; then the codex's own
## entries (design, or live data-only rites) in their order.
func _merge(old: Array, fresh: Array, dir_names := {}) -> Array:
	var by := {}
	for e in old:
		if e is Dictionary and e.has("id"):
			by[str(e["id"])] = e
	var out := []
	var seen := {}
	for e in fresh:
		var o: Dictionary = by.get(e["id"], {})
		for k in o:
			if not e.has(k):
				e[k] = o[k]
		if str(o.get("direction", "")) != "" and (dir_names.is_empty() or dir_names.has(str(o["direction"]))):
			e["direction"] = o["direction"]      # (the codex may file an entry under another direction than its tree)
		out.append(e)
		seen[e["id"]] = true
	for e in old:
		if e is Dictionary and not seen.has(str(e.get("id", ""))):
			out.append(e)
	return out

## The codex's own directions text wins where the names match; the game's run themes decide which there are.
func _merge_dirs(old: Array, fresh: Array) -> Array:
	if fresh.is_empty():
		return old
	var by := {}
	for o in old:
		by[str(o.get("id", ""))] = o
	var out := []
	for f in fresh:
		out.append(by.get(str(f["id"]), f))
	return out

func _read(rel: String) -> Dictionary:
	var p := OUT + rel
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}

func _write(rel: String, d: Dictionary) -> void:
	var f := FileAccess.open(OUT + rel, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t", false) + "\n")
	f.close()
