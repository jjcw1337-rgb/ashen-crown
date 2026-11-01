extends SceneTree
## Cloud saves (cloud_saves.gd) and the Battlegrounds stash rules against a running Nakama with the game's module:
##   godot --headless --path . -s tools/cloud_test.gd -- http://127.0.0.1:7350 <server_key> [<http_key>]
## Uses a scratch character folder and throwaway devices, never the player's saves. Exits 1 on any failure.

var g
var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[CL] " + ("ok   " if ok else "FAIL ") + what)

func _initialize():
	BuildEnv.forced = {"cloud": "0"}     # the game itself stays local; the test drives its own CloudSaves
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _write(id: String, d: Dictionary) -> void:
	var f := FileAccess.open(g.char_dir + id + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()

func _read(id: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(g.char_dir + id + ".json")) if FileAccess.file_exists(g.char_dir + id + ".json") else null
	return d if d is Dictionary else {}

func _clear() -> void:
	var dir := DirAccess.open(g.char_dir)
	if dir:
		for fn in dir.get_files():
			DirAccess.remove_absolute(g.char_dir + fn)

func _run() -> void:
	for i in 30:
		await process_frame
	var a := OS.get_cmdline_user_args()
	var url: String = a[0] if a.size() > 0 else "http://127.0.0.1:7350"
	var key: String = a[1] if a.size() > 1 else "defaultkey"
	var http_key: String = a[2] if a.size() > 2 else ""
	g.char_dir = "user://cloud_test_chars/"
	DirAccess.make_dir_recursive_absolute(g.char_dir)
	_clear()
	var cs := CloudSaves.new(g, url, key)
	cs.device_id = "cloud-test-" + Crypto.new().generate_random_bytes(8).hex_encode()
	get_root().add_child(cs)
	await process_frame
	# migration: two characters only on this PC go up
	_write("c_one", {"name": "One", "played": 100, "hero": {"cls": "knight", "level": 3}})
	_write("c_two", {"name": "Two", "played": 200, "hero": {"cls": "wraith", "level": 5}})
	check(await cs.sync(), "signed in and synced")
	check(cs.last_sync["up"] == 2 and cs.last_sync["down"] == 0, "both local characters uploaded (%s)" % cs.last_sync)
	var remote: Array = await cs.nk.list_objects(CloudSaves.COLLECTION)
	check(remote.size() == 2, "the account holds them (%d)" % remote.size())
	# played again here: only the newer one goes up
	_write("c_one", {"name": "One", "played": 300, "hero": {"cls": "knight", "level": 4}})
	await cs.sync()
	check(cs.last_sync["up"] == 1, "a newer local save is uploaded (%s)" % cs.last_sync)
	# a new PC (no local files): everything comes down, the newest copy
	_clear()
	await cs.sync()
	check(cs.last_sync["down"] == 2 and int(_read("c_one").get("played", 0)) == 300, "a fresh PC gets every character, the newest copy")
	# played on another device: the newer account copy wins
	await cs.nk.write_objects([{"collection": CloudSaves.COLLECTION, "key": "c_two", "value": {"name": "Two", "played": 999, "hero": {"cls": "wraith", "level": 9}}}])
	await cs.sync()
	check(int(_read("c_two").get("played", 0)) == 999, "a newer save from another device comes down")
	# Game.save_game's push
	await cs.push("c_three", {"name": "Three", "played": 1000})
	remote = await cs.nk.list_objects(CloudSaves.COLLECTION)
	check(remote.size() == 3, "a save is pushed (%d in the account)" % remote.size())
	await cs.remove("c_three")
	remote = await cs.nk.list_objects(CloudSaves.COLLECTION)
	check(remote.size() == 2, "a deleted character leaves the account (%d)" % remote.size())
	# another player's device can't see these
	var other := NakamaClient.new(url, key)
	get_root().add_child(other)
	await other.authenticate_device("cloud-test-other-" + Crypto.new().generate_random_bytes(8).hex_encode())
	var theirs: Array = await other.list_objects(CloudSaves.COLLECTION)
	check(theirs.is_empty(), "another account sees none of them")
	# the Battlegrounds stash: a player can't write it, only the game server
	var ok_rpc: Dictionary = await other.server_rpc("bg_stash_write", {"user_id": other.user_id, "items": [{"base": "gold", "count": 99999}]}, "wrong-key")
	check(not ok_rpc.get("ok", false), "a wrong key can't write a stash")
	var bearer: Dictionary = await other._call(HTTPClient.METHOD_POST, "/v2/rpc/bg_stash_write?unwrap", {"user_id": other.user_id, "items": []})
	check(not bearer.get("ok", false), "a player's own session can't call the server RPC (%s)" % other.last_error.substr(0, 40))
	if http_key != "":
		var w: Dictionary = await other.server_rpc("bg_stash_write", {"user_id": other.user_id, "items": [{"base": "gold", "count": 7}]}, http_key)
		check(w.get("ok", false), "the server key writes a stash")
		var mine: Dictionary = await other.read_object("battlegrounds", "stash")
		check(mine.get("items", []).size() == 1, "the player can read their own stash")
		var direct: bool = await other.write_objects([{"collection": "battlegrounds", "key": "stash", "value": {"items": []}}])
		check(not direct, "but can't overwrite it themselves")
	# tidy up the test account's characters
	await cs.remove("c_one")
	await cs.remove("c_two")
	_clear()
	print("[CL] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
