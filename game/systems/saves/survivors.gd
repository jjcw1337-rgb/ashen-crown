class_name Survivors
extends RefCounted
## Survivors (Blaine's overhaul, 2026-11-06): run characters saved after a successful Battlegrounds extraction, the
## roster the Arena picks from. Each is its own file, `user://survivors/sv_<run uid>.json`, apart from the
## single-player characters (`user://characters/`), so neither touches the other. A run has one uid (RunBuild.uid):
## saving it again (a second press, a reconnect, the results reopened) finds its file and writes nothing new.
## Not tamper-proof: the file is the player's own, like every save today (docs/systems/multiplayer.md).

const DIR := "user://survivors/"
const PREFIX := "sv_"
## Tools point this elsewhere so they never touch a player's roster.
static var dir := DIR

static func id_for(run: RunBuild) -> String:
	return PREFIX + run.uid

static func is_survivor(id: String) -> bool:
	return id.begins_with(PREFIX)

static func _path(id: String) -> String:
	return dir + id + ".json"

static func exists(id: String) -> bool:
	return FileAccess.file_exists(_path(id))

## Save the hero's run as a survivor. Returns its id, and whether this call wrote it ([id, new]); a run already
## saved is left as it was.
static func save(hero, title: String) -> Array:
	if hero == null or hero.run == null:
		return ["", false]
	var id := id_for(hero.run)
	if exists(id):
		return [id, false]
	DirAccess.make_dir_recursive_absolute(dir)
	var d := {"id": id, "name": title, "cls": hero.cls, "level": hero.level, "saved": int(Time.get_unix_time_from_system()),
		"camps": hero.run.camps, "bosses": hero.run.bosses, "hero": hero.to_save()}
	var f := FileAccess.open(_path(id), FileAccess.WRITE)
	if f == null:
		return ["", false]
	f.store_string(JSON.stringify(d))
	f.close()
	return [id, true]

static func read(id: String) -> Dictionary:
	if not is_survivor(id) or id.contains("/") or not exists(id):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path(id)))
	return d if d is Dictionary and d.get("hero") is Dictionary and (d["hero"] as Dictionary).get("run") is Dictionary else {}

## Every survivor, the newest first.
static func list() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for fn in DirAccess.get_files_at(dir):
		if fn.ends_with(".json"):
			var d := read(fn.get_basename())
			if not d.is_empty():
				out.append(d)
	out.sort_custom(func(a, b): return int(a.get("saved", 0)) > int(b.get("saved", 0)))
	return out

static func remove(id: String) -> void:
	if exists(id) and is_survivor(id):
		DirAccess.remove_absolute(_path(id))

## Put a survivor on the hero (for the Arena): its class, level, skills and slots, passives, gear and consumables.
static func load_into(game, id: String) -> bool:
	var d := read(id)
	if d.is_empty():
		return false
	game.hero.from_save(d["hero"])
	game.char_id = id
	game.char_name = str(d.get("name", Data.CLASSES.get(game.hero.cls, {}).get("name", "Survivor")))
	return game.hero.run != null

## A survivor's card line: "Archer · Level 9 · 6 camps".
static func summary(d: Dictionary) -> String:
	var cls := str(d.get("cls", ""))
	return "%s  ·  Level %d  ·  %d camp%s%s" % [Data.CLASSES.get(cls, {}).get("name", cls), int(d.get("level", 0)),
		int(d.get("camps", 0)), "" if int(d.get("camps", 0)) == 1 else "s",
		("  ·  %d boss%s" % [int(d.get("bosses", 0)), "" if int(d.get("bosses", 0)) == 1 else "es"]) if int(d.get("bosses", 0)) > 0 else ""]
