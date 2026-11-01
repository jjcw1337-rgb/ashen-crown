class_name CloudSaves
extends Node
## Characters in Nakama (builds with BuildEnv.cloud() on: staging and production). The local files in
## Game.char_dir stay the game's working copy, so everything that reads and writes saves is unchanged; this keeps
## them and the player's Nakama account the same:
##   - on start it signs in (the device's Battlegrounds.client_id) and syncs: a character only on this PC, or newer
##     here (its "played" time), is uploaded (this is also the one-time migration of existing local saves); one only in
##     the account, or newer there, is written to this PC, so a character follows the player to any device;
##   - every Game.save_game is pushed, every deleted character removed.
## Offline (no connection, the server down) the game plays from the local files and the next start syncs again.
## Storage: collection "characters", key = the character id, value = the save; the owner reads and writes it.
## tools/cloud_test.gd checks it against a running Nakama.

const COLLECTION := "characters"

var game: Node
var nk: NakamaClient
var signed_in := false      # signed in
var synced := false
var last_sync := {"up": 0, "down": 0}
var device_id := ""

func _init(g: Node, url := "", key := "") -> void:
	game = g
	name = "CloudSaves"
	nk = NakamaClient.new(url, key)

func _ready() -> void:
	add_child(nk)

## Signs in once (again after a failure). True when signed in.
func ensure() -> bool:
	if signed_in:
		return true
	if device_id == "":
		device_id = Battlegrounds.client_id()
	signed_in = await nk.authenticate_device(device_id)
	if not signed_in:
		print("[Cloud] offline: ", nk.last_error)
	return signed_in

func sync() -> bool:
	if not await ensure():
		return false
	var remote := {}
	for o in await nk.list_objects(COLLECTION):
		remote[o["key"]] = o["value"]
	if nk.last_error != "":
		print("[Cloud] could not list characters: ", nk.last_error)
		return false
	var local := {}
	var dir := DirAccess.open(game.char_dir)
	if dir != null:
		for fn in dir.get_files():
			if fn.ends_with(".json"):
				var d = JSON.parse_string(FileAccess.get_file_as_string(game.char_dir + fn))
				if d is Dictionary:
					local[fn.get_basename()] = d
	var up := []
	for id in local:
		if not remote.has(id) or int(local[id].get("played", 0)) > int(remote[id].get("played", 0)):
			up.append({"collection": COLLECTION, "key": id, "value": local[id]})
	var down := 0
	for id in remote:
		if not local.has(id) or int(remote[id].get("played", 0)) > int(local[id].get("played", 0)):
			DirAccess.make_dir_recursive_absolute(game.char_dir)
			var f := FileAccess.open(game.char_dir + str(id) + ".json", FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(remote[id]))
				down += 1
	if not up.is_empty() and not await nk.write_objects(up):
		print("[Cloud] upload failed: ", nk.last_error)
		return false
	last_sync = {"up": up.size(), "down": down}
	synced = true
	print("[Cloud] synced %d character(s) up, %d down" % [up.size(), down])
	return true

func push(id: String, save: Dictionary) -> void:
	if id == "" or not await ensure():
		return
	if not await nk.write_objects([{"collection": COLLECTION, "key": id, "value": save}]):
		print("[Cloud] save of %s not uploaded: %s" % [id, nk.last_error])

func remove(id: String) -> void:
	if id == "" or not await ensure():
		return
	await nk.delete_objects([{"collection": COLLECTION, "key": id}])
