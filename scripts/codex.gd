class_name Codex
extends RefCounted
## The Hero Codex (Blaine, 2026-11-06): every hero's skills, rites (talents), gems and consumables as JSON in
## `res://data/codex/`, the one place they are designed. The codex web editor (tools/codex/server.py) reads and writes
## the same files, and the game applies them when its data loads, so an edit in the codex is an edit to the game:
##   heroes/<cls>.json  {cls, name, fantasy, directions: [{id, name, desc}], skills: [...], rites: [...]}
##   shared.json        {skills: [...], rites: [...]}: the shared skills and the passives every class can take
##   gems.json, consumables.json  {entries: [...]}
## Every entry has "id", "status" ("live": in the game now; "design": an idea the codex keeps until its code exists)
## and "rarity" (0 common, 1 uncommon, 2 rare: what a camp's chest can offer it as, RunBuild.roll_offer).
##   skill: name, desc, mana, cd, use, power, range, role, rarity, direction: laid over its Data.SKILLS entry
##   rite:  name, text, max, fx, rarity, direction: laid over its talent (Talents.TREES) or generic passive
##          (RunBuild.GENERIC). A live rite with no talent behind it is a new passive made of data alone: it joins
##          its class's pool (RunBuild.passive_pool) as long as every fx key is one the game reads (fx_keys.json: shared and the class's own).
## A design entry never reaches the game. `tools/codex_export.gd` writes the files from the game's data.
## Code edits are never lost to the codex (a three-way merge per field): code_base.json is what the code said for every
## field the codex lays over, as of the last export. A field the code has changed since then while the codex still says
## what the code said keeps the code's value (`code_newer`; the next export folds it into the codex); a field both
## changed takes the codex's (`conflicts`). tools/codex_test.gd prints both; tools/codex/server.py exports on Publish.

const DIR := "res://data/codex/"
const SKILL_FIELDS := ["name", "desc", "mana", "cd", "use", "power", "range", "role", "rarity", "direction"]
const RITE_FIELDS := ["name", "text", "max", "fx", "rarity", "k"]      # (k: a run talent's numbers, RunTalents)
## The fx keys a rite may use and still be live: fx_keys.json "any" (plain stats and percentages Hero.recalc /
## Hero.talent read for every class, plus the per-skill forms dmg:<skill>, cd:<skill>, cost:<skill>) and the class's
## own list (keys its skills script reads, e.g. WarlockHex.RITE_KEYS). The codex editor reads the same file.
static func fx_keys(cls := "") -> Array:
	var f := file("fx_keys.json")
	return Array(f.get("any", [])) + (Array(f.get(cls, [])) if cls != "" else [])

static var _files := {}
static var code_now := {}      # kind -> id -> field -> the code's own value (before the codex): the export's next base
static var code_newer := []    # "kind id.field": the code changed it since the last export, the codex didn't: code kept
static var conflicts := []     # "kind id.field": both changed it since the last export: the codex's value taken
static var overrides := []     # "kind id.field": where the game plays the codex's value instead of the code's

## A codex file parsed ({} when missing or broken: the game then plays on its built-in data).
static func file(rel: String) -> Dictionary:
	if _files.has(rel):
		return _files[rel]
	var out := {}
	var path := DIR + rel
	if FileAccess.file_exists(path):
		var p = JSON.parse_string(FileAccess.get_file_as_string(path))
		if p is Dictionary:
			out = p
		else:
			push_warning("Codex: %s is not valid JSON; using the built-in data" % path)
	_files[rel] = out
	return out

static func hero(cls: String) -> Dictionary:
	return file("heroes/%s.json" % cls)

static func shared() -> Dictionary:
	return file("shared.json")

static func live(e) -> bool:
	return e is Dictionary and str(e.get("status", "live")) == "live" and str(e.get("id", "")) != ""

## Every live skill entry by id, from every hero file and shared.json.
static func skill_entries() -> Dictionary:
	var out := {}
	var lists := [shared().get("skills", [])]
	for cls in _hero_ids():
		lists.append(hero(cls).get("skills", []))
	for l in lists:
		for e in l:
			if live(e):
				out[str(e["id"])] = e
	return out

static func _hero_ids() -> Array:
	var out := []
	var d := DirAccess.open(DIR + "heroes")
	if d == null:
		return out
	for f in d.get_files():
		var n := f.trim_suffix(".remap")      # (an exported build lists some files with .remap)
		if n.ends_with(".json"):
			out.append(n.get_basename())
	return out

## Lay the codex over Data.SKILLS (Data._static_init).
static func apply_skills(skills: Array) -> void:
	var by := skill_entries()
	if by.is_empty():
		return
	for s in skills:
		var e = by.get(str(s["id"]))
		if e == null:
			continue
		for k in SKILL_FIELDS:
			if e.has(k) and e[k] != null and _take("skills", str(s["id"]), k, s.get(k), e[k]):
				s[k] = _num_like(s.get(k), e[k])

## Lay the codex's rites over a list of talents or passives (Talents._static_init per class tree,
## RunBuild._static_init for the generic ones).
static func apply_rites(list: Array, entries: Array, kind := "rites") -> void:
	var by := {}
	for e in entries:
		if live(e):
			by[str(e["id"])] = e
	for t in list:
		var e = by.get(str(t["id"]))
		if e == null:
			continue
		for k in RITE_FIELDS:
			if e.has(k) and e[k] != null and _take(kind, str(t["id"]), k, t.get(k), e[k]):
				t[k] = e[k].duplicate(true) if e[k] is Dictionary else _num_like(t.get(k), e[k])

## Live rites with no talent or generic passive behind them, ready for RunBuild.passive_pool.
static func extra_rites(cls: String, known: Dictionary) -> Array:
	var out := []
	for e in hero(cls).get("rites", []) + shared().get("rites", []):
		if not live(e) or known.has(str(e["id"])) or not data_only(e, cls):
			continue
		var p := {"id": str(e["id"]), "name": str(e.get("name", e["id"])), "rarity": clampi(int(e.get("rarity", 0)), 0, 2),
			"max": maxi(1, int(e.get("max", 1))), "icon": str(e.get("icon", "")) if str(e.get("icon", "")) != "" else "t_star",
			"fx": e.get("fx", {}).duplicate(true), "text": str(e.get("text", "")), "tree": str(e.get("direction", "")),
			"theme": str(e.get("direction", "")).to_lower()}
		# offered only once one of these skills is his (RunBuild.roll_offer)
		if e.get("requires") is Array and not (e["requires"] as Array).is_empty():
			p["needs_any"] = Array(e["requires"]).map(func(x): return str(x))
		out.append(p)
	return out

## Can this rite work from its data (every fx key one the game reads, for every class or this class)?
static func data_only(e: Dictionary, cls := "") -> bool:
	var fx = e.get("fx", {})
	if not (fx is Dictionary) or fx.is_empty():
		return false
	var keys := fx_keys(cls)
	for k in fx:
		var key := str(k)
		if not (key in keys or key.begins_with("dmg:") or key.begins_with("cd:") or key.begins_with("cost:")):
			return false
	return true

## Does the codex's value go on this field? (the three-way merge above; it also notes the code's own value)
static func _take(kind: String, id: String, k: String, cur, v) -> bool:
	var rec: Dictionary = code_now.get_or_add(kind, {}).get_or_add(id, {})
	rec[k] = cur.duplicate(true) if (cur is Dictionary or cur is Array) else cur
	var base: Dictionary = file("code_base.json").get(kind, {}).get(id, {})
	var what := "%s %s.%s" % [kind, id, k]
	if base.has(k) and not same(cur, base[k]):
		if same(v, base[k]):
			code_newer.append(what)  # only the code moved since the export: keep it
			return false
		if not same(v, cur):
			conflicts.append(what)   # both moved: the codex (the designers' latest word) wins
	if cur != null and not same(cur, v):
		overrides.append(what)       # (a field the code doesn't have at all, e.g. a direction, isn't one)
	return true

## Equal as data (JSON's floats against the code's ints, dictionaries and arrays by content).
static func same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not same(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same(a[i], b[i]):
				return false
		return true
	if a == null or b == null:
		return a == null and b == null
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	return typeof(a) == typeof(b) and a == b

## JSON numbers are floats: keep an int an int where the game had one.
static func _num_like(old, v):
	if old is int and v is float and is_equal_approx(v, round(v)):
		return int(v)
	return v
