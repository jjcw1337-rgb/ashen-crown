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
##          its class's pool (RunBuild.passive_pool) as long as every fx key is one the game reads (FX_KEYS).
## A design entry never reaches the game. `tools/codex_export.gd` writes the files from the game's data.

const DIR := "res://data/codex/"
const SKILL_FIELDS := ["name", "desc", "mana", "cd", "use", "power", "range", "role", "rarity", "direction"]
const RITE_FIELDS := ["name", "text", "max", "fx", "rarity"]
## The fx keys a data-only rite may use: plain stats and percentages Hero.recalc / Hero.talent read for every class
## (Talents' header), plus the per-skill forms dmg:<skill>, cd:<skill>, cost:<skill>.
const FX_KEYS := ["dmg", "life_pct", "mana_pct", "armor_pct", "crit", "crit_dmg", "ias", "frw", "regen", "res", "ls",
	"str", "dex", "vit", "ene", "block", "mf", "buff_pow", "buff_dur", "block_dr", "cdr"]

static var _files := {}

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
			if e.has(k) and e[k] != null:
				s[k] = _num_like(s.get(k), e[k])

## Lay the codex's rites over a list of talents or passives (Talents._static_init per class tree,
## RunBuild._static_init for the generic ones).
static func apply_rites(list: Array, entries: Array) -> void:
	var by := {}
	for e in entries:
		if live(e):
			by[str(e["id"])] = e
	for t in list:
		var e = by.get(str(t["id"]))
		if e == null:
			continue
		for k in RITE_FIELDS:
			if e.has(k) and e[k] != null:
				t[k] = e[k].duplicate(true) if e[k] is Dictionary else _num_like(t.get(k), e[k])

## Live rites with no talent or generic passive behind them, ready for RunBuild.passive_pool.
static func extra_rites(cls: String, known: Dictionary) -> Array:
	var out := []
	for e in hero(cls).get("rites", []) + shared().get("rites", []):
		if not live(e) or known.has(str(e["id"])) or not data_only(e):
			continue
		out.append({"id": str(e["id"]), "name": str(e.get("name", e["id"])), "rarity": clampi(int(e.get("rarity", 0)), 0, 2),
			"max": maxi(1, int(e.get("max", 1))), "icon": str(e.get("icon", "t_star")), "fx": e.get("fx", {}).duplicate(true),
			"text": str(e.get("text", "")), "tree": str(e.get("direction", ""))})
	return out

## Can this rite work from its data alone (every fx key one the game already reads)?
static func data_only(e: Dictionary) -> bool:
	var fx = e.get("fx", {})
	if not (fx is Dictionary) or fx.is_empty():
		return false
	for k in fx:
		var key := str(k)
		if not (key in FX_KEYS or key.begins_with("dmg:") or key.begins_with("cd:") or key.begins_with("cost:")):
			return false
	return true

## JSON numbers are floats: keep an int an int where the game had one.
static func _num_like(old, v):
	if old is int and v is float and is_equal_approx(v, round(v)):
		return int(v)
	return v
