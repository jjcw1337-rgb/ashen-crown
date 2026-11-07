class_name SharedStash
extends RefCounted
## The camp's stash, one for the whole player (jj, 2026-11-02): every character on this PC shares it, TABS tabs of
## SLOTS. It lives in its own file (PATH, `Game.stash`), never in a character's save, and only the camp's stash chest
## opens it (never in a raid), so nothing in it is ever at stake.
##
## No duplicates. An item moving between a character and the stash is written to two files, so a crash or a closed
## game between the two writes would leave it in both or in neither. The rule that makes it always "both, and the
## stash's copy wins":
##   - an item going into the stash gets a new "uid" (`stamp`) and the character is saved with it stamped, still in
##     the bag; then the stash is saved with it, then the character without it (Game.stash_deposit);
##   - an item coming out keeps its uid, and the character is saved FIRST, then the stash;
##   - `reconcile` takes out of a character anything whose uid is in the stash. Game runs it on every character file
##     at start (`Game._stash_start`, before any can be played) and on the one being loaded (`Game.load_game`).
## A second copy of the game open at once: every change first re-reads the file if its `rev` moved (`fresh`), so one
## copy never hands out an item the other already took. The file is written whole through a temporary file and a
## rename, so it's never left half-written. Old saves: each character's own stash (Hero.stash, 60 slots) is stamped,
## moved in and reconciled away the same way (`adopt`), so a crash mid-move can't bring it in twice.
## What it can't stop: someone editing or restoring their own files (saves are the player's; see docs/systems/combat.md, "Who decides").

const TABS := 5
const SLOTS := 60
const PATH := "user://stash.json"
const TEST_PATH := "user://ashen_crown_test_stash.json"

var path := PATH
var tabs: Array = []          # TABS Arrays of SLOTS: an item Dictionary or null
var rev := 0                  # bumped by every save; another copy of the game compares it (fresh)
var pushed: Callable          # (the cloud backup: Game sets it; called with the saved Dictionary)

func _init(p := PATH) -> void:
	path = p
	_empty()
	load_file()

func _empty() -> void:
	tabs = []
	for t in TABS:
		var a := []
		a.resize(SLOTS)
		tabs.append(a)

func load_file() -> void:
	if not FileAccess.file_exists(path):
		_empty()
		rev = 0
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return            # (unreadable: keep what's in memory rather than wipe it)
	from_dict(d)

func from_dict(d: Dictionary) -> void:
	_empty()
	rev = int(d.get("rev", 0))
	var src: Array = d.get("tabs", []) if d.get("tabs") is Array else []
	for t in mini(src.size(), TABS):
		var row: Array = src[t] if src[t] is Array else []
		for i in mini(row.size(), SLOTS):
			if row[i] is Dictionary and row[i].has("base") and Data.BASES.has(row[i]["base"]):
				tabs[t][i] = row[i]
	Items.upgrade_all(tabs)

func to_dict() -> Dictionary:
	return {"v": 1, "rev": rev, "tabs": tabs}

## The file's rev, without loading it (-1: no file).
func disk_rev() -> int:
	if not FileAccess.file_exists(path):
		return -1
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return int(d.get("rev", 0)) if d is Dictionary else -1

## Before any change: if another copy of the game saved the stash since we read it, read it again. True if it moved.
func fresh() -> bool:
	var r := disk_rev()
	if r >= 0 and r != rev:
		load_file()
		return true
	return false

func save() -> bool:
	rev += 1
	var d := to_dict()
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		return false
	if pushed.is_valid():
		pushed.call(d)
	return true

static func stamp(it: Dictionary) -> void:
	it["uid"] = "%08x%08x%08x" % [randi(), randi(), Time.get_ticks_usec() & 0xffffffff]

func uids() -> Dictionary:
	var out := {}
	for row in tabs:
		for it in row:
			if it is Dictionary and it.has("uid"):
				out[str(it["uid"])] = true
	return out

func free_slot(tab: int) -> int:
	return (tabs[tab] as Array).find(null)

func tab_count(tab: int) -> int:
	var n := 0
	for it in tabs[tab]:
		if it != null:
			n += 1
	return n

func count() -> int:
	var n := 0
	for row in tabs:
		for it in row:
			if it != null:
				n += 1
	return n

## Takes out of a hero's save (Hero.to_save's Dictionary: equipment, inventory, belt, old stash) every item whose
## uid is in the stash: a copy a crash left behind. Returns how many it took.
func reconcile(h: Dictionary, ids := {}) -> int:
	if ids.is_empty():
		ids = uids()
	if ids.is_empty():
		return 0
	var n := 0
	var eq = h.get("equipment")
	if eq is Dictionary:
		for slot in eq.keys():
			if _stashed(eq[slot], ids):
				eq[slot] = null
				n += 1
	for key in ["inventory", "belt", "stash"]:
		var a = h.get(key)
		if a is Array:
			for i in (a as Array).size():
				if _stashed(a[i], ids):
					a[i] = null
					n += 1
	return n

static func _stashed(it, ids: Dictionary) -> bool:
	return it is Dictionary and it.has("uid") and ids.has(str(it["uid"]))

## A character's own stash from before the shared one (Hero.stash, an Array): every item is stamped (the caller has
## saved the character with those stamps first), moved into the first free slots and the stash saved; the caller
## then reconciles the character, which takes the moved ones out. What doesn't fit stays where it was. Returns how
## many moved.
func adopt(old: Array) -> int:
	var n := 0
	for it in old:
		if not (it is Dictionary) or not it.has("uid") or uids().has(str(it["uid"])):
			continue
		var placed := false
		for t in TABS:
			var s := free_slot(t)
			if s >= 0:
				tabs[t][s] = it
				placed = true
				n += 1
				break
		if not placed:
			break
	if n > 0:
		save()
	return n
