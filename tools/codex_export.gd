extends SceneTree
## Writes the Hero Codex (data/codex/, see scripts/codex.gd) from the game's own data: every class's skills
## (Data.SKILLS), its rites (Talents.TREES, its three directions), the shared skills and generic passives
## (RunBuild.GENERIC) and the consumables (Data.BASES potions). A file that exists keeps what only the codex has:
## design entries, a hero's fantasy and directions text, gems, and extra fields on live entries.
##   godot --headless --path . -s tools/codex_export.gd

const OUT := "res://data/codex/"

func _init() -> void:
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
			skills.append(_skill(s))
		var rites := []
		var dirs := []
		for tree in trees:
			dirs.append({"id": str(tree["name"]), "name": str(tree["name"]), "desc": str(tree.get("desc", ""))})
			for t in tree["talents"]:
				rites.append(_rite(t, str(tree["name"]), clampi(int(t["rarity"]), 0, 2) if t.has("rarity") else [0, 0, 1, 2][clampi(int(t["row"]), 0, 3)]))
		var c: Dictionary = Data.CLASSES[cls]
		var d := {"cls": cls, "name": str(c.get("name", cls)), "fantasy": str(old.get("fantasy", c.get("desc", ""))),
			"directions": _merge_dirs(old.get("directions", []), dirs),
			"skills": _merge(old.get("skills", []), skills), "rites": _merge(old.get("rites", []), rites)}
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
	if not FileAccess.file_exists(OUT + "gems.json"):
		_write("gems.json", {"entries": []})
	print("[codex_export] %d heroes, %d shared skills, %d generic rites, %d consumables" % [n, ss.size(), gr.size(), cl.size()])
	quit()

func _skill(s: Dictionary) -> Dictionary:
	var e := {"id": str(s["id"]), "status": "live", "name": str(s["name"]), "rarity": RunBuild.skill_rarity(s),
		"direction": str(s.get("direction", "")), "desc": str(s.get("desc", ""))}
	for k in ["mana", "cd", "use", "power", "range", "role", "tags", "lvl"]:
		if s.has(k):
			e[k] = s[k]
	return e

func _rite(t: Dictionary, dir: String, rarity: int) -> Dictionary:
	return {"id": str(t["id"]), "status": "live", "name": str(t["name"]), "rarity": rarity, "direction": dir,
		"max": int(t["max"]), "fx": t["fx"].duplicate(true), "text": str(t.get("text", "")), "icon": str(t.get("icon", ""))}

## Live entries from the game, in the game's order, each keeping fields only the codex has; then the codex's own
## entries (design, or live data-only rites) in their order.
func _merge(old: Array, fresh: Array) -> Array:
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
		if o.has("direction") and str(e.get("direction", "")) == "":
			e["direction"] = o["direction"]
		out.append(e)
		seen[e["id"]] = true
	for e in old:
		if e is Dictionary and not seen.has(str(e.get("id", ""))):
			out.append(e)
	return out

func _merge_dirs(old: Array, fresh: Array) -> Array:
	return old if old.size() > 0 else fresh

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
